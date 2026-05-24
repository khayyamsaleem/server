---
name: pr-conflict-resolve
description: Resolve merge conflicts on a specific GitHub PR by URL or number. Use when the user says "fix the conflicts on PR #N", "rebase PR X over main", "this PR can't merge — fix it", or pastes a /pull/N URL with "fix conflicts" / "merge" intent. ALWAYS fetch fresh PR state before claiming anything about it.
compatibility: opencode
---

## Mandatory first step

**Do not claim anything about the PR based on memory of past conversation.**
PR state changes. The repo may have been updated. Earlier work in this session
may have been on a different branch. Always re-check.

```bash
# Replace 39 / khayyamsaleem/k5m.sh with the actual PR number and repo
gh pr view 39 --repo khayyamsaleem/k5m.sh --json number,title,state,mergeable,mergeStateStatus,headRefName,baseRefName,headRepository
```

The `mergeable` and `mergeStateStatus` fields are the source of truth:

- `mergeable: "CONFLICTING"` → there ARE conflicts. Proceed to resolve.
- `mergeable: "MERGEABLE"` → no conflicts. Tell the user and stop.
- `mergeable: "UNKNOWN"` + `mergeStateStatus: "BEHIND"` → out of date but no
  active conflict; a rebase will tell you for sure.

**If you skip this check, you are guessing.** Do not guess.

## Canonical fix workflow

After you've confirmed conflicts exist:

```bash
# 1. Land in a clone of the repo
cd /workspace/dev      # or wherever
[ -d "<repo>" ] || gh repo clone <owner>/<repo>
cd <repo>
git fetch origin

# 2. Check out the PR branch
gh pr checkout <N>     # this brings down origin/<head-branch> and checks it out

# 3. Bring main up to date locally and merge (or rebase — pick one and stick)
git fetch origin main:main 2>/dev/null || git fetch origin main
git merge origin/main             # OR: git rebase origin/main

# 4. If conflicts: resolve them, then continue
#    `git status` lists conflicted files. Edit each, then:
git add <resolved-files>
git commit                        # for merge   OR  git rebase --continue  for rebase

# 5. Push back
git push                          # merge path; upstream already set
# OR rebase path:
git push --force-with-lease

# 6. Re-check the PR state
gh pr view <N> --json mergeable,mergeStateStatus
# Should now show MERGEABLE / CLEAN.
```

## After resolving — verify, don't assume

Before reporting "done":

```bash
gh pr view <N> --json mergeable,mergeStateStatus,statusCheckRollup
gh pr checks <N>                  # CI status
```

If CI is failing, that's not "done" either — report the failure and ask.

## Output rules

Report what you actually did, with command output to back each claim. Do **not**:

- Use ✅ checkmarks for things you haven't verified.
- Say "the PR is now mergeable" without showing `mergeable: MERGEABLE` from a fresh `gh pr view`.
- Claim "I addressed this earlier in the conversation" — even if you did, the
  user is asking you to verify NOW. Run the check now.
- Summarize a list of prior accomplishments to deflect from the actual question.

If the PR turns out to already be mergeable, the correct response is:
> "Checked PR #N just now — `mergeable: MERGEABLE`, no conflicts. Nothing to fix."

That's the whole response. No checklists, no recap of past work.

## When the user asks about a specific PR number, prefer the PR's repo

The PR URL has the form `https://github.com/<owner>/<repo>/pull/<N>`. Always
pass `--repo <owner>/<repo>` to `gh pr view` / `gh pr checks` if you're not
inside that repo's clone. Otherwise `gh` infers from cwd and might hit the
wrong repo.

See also: `gh-pr-workflow`, `git-commit-hygiene`.
