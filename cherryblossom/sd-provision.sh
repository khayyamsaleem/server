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

# --- Checkpoints ---
CKPT_DIR="$STORAGE/stable_diffusion/models/ckpt"
mkdir -p "$CKPT_DIR"
# CyberRealistic Pony v18.0 CoreShift (fp16 pruned): photoreal Pony merge, keeps
# Pony score tags and LoRAs. Civitai requires an API token for this download.
CRP="$CKPT_DIR/cyberrealisticPony_v18.safetensors"
CRP_SHA256="1d580c1c3f3612fa4db88af65372255582d5509ca0b28f85387273368301941b"
if [ ! -f "$CRP" ]; then
    if [ -z "${CIVITAI_TOKEN:-}" ]; then
        printf "[init] CIVITAI_TOKEN unset, skipping CyberRealistic Pony\n"
    else
        printf "[init] Downloading CyberRealistic Pony v18...\n"
        # token as a query param: the download redirects to a presigned CDN URL
        # that rejects an extra Authorization header
        wget -q -O "$CRP.part" \
            "https://civitai.com/api/download/models/2884631?type=Model&format=SafeTensor&size=pruned&fp=fp16&token=$CIVITAI_TOKEN" \
            || { rm -f "$CRP.part"; printf "[init] CyberRealistic Pony download failed\n"; exit 1; }
        if [ "$(sha256sum "$CRP.part" | cut -d' ' -f1)" = "$CRP_SHA256" ]; then
            mv "$CRP.part" "$CRP"
        else
            printf "[init] CyberRealistic Pony checksum mismatch, discarding\n"
            rm -f "$CRP.part"
        fi
    fi
else
    printf "[init] CyberRealistic Pony: present\n"
fi

printf "[init] SD provisioning complete\n"
