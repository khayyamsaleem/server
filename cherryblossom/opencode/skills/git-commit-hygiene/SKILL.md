---
name: git-commit-hygiene
description: Make clean, conventional git commits in this environment. Use when committing changes to any repo under /workspace. Covers staging, commit message style, signing, and what NOT to do.
compatibility: opencode
---

## Identity

Author/committer identity is set via env vars:
- `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`
- `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL`

You do not need to `git config user.name/email` — env vars take precedence.

## Commit message style

Use **Conventional Commits**: `<type>(<scope>): <subject>`.

Types: `feat fix refactor docs test chore perf build ci style revert`.

Subject ≤ 72 chars, imperative mood, no trailing period.

If the *why* isn't obvious from the diff, add a body separated by a blank line.
One-line summary + bulleted body is fine.

Example:
```
fix(opencode): IPv4 healthcheck to avoid IPv6 false-negative

Alpine resolves localhost via IPv6 first; opencode binds IPv4 only, so the
existing healthcheck reported unhealthy despite the service being up. Switch
the wget URL to 127.0.0.1.
```

## Do not

- **Do not** `git commit --no-verify` — pre-commit hooks exist for a reason.
- **Do not** `git commit --amend` to a commit that's already pushed.
- **Do not** `git add -A` blindly in repos that may contain `.env`, credentials,
  build artifacts. Stage by name or by path glob.
- **Do not** push to `main` / `master` directly on protected repos. Use a branch
  + PR.

## Co-author trailer

When making commits on behalf of the user via opencode, include a trailer:
```
Co-Authored-By: opencode <noreply@opencode.ai>
```

This is purely a marker so the user can later see which commits came from the
agent.

## Pre-flight checklist

Before running `git commit`:

```bash
git status               # see what's actually staged
git diff --staged        # review the staged hunks
git log --oneline -5     # match the existing commit-message style
```
