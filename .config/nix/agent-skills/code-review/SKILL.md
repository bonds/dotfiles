---
name: code-review
description: "Review pending changes before a commit, push, or pull request. Use when the user asks for a review, before committing any batch of edits, or when checking a branch or PR for problems."
---

# Code review

Review the change, not the whole repo. Report findings; do not start editing
unless the user asks for fixes.

## 1. Establish the diff

Work from the smallest relevant scope:

```bash
git diff --staged          # staged changes (preferred)
git diff                   # unstaged, if nothing is staged
git show --stat HEAD       # last commit, if the tree is clean
git diff main...HEAD       # a branch
```

For this dotfiles repo there is no `.git` in `$HOME`; use the bare-repo prefix
and always `cd ~` first:

```bash
cd ~ && git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME diff --staged
```

Note that the bare repo hides untracked files, so also check
`git ... status --porcelain --untracked-files=normal` when the change adds
files, and confirm they were staged with `git add` (no `-f`).

## 2. Read the surroundings

For each non-trivial hunk, read the enclosing function or module before judging
it. A diff alone hides invariants: check callers, tests, and whether the same
logic already exists elsewhere.

Also read the repo's own instructions (`AGENTS.md`, and
`.config/nix/AGENTS.md` for nix changes) — conventions there override generic
advice.

## 3. What to check

Correctness
- Logic errors, off-by-one, wrong operator, inverted condition.
- Unhandled error paths; swallowed exit codes; `$status`/`$?` misuse.
- Races: shared mutable state, `await` inside loops that assume order.
- Resource leaks: unclosed files/sockets, temp dirs never removed.

Secrets and safety
- No API keys, tokens, passwords, private hostnames, or decrypted secret
  material in tracked files. This repo is **public**.
- Secrets stay behind agenix (`/run/agenix/...`) or passage; only references
  belong in the repo.
- Destructive commands (`rm -rf`, `doas`, force-push) are deliberate.

Shell compatibility
- Commands must be fish-compatible: `and` not `&&`, `(cmd)` not `$(cmd)`,
  `set -x` not `export`, `$status` not `$?`.
- No `if count $argv -lt N` (fish mis-parses it — assign first).
- Avoid bashisms in anything that runs under fish, including
  `ssh host '...'` one-liners on sophrosyne.

Nix
- `alejandra` formatting; `nix flake check` passes.
- No `builtins.readFile` of secrets, no secret values in the store.
- Version bumps when user-facing behavior or dependencies change, with
  `default.nix` and `pyproject.toml` in sync.

Python / Swift
- No `.pyc`/`__pycache__` staged.
- Swift tests run in Debug, never `-c release`.

Tests and docs
- Behavior change without a test where the repo has a suite.
- Non-obvious discovery gets a `docs/learnings/` entry (symptom, cause, fix).
- User-facing change gets an AGENTS.md update when it changes documented
  commands or paths.

## 4. Report

Group by severity, and give `file:line` for each item:

```markdown
**Blocking**
- `path/file.nix:42` — reason, and what to change.

**Non-blocking**
- `path/file.py:88` — suggestion.

**Verified**
- What you checked that looks right (keeps the report honest about scope).
```

State the scope you actually reviewed (staged only, branch, etc.) and anything
you could not verify (missing tests, no runtime access).

End with the concrete next step: the commands to run (`nix flake check`,
`pytest`, `swift test` with the Debug flags) and a question about how to
proceed — never commit or push as part of a review unless asked.
