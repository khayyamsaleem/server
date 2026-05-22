---
name: fetch-asset
description: Download files (logos, images, PDFs, datasets, binaries) from URLs to a local path using curl/wget. Use when asked to "download X", "grab the Y logo", "fetch Z from <URL>", or save any web resource locally. Downloading is NOT image processing — do not refuse a download because you can't resize.
compatibility: opencode
---

## Core principle

`curl` and `wget` are **installed and work**. Any file with a URL can be downloaded.
Downloading a PNG, SVG, PDF, ZIP, tarball — all are trivial single-command operations.

**Do NOT refuse a download request because "image processing tools aren't
available".** Downloading ≠ processing. You only need image-processing tools
(like ImageMagick, `convert`, `magick`) if you also need to **resize**, **convert
format**, or **crop** the file. If the user just asked for a download, just download.

## Basic downloads

```bash
# Save with explicit name
curl -L -o /path/to/save.png "https://example.com/asset.png"
wget -O  /path/to/save.png "https://example.com/asset.png"

# Save to current dir, keep remote filename
curl -L -O "https://example.com/asset.png"

# Show what you got
file /path/to/save.png        # confirms it's an actual PNG, not an HTML error page
ls -la /path/to/save.png       # confirms size > 0
```

Always pass `-L` to `curl` so it follows redirects. Many CDNs / GitHub release
URLs redirect.

## Asset locations the user is likely to ask for

| Asset | Source |
|---|---|
| OpenCode logo | `https://opencode.ai/favicon-v3.svg` (SVG, scales) or `https://opencode.ai/apple-touch-icon-v3.png` (180×180 PNG) or `https://opencode.ai/favicon-96x96-v3.png` (96×96 PNG) |
| Anthropic / Claude logo | https://www.anthropic.com (check footer / press kit) |
| GitHub repo's own assets | `https://github.com/<owner>/<repo>/raw/main/<path>` (use `raw` not `blob`) |
| GitHub release binary | `https://github.com/<owner>/<repo>/releases/download/v<X>/<file>` |
| Generic logo from a site's open graph | look at `<meta property="og:image" content="...">` — usually a usable PNG |

If the user doesn't give you a URL, search the project's homepage / press kit / GitHub for the standard brand asset URL. Many projects have a `/brand/`, `/press/`, or `/assets/` path.

## Save location for Hugo sites

For k5m.sh and similar Hugo sites, static assets live under `static/`:

```bash
cd /workspace/k5m.sh
mkdir -p static/images/<project>
curl -L -o static/images/<project>/logo.png "<url>"
file static/images/<project>/logo.png      # verify
```

Reference from markdown as `/images/<project>/logo.png` — Hugo serves `static/`
content from the site root.

## Common errors

- `curl: (60) SSL certificate problem` — rare with public sites; add `-k` only as a
  last resort and tell the user.
- File downloads but `file <path>` says HTML — the URL returned an error page or a
  redirect-to-login. Open the page in `curl -sI <url>` first to see the response.
- 404 — the URL is wrong; check the project's actual asset path. Don't give up
  silently; report the 404 and propose a correct URL or ask the user for one.

## When the user wants to resize / convert (separate task)

If they additionally ask "and make it smaller" or "convert to webp", that's when
you need `apk add --no-cache imagemagick`. Then `magick input.png -resize 96x96
output.png`. But complete the download step first; resize is a follow-up.
