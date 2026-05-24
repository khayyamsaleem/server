---
name: pr-review
description: Review a GitHub PR with structured feedback. Use when asked to "review this PR", "check PR #N", or look at a diff before merging. Focuses on real defects and design issues, not nits.
compatibility: opencode
---

## Fetch the PR

```bash
cd /workspace/dev/<repo>   # or clone if missing — see gh-pr-workflow
gh pr view <N> --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles
gh pr diff <N>             # full diff
gh pr checks <N>           # CI status
```

For deeper context:
```bash
gh pr view <N> --json files | jq -r '.files[].path'   # files touched
git fetch origin
git diff origin/main...origin/<head-branch>           # diff vs base
```

## What to look for (in priority order)

1. **Correctness defects** — actual bugs. Off-by-one, null deref, missing await,
   wrong condition, leaked resource, race condition. These are blockers.
2. **Security** — injection, secret leak, broken auth, unsafe deserialization,
   unvalidated input at trust boundary.
3. **Design** — does the change fit the existing architecture? Is the abstraction
   level right? Did it introduce a leaky interface?
4. **Tests** — does the new code have tests? Do existing tests still pass? Are
   tests testing behavior, not implementation?
5. **Naming and clarity** — would a new reader understand this? Is the function
   name a lie about what it does?
6. **Style/nits** — last and lowest priority. Only mention if they create real
   friction; otherwise let the linter complain.

## What to skip

- Don't comment "consider X" when X is just a style preference.
- Don't ask for tests on a 3-line refactor that doesn't change behavior.
- Don't suggest renames unless the existing name is actively misleading.
- Don't pile up nits — three real comments beat thirty nitpicks.

## Output structure

```
## Summary
<one paragraph: what the PR does, your overall recommendation: approve / request
changes / discuss>

## Blocking issues
- file:line — what's wrong, why, suggested fix
- ...

## Worth discussing
- file:line — design question, alternatives, your lean

## Minor
- file:line — small things, batched briefly
```

Skip empty sections.

## Posting comments

If the user asks you to actually post the review (not just summarize), use:

```bash
gh pr review <N> --comment --body "..."          # general comment
gh pr review <N> --request-changes --body "..."  # request changes
gh pr review <N> --approve --body "..."          # approve
# Inline comments need the API; usually a top-level comment is fine.
```
