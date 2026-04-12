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

-- Models that should be routed to the task GPU (1080 Ti)
local TASK_MODELS = {
  ["igorls/gemma-4-E4B-it-heretic-GGUF:latest"] = true,
  ["igorls/gemma-4-E4B-it-heretic-GGUF"] = true,
}

function envoy_on_request(handle)
  local path = handle:headers():get(":path") or ""
  local method = handle:headers():get(":method") or ""
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "path", path)
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "method", method)

  -- Default: route to main ollama (3090)
  local cluster = "ollama_3090"

  -- Buffer and store the request body for chat/generate endpoints
  if method == "POST" and (path == "/api/generate" or path == "/api/chat") then
    local body = handle:body()
    if body then
      local raw = body:getBytes(0, body:length())
      if raw and #raw > 0 then
        handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "request_body", raw)

        -- Route task models to the 1080 Ti instance
        local model = raw:match('"model"%s*:%s*"([^"]*)"')
        if model and TASK_MODELS[model] then
          cluster = "ollama_1080ti"
        end
      end
    end
  end

  handle:headers():add("x-ollama-cluster", cluster)
end

-- Response handler: log request-side info only (model, prompt) without buffering
-- the response body. Buffering the response via handle:body() blocks streaming
-- to Open WebUI. Response-side stats (tokens, TPS) are captured from Ollama's
-- own container logs via Promtail.
function envoy_on_response(handle)
  local meta = handle:streamInfo():dynamicMetadata():get("envoy.filters.http.lua")
  if not meta then return end
  local path = meta["path"] or ""
  local method = meta["method"] or ""

  if method ~= "POST" then return end
  if path ~= "/api/generate" and path ~= "/api/chat" then return end

  local endpoint = path:gsub("/api/", "")
  local request_body = meta["request_body"] or ""
  local prompt = extract_prompt(request_body, endpoint) or ""

  -- Extract model name from the request body
  local model = request_body:match('"model"%s*:%s*"([^"]*)"') or "unknown"

  handle:logInfo(string.format(
    'ollama_request model=%s endpoint=%s prompt="%s"',
    model, endpoint, logfmt_escape(prompt)
  ))
end
