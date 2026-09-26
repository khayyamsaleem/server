-- ComfyUI proxy filter: take a gpu-yield video lease before every prompt
-- submission. The lease unloads Ollama, frees Forge's RAM and verifies host
-- memory; it is released by gpu-yield once ComfyUI's queue drains.
--
-- Fails closed: a video job without the lease can exhaust host RAM (a 16G
-- ComfyUI next to a loaded Forge caused a host-wide OOM), so if gpu-yield is
-- down or refuses, the prompt is rejected.

local PROMPT_PATHS = {
  ["/prompt"] = true,
  ["/api/prompt"] = true,
}

function envoy_on_request(handle)
  local method = handle:headers():get(":method") or ""
  local path = handle:headers():get(":path") or ""
  if method ~= "POST" or not PROMPT_PATHS[path] then
    return
  end

  local headers, body = handle:httpCall("gpu_yield", {
    [":method"] = "POST",
    [":path"] = "/lease",
    [":authority"] = "gpu-yield",
    ["content-type"] = "application/json",
  }, "{}", 120000)
  local status = headers and headers[":status"] or "none"
  handle:logInfo(string.format("comfy_filter: lease status=%s %s", status, body or ""))

  if status ~= "200" then
    handle:respond({[":status"] = "503", ["content-type"] = "application/json"},
      body or '{"error":"gpu-yield unavailable; refusing video job"}')
  end
end
