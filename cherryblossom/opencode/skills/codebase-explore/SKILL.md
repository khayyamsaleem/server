---
name: codebase-explore
description: Efficient patterns for exploring an unfamiliar codebase. Use when asked to find where something is defined, understand a repo's structure, or trace how data flows through code. Beats blind reads with cheap searches first.
compatibility: opencode
---

## Order of operations

1. **Map the top level** before reading anything:
   ```bash
   ls -F
   cat README.md AGENTS.md CLAUDE.md 2>/dev/null   # whichever exist
   ```
2. **Pattern-match before reading.** `rg` (ripgrep) is preinstalled. Use it instead
   of full file reads:
   ```bash
   rg -n "ClassName"                     # find symbol definitions + references
   rg -n "^(def|class|fn|func) " --type py    # list all functions/classes in py
   rg -l "import_path"                   # files importing something
   rg -tA 3 -tB 1 "TODO|FIXME"           # find todos with context
   ```
3. **Read targeted, not blindly.** When `rg` points you to a file, read just the
   relevant range, not the whole file.

## Repo shape questions

| Question | Command |
|---|---|
| What languages are here? | `rg --files \| sed 's/.*\\.//' \| sort \| uniq -c \| sort -rn \| head` |
| Where's the entry point? | `rg "^(def main\|if __name__\|fn main\|func main)" -n` |
| What's the build system? | `ls -1 Makefile package.json pyproject.toml Cargo.toml go.mod 2>/dev/null` |
| Which dirs have the most code? | `find . -name '*.py' -o -name '*.ts' -o -name '*.go' \| xargs wc -l \| sort -rn \| head` |

## Trace how X works

When asked "how does X work":

1. `rg -n "X"` — first hits often reveal what's a definition vs reference.
2. Open the file containing the definition. Read 30-60 lines around it.
3. `rg -n "X(" ` (with the open paren) — find callers.
4. Pick the 2-3 most relevant callers, read each briefly.

## Don't

- Don't `cat` a 5,000-line file when `rg pattern file.py | head` answers the
  question.
- Don't read every file in a directory to "understand the structure" — `ls -F`
  + a `rg` for landmarks is faster.
- Don't recurse infinitely into `node_modules/`, `.venv/`, `dist/`, `build/`.
  ripgrep ignores these by default. If using `find`, pass `-prune` for them.

## Hand-off

If exploration produces useful findings, write them down before you forget. A
brief summary at the top of your next response (or in a `NOTES.md` you draft)
saves re-exploration later.
