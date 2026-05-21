FROM node:lts-alpine
RUN apk add --no-cache ripgrep git python3 bash docker-cli curl
RUN npm install -g opencode-ai
# Pre-seed ripgrep so opencode doesn't try to download it at runtime
RUN opencode debug 2>/dev/null || true
WORKDIR /workspace
EXPOSE 4096
ENTRYPOINT ["opencode"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "4096"]
