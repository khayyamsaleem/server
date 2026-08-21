#!/bin/sh
# nvidia-smi shim for the hermes container.
#
# This container has no NVIDIA driver and no /dev/nvidia* devices, so the real
# nvidia-smi cannot be installed here. The agent nonetheless reaches for a bare
# `nvidia-smi` constantly, no matter what the skill docs say, and then reports
# "GPU unavailable" to the user.
#
# So: proxy the call into the container that DOES own the GPU. Arguments pass
# through unchanged, so every nvidia-smi invocation the agent knows how to write
# works verbatim.
GPU_CONTAINER="${GPU_CONTAINER:-cherryblossom-ollama-3090-1}"

if ! docker inspect -f '{{.State.Running}}' "$GPU_CONTAINER" >/dev/null 2>&1; then
    echo "nvidia-smi shim: GPU container '$GPU_CONTAINER' is not running." >&2
    echo "The GPU is reachable only through that container. Check 'docker ps'," >&2
    echo "or read GPU metrics from http://dcgm-exporter:9400/metrics instead." >&2
    exit 1
fi

exec docker exec "$GPU_CONTAINER" nvidia-smi "$@"
