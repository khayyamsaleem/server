#!/bin/bash
set -euo pipefail
# Init container: ensures SD extensions and models exist in the shared volume.
# Volume mounts handle the wiring — this only downloads missing artifacts.

STORAGE=/data

# --- Extensions ---
if [ ! -d "$STORAGE/extensions/adetailer" ]; then
    printf "[init] Downloading ADetailer extension...\n"
    mkdir -p "$STORAGE/extensions"
    git clone --depth 1 https://github.com/Bing-su/adetailer.git "$STORAGE/extensions/adetailer"
else
    printf "[init] ADetailer: present\n"
fi

# --- LoRA ---
LORA_DIR="$STORAGE/stable_diffusion/models/lora"
mkdir -p "$LORA_DIR"
if [ ! -f "$LORA_DIR/flux-uncensored-v2.safetensors" ]; then
    printf "[init] Downloading flux-uncensored-v2 LoRA...\n"
    wget -q -O "$LORA_DIR/flux-uncensored-v2.safetensors" \
        "https://civitai.com/api/download/models/630948?type=Model&format=SafeTensor"
else
    printf "[init] flux-uncensored-v2 LoRA: present\n"
fi

printf "[init] SD provisioning complete\n"
