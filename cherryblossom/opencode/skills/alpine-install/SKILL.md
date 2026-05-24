---
name: alpine-install
description: Install system packages in this Alpine-based container using apk. Use when a binary you need (compiler, language runtime, CLI tool) is missing and you need to add it. Covers apk syntax and common alternatives (npm, pip, go install, direct binaries).
compatibility: opencode
---

## This container

- Base: `node:lts-alpine`
- Pre-installed: `ripgrep git python3 bash docker-cli curl github-cli node npm`

You generally have root inside the container (containers run as root by default
unless USER was set). Just `apk add` what you need.

## apk basics

```bash
apk update                  # refresh package index (only needed if cache stale)
apk add --no-cache <pkg>    # install without keeping cache
apk info <pkg>              # show installed pkg info
apk search <term>           # find packages
apk del <pkg>               # uninstall
```

## Common needs

| Need | Command |
|---|---|
| C/C++ compiler | `apk add --no-cache build-base` |
| Go toolchain | `apk add --no-cache go` |
| Rust toolchain | `apk add --no-cache rust cargo` |
| Python tooling | `apk add --no-cache python3 py3-pip` (already present) |
| Hugo static-site generator | `apk add --no-cache hugo` (or use github release for extended) |
| jq | `apk add --no-cache jq` |
| make | `apk add --no-cache make` |
| openssh client | `apk add --no-cache openssh-client` |
| musl-dev headers | `apk add --no-cache musl-dev` |

## When apk's version is too old

Prefer downloading the official binary from the project's GitHub releases:

```bash
# Pattern
wget -qO /tmp/tool.tar.gz "https://github.com/<owner>/<repo>/releases/download/v<VER>/<tarball>"
tar -C /usr/local/bin -xzf /tmp/tool.tar.gz <binary-name>
chmod +x /usr/local/bin/<binary-name>
```

## Language-specific package managers

- `npm install -g <pkg>` for Node CLIs
- `pip install --break-system-packages <pkg>` (Alpine py3 may need `--break-system-packages`)
- `go install <path>@latest` for Go (after `apk add go`)

## Persistence note

Anything installed via `apk` lives only in *this container instance*. A `docker
compose down && up --build` wipes it. For persistent additions, edit the Dockerfile
at `cherryblossom/opencode/Dockerfile` and rebuild.
