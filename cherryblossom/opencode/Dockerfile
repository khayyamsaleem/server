FROM node:lts-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep git python3 bash docker.io curl gh \
 && rm -rf /var/lib/apt/lists/*
RUN npm install -g opencode-ai mcp-searxng
# Pre-seed ripgrep so opencode doesn't try to download it at runtime
RUN opencode debug 2>/dev/null || true
RUN git config --global credential.helper '!gh auth git-credential'
WORKDIR /workspace
EXPOSE 4096
ENTRYPOINT ["opencode"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "4096"]
