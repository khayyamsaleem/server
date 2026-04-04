-- Escape a string for safe embedding in a logfmt value.
-- Replaces newlines and quotes so the entire value stays on one log line.
local function logfmt_escape(s)
  if not s then return "" end
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '')
  return s
end

-- Extract the user prompt from an Ollama /api/chat or /api/generate request body.
-- For /api/chat: takes the last message with role "user".
-- For /api/generate: takes the "prompt" field.
local function extract_prompt(raw, endpoint)
  if endpoint == "chat" then
    -- Find all user messages, take the last one
    local last_content = nil
    for content in raw:gmatch('"role"%s*:%s*"user"%s*,%s*"content"%s*:%s*"([^"]*)"') do
      last_content = content
    end
    if not last_content then
      -- Try alternate key order: content before role
      for content in raw:gmatch('"content"%s*:%s*"([^"]*)"%s*,%s*"role"%s*:%s*"user"') do
        last_content = content
      end
    end
    return last_content
  elseif endpoint == "generate" then
    return raw:match('"prompt"%s*:%s*"([^"]*)"')
  end
  return nil
end

function envoy_on_request(handle)
  local path = handle:headers():get(":path") or ""
  local method = handle:headers():get(":method") or ""
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "path", path)
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "method", method)

  -- Buffer and store the request body for chat/generate endpoints
  if method == "POST" and (path == "/api/generate" or path == "/api/chat") then
    local body = handle:body()
    if body then
      local raw = body:getBytes(0, body:length())
      if raw and #raw > 0 then
        handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "request_body", raw)
      end
    end
  end
end

function envoy_on_response(handle)
  local meta = handle:streamInfo():dynamicMetadata():get("envoy.filters.http.lua")
  if not meta then return end
  local path = meta["path"] or ""
  local method = meta["method"] or ""

  if method ~= "POST" then return end
  if path ~= "/api/generate" and path ~= "/api/chat" then return end

  local body = handle:body()
  if not body then return end
  local raw = body:getBytes(0, body:length())
  if not raw or #raw == 0 then return end

  -- Collect the full response text from the streamed NDJSON chunks.
  -- Each line is a JSON object with a "message.content" (chat) or "response" (generate) field.
  local response_parts = {}
  local last_line = raw
  local endpoint = path:gsub("/api/", "")
  for line in raw:gmatch("[^\n]+") do
    last_line = line
    if endpoint == "chat" then
      local chunk = line:match('"content"%s*:%s*"([^"]*)"')
      if chunk then table.insert(response_parts, chunk) end
    elseif endpoint == "generate" then
      local chunk = line:match('"response"%s*:%s*"([^"]*)"')
      if chunk then table.insert(response_parts, chunk) end
    end
  end
  local full_response = table.concat(response_parts)

  local function extract_num(s, field)
    local pattern = '"' .. field .. '":%s*(%d+%.?%d*)'
    local val = s:match(pattern)
    return val and tonumber(val) or nil
  end

  local function extract_str(s, field)
    local pattern = '"' .. field .. '":%s*"([^"]*)'
    return s:match(pattern)
  end

  local model = extract_str(last_line, "model") or "unknown"
  local prompt_tokens = extract_num(last_line, "prompt_eval_count") or 0
  local eval_tokens = extract_num(last_line, "eval_count") or 0
  local total_dur = extract_num(last_line, "total_duration") or 0
  local eval_dur = extract_num(last_line, "eval_duration") or 0

  local tps = 0
  if eval_dur > 0 then
    tps = eval_tokens / (eval_dur / 1e9)
  end
  local total_sec = total_dur / 1e9

  -- Extract prompt from the stored request body
  local request_body = meta["request_body"] or ""
  local prompt = extract_prompt(request_body, endpoint) or ""

  handle:logInfo(string.format(
    'ollama_inference model=%s endpoint=%s prompt_tokens=%d completion_tokens=%d total_duration_s=%.3f tokens_per_second=%.2f prompt="%s" response="%s"',
    model, endpoint, prompt_tokens, eval_tokens, total_sec, tps,
    logfmt_escape(prompt), logfmt_escape(full_response)
  ))
end
