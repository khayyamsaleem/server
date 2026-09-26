# Stable Diffusion WebUI Forge - Neo (Haoming02/sd-webui-forge-classic, neo branch).
# Serves the A1111-compatible API on :17860 that Open WebUI reaches through the
# ollama-gateway (forge_filter.lua). Based on upstream docker/Dockerfile, with
# Neo and ADetailer pinned and every Python dependency installed at build time
# so a recreated container starts without touching the network.
FROM nvidia/cuda:13.0.3-runtime-ubuntu22.04

ARG NEO_COMMIT=3a3dea7ff781f525dd227c0f6f9ed2790ad00a35
# Neo's fork of ADetailer: upstream Bing-su/adetailer reads cmd_opts.use_cpu,
# which Neo removed, and fails to initialize. Same "ADetailer" script API.
ARG ADETAILER_COMMIT=67e973e1c5019c16dcf838364ae391a2752bfa7b

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_PYTHON_DOWNLOADS=automatic \
    UV_NO_CACHE=1

COPY --from=ghcr.io/astral-sh/uv:0.12.19 /uv /usr/local/bin/uv

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential curl ffmpeg git libgl1 libglib2.0-0 libgomp1 libtcmalloc-minimal4 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -u 1000 -m -d /home/forge -s /bin/bash forge
WORKDIR /home/forge/sd-webui

RUN git init -q . \
    && git remote add origin https://github.com/Haoming02/sd-webui-forge-classic.git \
    && git fetch -q --depth 1 origin "$NEO_COMMIT" && git checkout -q -B neo FETCH_HEAD \
    && git init -q extensions/ADetailer-Neo \
    && git -C extensions/ADetailer-Neo remote add origin https://github.com/Haoming02/ADetailer-Neo.git \
    && git -C extensions/ADetailer-Neo fetch -q --depth 1 origin "$ADETAILER_COMMIT" \
    && git -C extensions/ADetailer-Neo checkout -q -B main FETCH_HEAD \
    # Forge state (settings, ADetailer's downloaded detectors) lives in /data.
    && mkdir -p /data/adetailer models \
    && ln -s /data/adetailer models/adetailer \
    && chown -R forge:forge /home/forge /data

USER forge
ENV VIRTUAL_ENV=/home/forge/sd-webui/venv \
    PATH=/home/forge/sd-webui/venv/bin:$PATH
RUN uv venv venv --python 3.13 --seed \
    && uv pip install torch==2.13.0+cu130 torchvision==0.28.0+cu130 \
        --index-url https://download.pytorch.org/whl/cu130
# Neo's requirements plus each extension's installer; no GPU at build time.
RUN python launch.py --exit --skip-torch-cuda-test --uv

COPY --chown=forge:forge entrypoint.sh /home/forge/entrypoint.sh
EXPOSE 17860
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD curl -sf http://localhost:17860/sdapi/v1/sd-models > /dev/null || exit 1
ENTRYPOINT ["/home/forge/entrypoint.sh"]
