-- Forge proxy filter: dynamically inject ADetailer for SDXL/Pony models.
-- Flux does not support ADetailer (causes NaN), so it is stripped for Flux.

-- Models that support ADetailer (SDXL-based inpainting)
local ADETAILER_MODELS = {
  ["ponyDiffusionV6XL"] = true,
  ["sd_xl_base_1.0"] = true,
}

local ADETAILER_CONFIG = [[,"alwayson_scripts":{"ADetailer":{"args":[{"ad_model":"hand_yolov8n.pt","ad_confidence":0.4,"ad_denoising_strength":0.35,"ad_inpaint_only_masked":true,"ad_inpaint_only_masked_padding":32},{"ad_model":"face_yolov8n.pt","ad_confidence":0.3,"ad_denoising_strength":0.4,"ad_inpaint_only_masked":true,"ad_inpaint_only_masked_padding":32}]}}]]

-- Cached model name (Lua globals persist across requests within worker thread)
local cached_model = nil

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

  -- Only modify txt2img requests
  if method ~= "POST" or path ~= "/sdapi/v1/txt2img" then
    return
  end

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

  if modified then
    body:setBytes(modified)
    handle:headers():replace("content-length", tostring(#modified))
  end
end

-- Cache model from GET /sdapi/v1/options responses (populates on first query)
function envoy_on_response(handle)
  local meta = handle:streamInfo():dynamicMetadata():get("envoy.filters.http.lua")
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
