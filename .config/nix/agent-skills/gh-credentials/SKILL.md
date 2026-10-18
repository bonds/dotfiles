---
name: gh-credentials
description: "The two GitHub tokens: a fine-grained PAT in the gh keyring for repos Scott owns, and a classic public_repo token in the macOS Keychain used by the `gh-public` wrapper for third-party public repos. Use when filing issues or PRs on someone else's repo, when creating a release (needs Contents: write), or when gh or a push fails with missing scopes, 403, or Permission denied."
---

Neither token is in this repo (it is public).

## GitHub credentials (`gh`)

Two tokens, deliberately separate. **Neither is stored in this repo** (it is public).

| Credential | Stored in | Scope | Used for |
|---|---|---|---|
| fine-grained PAT | `gh` keyring (`~/.config/gh/`) | repos Scott owns | normal `gh` work; also feeds `NIX_CONFIG` access-tokens (`35-nix-github-token.fish`) |
| classic PAT | macOS login Keychain, item `gh-public-token` | `public_repo` | filing issues/PRs on **third-party public repos**, via the `gh-public` wrapper |

**Why two.** A fine-grained PAT can only ever be granted access to repos you own (or orgs you belong to), so it cannot reach a public repo owned by someone else — `gh issue create --repo someone/else` dies with `GraphQL: Resource not accessible by personal access token (createIssue)`. A classic `public_repo` token is the right credential for that, but it **cannot be stored in the `gh` keyring**: `gh auth login --with-token` enforces a minimum scope set (`repo`, `read:org`, `gist`) and rejects `public_repo` with `missing required scopes`.

**Why per-invocation, not a global `GH_TOKEN`.** `GH_TOKEN` takes precedence over the keyring token for *every* gh call, so exporting the `public_repo` token globally would shadow the fine-grained PAT and strip gh's access to Scott's own private repos. `gh-public` sets it only for the command it wraps.

Set up (once per machine; copy a classic token scoped to `public_repo` first):

```fish
security add-generic-password -U -s gh-public-token -a bonds -w (pbpaste)
```

Use:

```fish
gh-public issue create --repo osaurus-ai/osaurus --title "..." --label enhancement --body-file ~/body.md
```

Rotate: re-run the same `security add-generic-password -U …` line with the new token (`-U` updates the item in place). Remove: `security delete-generic-password -s gh-public-token -a bonds`. The wrapper itself is `.config/fish/conf.d/36-gh-public-token.fish`.

**Gotchas:**
- **`gh issue create --label X` does not fail when the label can't be applied** — it prints the issue URL and exits 0. Always confirm with `gh issue view <n> --json labels`. A non-collaborator cannot label on someone else's repo at all (`AddLabelsToLabelable` denied), so expect `labels: []`; a maintainer will label it.
- The Keychain item was created by `security`, so `security` reads it without a prompt; reading it from fish can raise a one-time "always allow" dialog.
- `--with-token`'s minimum-scope rule is hard, not a warning — a `public_repo`-only token cannot be logged in that way at all.
