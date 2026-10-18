---
description: Review, commit, and push a batch of changes to every remote
argument-hint: "[commit message]"
---
Ship the current batch:

1. Run the `code-review` skill over the pending changes. Fix anything blocking.
2. Run the repo's verification (see its AGENTS.md: `nix flake check`, `pytest`,
   `swift test` in Debug, …). Report what passed.
3. Stage only the intended files. Never use `-f` to force-add ignored paths
   (e.g. `__pycache__`/`.pyc` in `nix-what-changed`).
4. Commit with message: ${1:-a concise description of the change}.

Then push to **all** remotes:

- This dotfiles repo (bare repo at `~/.local/share/dotfiles`). `config` is a
  **fish-only** alias, so from the bash tool use the full form:

  ```bash
  cd ~ && git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME push origin main
  cd ~ && git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME push sophrosyne main
  ```

- Any other repo: `git push origin <branch>`

Rules:
- **Never** `--force` / `-f` to any remote. If sophrosyne rejects the push
  because of divergent history, merge or pull first, then push again.
- A push over SSH needs a Secretive TouchID approval. If it fails with
  `Permission denied (publickey)` or HTTP 403, do **not** retry in a loop and
  do not try to work around it: tell me the exact command to run myself.
- Stop after pushing. Do not start a rebuild.
