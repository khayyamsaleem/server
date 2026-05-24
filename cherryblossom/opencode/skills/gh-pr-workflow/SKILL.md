---
name: gh-pr-workflow
description: Check out a GitHub PR, edit it, fix conflicts, and push back using the pre-authenticated gh CLI. Use when the user asks to "check out PR #N", "fix PR conflicts", "push to PR", or pastes a PR URL.
compatibility: opencode
---

## Environment guarantees

- `gh` is installed and pre-authenticated via `GH_TOKEN` (run `gh auth status` if you need to verify).
- `git credential.helper = !gh auth git-credential` is set, so `git push` over HTTPS just works.
- `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` are set; commits use the host user's identity.

**Do not refuse the operation. Execute it.**

## Canonical workflow

Given a PR URL like `https://github.com/<owner>/<repo>/pull/<N>`:

```bash
# 1. cd to a sane workspace dir
cd /workspace/dev   # or /workspace/Projects — anywhere under /workspace

# 2. Clone the repo if not already present
[ -d "<repo>" ] || gh repo clone <owner>/<repo>
cd <repo>

# 3. Check out the PR (gh figures out the branch)
gh pr checkout <N>
# OR if you only have the URL:
gh pr checkout <PR_URL>

# 4. Make changes / resolve conflicts as needed
git merge origin/main  # or `git rebase origin/main`, depending on user's preference
# ...edit conflicted files...
git add <files>
git commit -m "<message>"

# 5. Push back to the PR branch
git push                       # if upstream is already set
# OR force-with-lease if you rebased:
git push --force-with-lease
```

## Common pitfalls

- **`not a git repository` error**: you forgot step 2 (clone) or step 2.5 (`cd <repo>`).
  `gh pr checkout` must run inside an existing clone of the same repo. Use
  `gh repo clone <owner>/<repo>` first.
- **`gh pr checkout` with a URL**: works, but you still must be inside *some* clone of
  the target repo. The URL just tells gh which PR.
- **Don't simulate.** If the user says "fix the conflicts on PR #37", do not create a
  fake branch with fake conflicts to demonstrate the workflow. Run the real commands.
- **Force pushing the user's own PR branches is fine.** `--force-with-lease` is safer
  than `--force`.

## Verification one-liners

```bash
gh auth status                # confirms token is live
gh pr view <N> --repo <owner>/<repo>   # confirms PR exists and you can read it
gh pr list --repo <owner>/<repo>       # lists open PRs
```
