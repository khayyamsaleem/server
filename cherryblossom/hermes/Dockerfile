FROM nousresearch/hermes-agent:latest

# Install gh CLI + curl (needed for doctl download)
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    gh \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Add hermes user to docker group (GID 965 on host) so it can use docker.sock.
# gosu in the entrypoint drops supplementary groups, so group_add in compose
# only reaches PID 1 — we need hermes itself to be a member.
RUN groupadd -g 965 docker && usermod -aG docker hermes

# Install doctl
ARG DOCTL_VERSION=1.150.0
RUN curl -sL "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin doctl

# Static binaries copied from picoclaw (pre-extracted to build context)
COPY gog /usr/local/bin/gog
COPY goplaces /usr/local/bin/goplaces
COPY hermes-init.sh /usr/local/bin/hermes-init
# Proxies `nvidia-smi` into the GPU container. No driver is visible in here, but
# the agent types the bare command regardless — make it work instead of fail.
COPY nvidia-smi-shim.sh /usr/local/bin/nvidia-smi
RUN chmod +x /usr/local/bin/gog /usr/local/bin/goplaces /usr/local/bin/hermes-init /usr/local/bin/nvidia-smi
