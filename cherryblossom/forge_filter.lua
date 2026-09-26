-- Forge proxy filter: dynamically inject ADetailer for SDXL/Pony models.
-- Flux does not support ADetailer (causes NaN), so it is stripped for Flux.
-- Also yields the GPU from Ollama around generations via gpu-yield.

-- Models that support ADetailer (SDXL-based inpainting)
local ADETAILER_MODELS = {
  ["ponyDiffusionV6XL"] = true,
  ["cyberrealisticPony_v18"] = true,
  ["sd_xl_base_1.0"] = true,
}

local ADETAILER_CONFIG = [[,"alwayson_scripts":{"ADetailer":{"args":[{"ad_model":"hand_yolov8n.pt","ad_confidence":0.4,"ad_denoising_strength":0.35,"ad_inpaint_only_masked":true,"ad_inpaint_only_masked_padding":32},{"ad_model":"face_yolov8n.pt","ad_confidence":0.3,"ad_denoising_strength":0.4,"ad_inpaint_only_masked":true,"ad_inpaint_only_masked_padding":32}]}}]]

-- Per-checkpoint sampler settings that override OWUI's global AUTOMATIC1111_PARAMS.
-- CyberRealistic Pony's recommended CFG 5 / 30+ steps; a fixed-seed A/B vs CFG 7 /
-- 25 steps removed censor-sticker artifacts (3/6 -> 0/6). Clip skip is not set:
-- Forge ignores it for SDXL-based checkpoints (outputs were byte-identical).
local SAMPLER_OVERRIDES = {
  ["ponyDiffusionV6XL"] = { cfg_scale = "5", steps = "30" },
  ["cyberrealisticPony_v18"] = { cfg_scale = "5", steps = "30" },
}

-- Set a top-level numeric field in a JSON body, adding it if absent.
local function set_number(raw, key, value)
  local pattern = '"' .. key .. '"%s*:%s*[%d%.]+'
  if raw:find(pattern) then
    return (raw:gsub(pattern, '"' .. key .. '": ' .. value, 1))
  end
  return (raw:gsub("}%s*$", ',"' .. key .. '": ' .. value .. "}", 1))
end

-- Cached model name (Lua globals persist across requests within worker thread)
local cached_model = nil

-- Generation endpoints that need the GPU to themselves. gpu-yield unloads the
-- Ollama model before these and reloads it before the response is returned, so
-- the follow-up chat turn (native tool calling) finds the model already warm.
local GPU_PATHS = {
  ["/sdapi/v1/txt2img"] = true,
  ["/sdapi/v1/img2img"] = true,
}

-- Fails open: if gpu-yield is down the request proceeds as before.
local function gpu_yield(handle, action, timeout_ms)
  local headers, body = handle:httpCall("gpu_yield", {
    [":method"] = "POST",
    [":path"] = "/" .. action,
    [":authority"] = "gpu-yield",
    ["content-type"] = "application/json",
  }, "{}", timeout_ms)
  local status = headers and headers[":status"] or "none"
  handle:logInfo(string.format("forge_filter: gpu-yield %s status=%s %s", action, status, body or ""))
  return status, body
end

-- Inject or strip ADetailer and apply sampler overrides for the active checkpoint.
local function rewrite_txt2img(handle)
  local body = handle:body()
  if not body then return end
  local raw = body:getBytes(0, body:length())
  if not raw or #raw == 0 then return end

  local prompt = raw:match('"prompt"%s*:%s*"(.-[^\\])"') or raw:match('"prompt"%s*:%s*"([^"]*)"') or "(unknown)"
  local neg = raw:match('"negative_prompt"%s*:%s*"(.-[^\\])"') or raw:match('"negative_prompt"%s*:%s*"([^"]*)"') or ""
  local model_log = cached_model or "(unknown)"
  handle:logInfo(string.format('forge_filter: txt2img model=%s prompt="%s" negative="%s"',
    model_log, prompt:sub(1, 300), neg:sub(1, 150)))

  if not cached_model then
    return
  end

  local has_alwayson = raw:find('"alwayson_scripts"')
  local modified = nil

  if ADETAILER_MODELS[cached_model] and not has_alwayson then
    modified = raw:gsub("}%s*$", ADETAILER_CONFIG .. "}")
    handle:logInfo("forge_filter: injected ADetailer for model=" .. cached_model)
  elseif not ADETAILER_MODELS[cached_model] and has_alwayson then
    modified = raw:gsub(',%s*"alwayson_scripts"%s*:%s*%b{}', '')
    if modified == raw then modified = nil end
    if modified then
      handle:logInfo("forge_filter: stripped ADetailer for model=" .. cached_model)
    end
  end

  local overrides = SAMPLER_OVERRIDES[cached_model]
  if overrides then
    local tuned = modified or raw
    for key, value in pairs(overrides) do
      tuned = set_number(tuned, key, value)
    end
    if tuned ~= raw then
      modified = tuned
      handle:logInfo("forge_filter: sampler overrides for model=" .. cached_model)
    end
  end

  if modified then
    body:setBytes(modified)
    handle:headers():replace("content-length", tostring(#modified))
  end
end

function envoy_on_request(handle)
  local path = handle:headers():get(":path") or ""
  local method = handle:headers():get(":method") or ""

  -- Track model changes from POST /sdapi/v1/options
  if method == "POST" and path == "/sdapi/v1/options" then
    local body = handle:body()
    if body then
      local raw = body:getBytes(0, body:length())
      if raw then
        local model = raw:match('"sd_model_checkpoint"%s*:%s*"([^"]*)"')
        if model then
          cached_model = model:gsub("%.safetensors$", ""):gsub("%.ckpt$", "")
          handle:logInfo("forge_filter: cached model=" .. cached_model)
        end
      end
    end
    return
  end

  -- Track GET /sdapi/v1/options so we can cache model from response
  if method == "GET" and path == "/sdapi/v1/options" then
    handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "cache_from_response", "true")
    return
  end

  if method ~= "POST" or not GPU_PATHS[path] then
    return
  end

  if path == "/sdapi/v1/txt2img" then
    rewrite_txt2img(handle)
  end

  -- Yield last: once httpCall suspends the script the request body streams
  -- upstream, and body() can no longer be read or rewritten.
  local status, body = gpu_yield(handle, "evict", 90000)
  if status == "423" then
    -- A ComfyUI video job holds the GPU; refuse rather than contend for VRAM/RAM.
    handle:respond({[":status"] = "503", ["content-type"] = "application/json"}, body)
    return
  end
  handle:streamInfo():dynamicMetadata():set("envoy.filters.http.lua", "gpu_yielded", "true")
end

-- Cache model from GET /sdapi/v1/options responses (populates on first query)
function envoy_on_response(handle)
  local meta = handle:streamInfo():dynamicMetadata():get("envoy.filters.http.lua")
  if meta and meta["gpu_yielded"] == "true" then
    gpu_yield(handle, "restore", 180000)
    return
  end
  if not meta or meta["cache_from_response"] ~= "true" then return end

  local body = handle:body()
  if not body then return end
  local raw = body:getBytes(0, body:length())
  if not raw or #raw == 0 then return end

  local model = raw:match('"sd_model_checkpoint"%s*:%s*"([^"]*)"')
  if model then
    cached_model = model:gsub("%.safetensors$", ""):gsub("%.ckpt$", "")
    handle:logInfo("forge_filter: cached model from response=" .. cached_model)
  end
end
