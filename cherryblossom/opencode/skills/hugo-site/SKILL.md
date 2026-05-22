---
name: hugo-site
description: Install Hugo and build/serve a Hugo static site inside this Alpine container. Use when the user asks to install Hugo, render a Hugo site, preview a blog locally, or work with content under content/, layouts/, themes/.
compatibility: opencode
---

## Installation (Alpine container)

This container is `node:lts-alpine`. Install Hugo extended via apk:

```bash
apk add --no-cache hugo
hugo version   # confirm install; want a version with "extended" if SCSS is used
```

If apk's hugo is too old or non-extended for the site, download the official binary:

```bash
# Pick a recent version; replace VER as needed
VER=0.134.0
wget -qO /tmp/hugo.tar.gz "https://github.com/gohugoio/hugo/releases/download/v${VER}/hugo_extended_${VER}_linux-amd64.tar.gz"
tar -C /usr/local/bin -xzf /tmp/hugo.tar.gz hugo
hugo version
```

## Build & serve

Inside the site's repo (must contain `config.toml` / `config.yaml` / `hugo.toml`):

```bash
# One-shot build into ./public
hugo --minify

# Local dev server with live reload (bind to all interfaces in a container!)
hugo server --bind 0.0.0.0 --port 1313 --baseURL "http://localhost:1313/" --disableFastRender
```

If the site uses Hugo Modules or a git-submoduled theme, run **before** building:

```bash
git submodule update --init --recursive   # for submoduled themes
hugo mod get -u                           # for Hugo modules (needs `go` installed)
```

## Common errors

- **`Error: command "server" not found`** — old apk Hugo without extended. Switch to the binary download above.
- **`Failed to transform "scss" ... unable to find resource`** — non-extended Hugo. Need `hugo_extended_*`.
- **`fatal: detected dubious ownership in repository`** — `git config --global --add safe.directory /workspace/<repo>` then retry.
- **Theme missing** — check `.gitmodules` and run `git submodule update --init --recursive`.

## Port exposure note

The opencode container binds 4096. Hugo's dev server on 1313 is only reachable from
inside the container unless the user maps the port. Tell the user the URL; they can
either `docker exec ... wget http://127.0.0.1:1313/` or you can `--bind 0.0.0.0` and
they can add `127.0.0.1:1313:1313` to compose.
