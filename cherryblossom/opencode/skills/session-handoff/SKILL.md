---
name: session-handoff
description: Write a handoff document when the current session has grown long and a new session would be more productive. Use when the user is on a long task and turns are slowing down, or when explicitly asked to "summarize this session" or "let me pick this up later".
compatibility: opencode
---

## When to suggest a handoff

This local-ollama setup has **no prompt caching**, so every turn re-processes the
entire conversation. A session past ~30k input tokens starts feeling sluggish;
past ~50k it's painful. Symptoms:

- Each turn takes noticeably longer than the previous
- The agent starts losing track of earlier decisions
- The model occasionally repeats itself or contradicts earlier turns

If the user is mid-task and noticing these, suggest: *"this session is getting
long — want me to write a HANDOFF.md so we can pick this up in a fresh session?"*

## What goes in HANDOFF.md

Write it as if to a new agent who has no memory of the previous session.

```markdown
# Handoff: <slug or task name>

## Goal
<One paragraph: what we're trying to accomplish and why.>

## Where we are
<What's been done, with file paths and commit hashes when relevant. Be specific.>

## What's left
<Bullet list of remaining work, in order. Each bullet should be actionable
without needing more context.>

## Decisions made (don't relitigate)
<List of design/scope decisions already settled. Saves a new session from
proposing alternatives that were already rejected.>

## Open questions
<Things genuinely undecided, with the trade-offs.>

## Useful context
<File paths, repo links, command snippets that the new session will want at
hand. Brief.>
```

## Then

```bash
git status               # confirm working tree is clean or note pending edits
# Commit work-in-progress to a branch if needed, so the new session can pick it up
```

Suggest the user open a new opencode session and start it with: "Read
HANDOFF.md and continue from where we left off."

## What NOT to do

- Don't write a transcript of the session. The new agent doesn't need it.
- Don't include long log dumps. Reference file paths instead.
- Don't include reasoning that didn't change the outcome. State the outcome.
