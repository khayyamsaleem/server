---
name: hugo-blog-post
description: Write a new Hugo blog post for k5m.sh in the user's established format. Use when asked to draft a blog post, write up an experiment, or document a new project. Covers frontmatter, file location, author conventions, and tonal style.
compatibility: opencode
---

## Where the post goes

In the k5m.sh repo:
```
content/<slug>.md            # short posts
content/<slug>/index.md      # posts with images / assets
```

Choose `index.md` form when the post will have images. Hugo treats each
directory as a page bundle, so co-located images can be referenced relatively.

## Frontmatter

The repo uses TOML frontmatter (delimited by `+++`), not YAML:

```toml
+++
date = "21 May 2026"
author = "khayyam"
+++
```

Look at recent posts in `content/` for the exact format. Date is human-readable,
not ISO. Author is lowercase first name. Some posts add fields like `tags`,
`draft = true` — only add if needed.

## Style (the user's own voice — match it)

Look at `content/init.md` and recent commits in `content/` for tone calibration.
Cues from the user's writing:

- Lowercase, conversational. No corporate AI tone.
- Specific concrete examples beat general claims.
- Short paragraphs. Lists where appropriate.
- Don't bury the lede — the first paragraph says what the post is about.
- Code blocks for commands; surround prose with them, don't replace it.

## What NOT to write

- No "In today's fast-paced world of AI..." openers.
- No "let's dive in", "buckle up", "stay tuned".
- No filler transitions ("Furthermore", "Moreover", "It's important to note").
- No bulleted lists summarizing the post at the top — let the post speak.

If the user has a `stop-slop` skill available, load it before writing.

## After writing

```bash
cd /workspace/dev/k5m.sh   # or wherever the clone lives
hugo server --bind 0.0.0.0 --port 1313   # preview locally
# Verify the post renders correctly, then:
git checkout -b post/<slug>
git add content/<slug>*
git commit -m "post: <subject>"
git push -u origin HEAD
gh pr create --fill
```

See also: `gh-pr-workflow`, `hugo-site`, `stop-slop`.
