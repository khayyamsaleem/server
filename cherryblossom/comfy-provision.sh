#!/bin/sh
set -eu
# Init container: ensures ComfyUI custom nodes and LTX-2.3 video models exist in
# the comfyui-data volume. Only downloads what is missing; each download is
# checked against its Hugging Face sha256 before it is moved into place.
# The ComfyUI image copies its bundle into /root/ComfyUI on first start with
# --update=none, so pre-creating model folders here is safe.

C=/data/ComfyUI
M=$C/models
HF=https://huggingface.co

# --- Custom nodes (pinned) ---
node() {  # <dir> <repo> <commit>
    if [ -d "$C/custom_nodes/$1" ]; then
        printf "[init] node %s: present\n" "$1"
        return
    fi
    printf "[init] node %s @ %s\n" "$1" "$3"
    mkdir -p "$C/custom_nodes/$1"
    git -C "$C/custom_nodes/$1" init -q
    git -C "$C/custom_nodes/$1" fetch -q --depth 1 "$2" "$3"
    git -C "$C/custom_nodes/$1" checkout -q FETCH_HEAD
}
# GGUF loaders for the LTX transformer and the Gemma 3 text encoder.
node ComfyUI-GGUF https://github.com/city96/ComfyUI-GGUF.git 6ea2651e7df66d7585f6ffee804b20e92fb38b8a

# --- Models ---
fetch() {  # <url> <dest> <sha256>
    if [ -f "$2" ]; then
        printf "[init] %s: present\n" "$(basename "$2")"
        return
    fi
    printf "[init] downloading %s...\n" "$(basename "$2")"
    mkdir -p "$(dirname "$2")"
    wget -q -O "$2.part" "$1" || { rm -f "$2.part"; printf "[init] download failed: %s\n" "$1"; exit 1; }
    if [ "$(sha256sum "$2.part" | cut -d' ' -f1)" = "$3" ]; then
        mv "$2.part" "$2"
    else
        rm -f "$2.part"
        printf "[init] checksum mismatch, discarded: %s\n" "$(basename "$2")"
        exit 1
    fi
}

# LTX-2.3 22B distilled 1.1, Q4_K_M (8 steps, CFG 1).
fetch $HF/unsloth/LTX-2.3-GGUF/resolve/main/distilled-1.1/ltx-2.3-22b-distilled-1.1-Q4_K_M.gguf \
    $M/unet/ltx-2.3-22b-distilled-1.1-Q4_K_M.gguf \
    5d09efdc0b8ec2054c44a05366cd7c6634ffa333b379b1f8baf018a78974b73d
# Text encoder: Gemma 3 12B (abliterated, so prompts are not softened) + LTX connectors.
fetch $HF/bartowski/mlabonne_gemma-3-12b-it-abliterated-GGUF/resolve/main/mlabonne_gemma-3-12b-it-abliterated-Q4_K_M.gguf \
    $M/text_encoders/gemma-3-12b-it-abliterated-Q4_K_M.gguf \
    d1702ca02f33f97c4763cc23041e90b1586c6b8ee33fedc1c62e62045a845d2b
fetch $HF/bartowski/mlabonne_gemma-3-12b-it-abliterated-GGUF/resolve/main/mmproj-mlabonne_gemma-3-12b-it-abliterated-f16.gguf \
    $M/text_encoders/mmproj-gemma-3-12b-it-abliterated-f16.gguf \
    30c02d056410848227001830866e0a269fcc28aaf8ca971bded494003de9f5a5
fetch $HF/unsloth/LTX-2.3-GGUF/resolve/main/text_encoders/ltx-2.3-22b-distilled_embeddings_connectors.safetensors \
    $M/text_encoders/ltx-2.3-22b-distilled_embeddings_connectors.safetensors \
    c61cbb396e2a8175d8b2da51f0fdac885a4ccd22c9f64dafa5aa2c455dc8a507
# Video + audio VAEs, and the 2x latent upscaler for the second pass.
fetch $HF/unsloth/LTX-2.3-GGUF/resolve/main/vae/ltx-2.3-22b-distilled_video_vae.safetensors \
    $M/vae/ltx-2.3-22b-distilled_video_vae.safetensors \
    e68d6d8f8a42942ac9b862cc315beb3bc30805a8876c7ad63ba5bf7a2b8e168a
fetch $HF/unsloth/LTX-2.3-GGUF/resolve/main/vae/ltx-2.3-22b-distilled_audio_vae.safetensors \
    $M/vae/ltx-2.3-22b-distilled_audio_vae.safetensors \
    3cd6a6eb8cb28f5ecc12f1f3126952b2a3d2b0b42ad3270e63cefafafe0d9b57
fetch $HF/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors \
    $M/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors \
    5f416311fa8172b65af67530758964708d29a317b830d689a51143b7f91913ed

# LTXVAudioVAELoader only lists the checkpoints folder.
mkdir -p $M/checkpoints
ln -sf /root/ComfyUI/models/vae/ltx-2.3-22b-distilled_audio_vae.safetensors \
    $M/checkpoints/ltx-2.3-22b-distilled_audio_vae.safetensors

printf "[init] ComfyUI provisioning complete\n"
