# `age` is not installed — encrypt with `rage` (and how to add a secret without plaintext on disk)

## Symptom

On accismus, whose entire secret story is agenix, the obvious command fails:

```
$ which age
age not found
$ age -e -r age1... -o secrets/foo.age
fish: Unknown command: age
```

## Cause

The flake installs **agenix** (0.15.0, `~/.nix-profile/bin`) and
**age-plugin-yubikey**, but not the `age` CLI. **`rage` 0.11.4** is in
`/run/current-system/sw/bin` and is flag-compatible for the parts we use:
`-e`, `-r` (repeatable), `-o`, and stdin input.

agenix itself still works for rekeying (`agenix -e file.age`), but `rage` is the
convenient one for a one-shot encrypt.

## Fix — add a secret without the plaintext touching the filesystem

Pipe the key straight from an unnamed Helix buffer into `rage`. The key lives
only in the editor's memory: an unnamed buffer is never written, Helix has no
swap files, and undo history is only persisted for named buffers.

1. `hx` (no filename → unnamed scratch buffer), `i`, paste the key, `Esc`.
2. `%` — select the whole document. **Required:** `:pipe-to` pipes each
   *selection*, and normal mode's selection is a single character, so without
   `%` you encrypt one character.
3. Pipe to `rage`, written to the bare-repo work tree:

   ```
   :pipe-to tr -d '\n' | rage -e -r <recipient> -r <recipient> -r <recipient> -o ~/.config/nix/secrets/<name>.age
   ```

4. `:q!` — close **without** writing.

`tr -d '\n'` is defensive: a stray trailing newline inside a key file breaks
whatever reads it (`Authorization` headers reject it, `{file:...}` includes it
verbatim).

Then declare it: `secrets.nix` (recipients, same set as its siblings) →
`age.secrets.<name>` in `hosts/accismus/configuration.nix` (owner/mode) → `nr`.
Verify with `od -c /run/agenix/<name> | tail -2`.

Notes:

- **The key is still visible in terminal scrollback** while pasting. That is a
  display exposure (memory), not a filesystem one; `clear` afterwards.
- **Bare key vs dotenv line.** `hermes-*` secrets are `KEY=<value>` env lines
  loaded as an env file. A consumer that reads the file itself (opencode's
  `{file:...}`) needs the **bare key** in its own file — hence separate files
  per consumer, which also lets keys rotate independently.
- `git status` shows nothing for a new `.age` file: `status.showUntrackedFiles`
  is `no` in this repo (see `2026-10-19-showuntrackedfiles-hides-worktree-files.md`).
  Add it by explicit path.
