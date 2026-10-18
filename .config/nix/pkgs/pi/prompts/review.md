---
description: Review the staged changes before committing
argument-hint: "[focus]"
---
Review the pending changes in this repo. Use the `code-review` skill.

Scope: staged changes first; fall back to unstaged, then the last commit.
Focus: ${1:-correctness, secrets, and repo conventions}.

Report blocking vs non-blocking findings with `file:line`, then tell me the
verification commands to run. Do not commit or push.
