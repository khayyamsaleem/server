#!/bin/bash
set -euo pipefail

# TCMalloc reduces memory fragmentation under large model workloads.
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4

# Dependencies are installed at build time; skip the startup environment checks.
# --disable-smart-memory offloads models to RAM after each job so Ollama can
# reclaim the VRAM (gpu-yield reloads it right after the image returns).
# --api-server-stop enables /sdapi/v1/server-kill, which gpu-yield uses to free
# RAM before a ComfyUI video job; restart: unless-stopped brings Neo back.
exec python /home/forge/sd-webui/launch.py \
    --listen --port 17860 --api --api-server-stop \
    --skip-prepare-environment --skip-version-check \
    --disable-smart-memory \
    --ckpt-dirs /models/ckpt \
    --lora-dirs /models/lora \
    --ui-settings-file /data/config.json \
    --ui-config-file /data/ui-config.json \
    ${FORGE_EXTRA_ARGS:-} "$@"
