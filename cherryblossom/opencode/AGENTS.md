# Agent operating instructions

You are running inside a container with full, authenticated access to the host user's
development environment. **Trust the environment and try real operations** before
claiming you cannot do something.

## Authenticated capabilities (verified)

- **GitHub CLI (`gh`)** is installed at `/usr/bin/gh` and pre-authenticated via the
  `GH_TOKEN` environment variable. Scopes include `repo`, `workflow`, `admin:org`,
  `gist`, and more. You can:
  - `gh repo clone <owner>/<name>`
  - `gh pr checkout <number-or-url>`
  - `gh pr create`, `gh pr push`, `gh pr merge`
  - `gh issue ...`, `gh api ...`, etc.
- **Git** is configured with `credential.helper = !gh auth git-credential`, so any
  `git clone`, `git push`, `git fetch` over HTTPS to GitHub will authenticate
  automatically. No password prompt — it just works.
- **Git identity** is set via `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` env vars.
  Commits use the host user's identity automatically.
- **Docker CLI** is available and the host's Docker socket is mounted read-only at
  `/var/run/docker.sock`. You can `docker ps`, `docker logs`, `docker inspect`
  containers running on the host.
- **Tools available**: `ripgrep`, `git`, `gh`, `python3`, `bash`, `node`, `npm`,
  `docker`, `curl`, `wget`.
- **Web search (MCP)**: an `mcp-searxng` server is wired in, exposing two tools
  to you:
  - `searxng_web_search(query, ...)` — search the live web via the local SearXNG
    instance (private, no tracking)
  - `web_url_read(url)` — fetch a URL and return its readable markdown content
  Use these when the user asks for current info, recent docs, or any fact that
  isn't in the codebase.

## Working directory

- `/workspace` is mounted from the host's home directory `/home/khayyam`.
- Subdirectories of interest:
  - `/workspace/server` — infrastructure repo (this server)
  - `/workspace/dev` — active dev projects
  - `/workspace/Projects` — personal projects
- Clone new repos into a sensible subdirectory (e.g. `/workspace/dev/<repo>`).
- Always `cd` into the repo before running git commands.

## Behavior rules

1. **Execute, don't simulate.** If a user asks you to "check out PR #37 and fix
   conflicts", actually run `gh pr checkout 37` against the cloned repo. Do not
   create a fake branch and simulate a conflict to "demonstrate" the workflow.
2. **Trust the auth setup.** Do not say "I cannot authenticate" or "I don't have
   GitHub access". The container is authenticated. Run the command and report the
   real result.
3. **Try the real thing first; report actual errors.** If a command fails, paste
   the error and reason about that specific error. Don't preemptively refuse based
   on assumed limitations.
4. **Force-push to PR branches is allowed** for branches you own. `git push --force`
   or `git push --force-with-lease` is fine for resolving PR conflicts.
5. **Read tools take absolute paths.** If a read fails with "not found", check the
   path — you likely need to prefix with the repo directory (`/workspace/<repo>/...`)
   or pass the full path returned by a prior `bash` listing.
6. **One task per session is ideal.** If a session has grown long, suggest starting
   a new one rather than continuing.
7. **`gh pr checkout` must run inside a clone of the target repo.** Steps for a
   PR URL: (a) `cd /workspace/dev` (or similar), (b) `gh repo clone <owner>/<repo>`
   if not present, (c) `cd <repo>`, (d) `gh pr checkout <N-or-URL>`. Skipping (b/c)
   gives `fatal: not a git repository` — that's not an auth problem, it's location.
8. **Install missing tools with `apk add`.** This is Alpine. `apk add --no-cache hugo`
   gets you Hugo, `apk add --no-cache go` Go, etc. Don't say "Hugo isn't installed"
   — install it.
9. **Download is not image processing.** `curl` and `wget` are installed and work.
   If the user says "download the X logo / fetch the Y file / grab Z from <URL>",
   that's `curl -L -o <path> <url>` — one command, no extra tooling. Do **not**
   refuse a download saying "image processing tools aren't available" — that's
   conflating download with resize. Process only if the user also asks for resize
   / convert.

## On-demand skills

The following SKILL.md files are available via the skill tool — load them when
the task matches:

**Infrastructure / git:**
- **gh-pr-workflow** — clone, checkout PR, fix conflicts, push back
- **git-commit-hygiene** — commit message style and what to avoid
- **alpine-install** — install missing packages via apk and alternatives
- **docker-host-inspect** — read host container state via the mounted socket
- **fetch-asset** — download files (logos, images, PDFs, binaries) via curl/wget

**Hugo / blog:**
- **hugo-site** — install Hugo (apk or binary), build, serve a Hugo site
- **hugo-blog-post** — draft a new k5m.sh blog post in the user's format/voice

**Code work:**
- **codebase-explore** — efficient `rg`-first exploration patterns
- **pr-review** — structured PR review (correctness > security > design > nits)

**Writing / sessions:**
- **stop-slop** — kill AI-tone phrases from prose
- **session-handoff** — write HANDOFF.md when a session has grown too long

If the user's request matches any of these, load the relevant skill before acting.

## Subagent model routing

Subagents (`explore`, `general`, `title`, `summary`) are configured to use
`qwen2.5-coder:7b-instruct-q4_K_M`, which routes to the 1080 Ti via the envoy
gateway. The primary agent (`build`, `plan`) keeps using `qwen3-coder-tuned:65k`
on the 3090. Both GPUs work in parallel — you don't need to think about this,
it just happens.

## Quick verification commands

If you ever doubt your environment, run these to verify:

```bash
gh auth status              # confirms GH_TOKEN is active
git config --global --list  # confirms credential helper
echo "$GH_TOKEN" | head -c 10  # confirms token is set (will print first 10 chars)
```

These will all succeed.
