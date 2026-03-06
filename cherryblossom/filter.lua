function envoy_on_request(handle)
  local path = handle:headers():get(":path") or ""
  local method = handle:headers():get(":method") or ""
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "path", path)
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "method", method)
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

  local last_line = raw
  for line in raw:gmatch("[^\n]+") do
    last_line = line
  end

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
  local endpoint = path:gsub("/api/", "")

  local tps = 0
  if eval_dur > 0 then
    tps = eval_tokens / (eval_dur / 1e9)
  end
  local total_sec = total_dur / 1e9

  handle:logInfo(string.format(
    "ollama_inference model=%s endpoint=%s prompt_tokens=%d completion_tokens=%d total_duration_s=%.3f tokens_per_second=%.2f",
    model, endpoint, prompt_tokens, eval_tokens, total_sec, tps
  ))
end
