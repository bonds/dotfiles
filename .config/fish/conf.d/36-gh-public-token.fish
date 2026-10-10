# `gh-public` — run gh against third-party PUBLIC repos with a minimal-scope token.
#
# gh's stored credential is a fine-grained PAT scoped to repos Scott owns.
# Fine-grained PATs can only be granted access to repos you own (or orgs you
# belong to), so they can never reach a public repo owned by someone else:
#
#     $ gh issue create --repo osaurus-ai/osaurus ...
#     GraphQL: Resource not accessible by personal access token (createIssue)
#
# A classic `public_repo` token is the correct credential for that, but it
# cannot live in gh's keyring next to the PAT: `gh auth login --with-token`
# enforces a minimum scope set (repo, read:org, gist) and rejects public_repo
# with "missing required scopes".
#
# So it lives in the macOS login Keychain, injected per-invocation via GH_TOKEN.
# Per-invocation matters: a *global* GH_TOKEN would shadow the fine-grained PAT
# for every gh call, and a public_repo token grants no access to Scott's own
# private repos.
#
# Store it once (copy the classic public_repo token first):
#
#     security add-generic-password -U -s gh-public-token -a bonds -w (pbpaste)
#
# Then, e.g.:
#
#     gh-public issue create --repo osaurus-ai/osaurus --title "..." \
#         --label enhancement --body-file ~/body.md
#
# No secret is stored in this file, so it is safe to track in dotfiles.
# Cost: one Keychain read per invocation (~10ms); macOS may ask once whether
# fish may access the item — choose "Always Allow".
function gh-public --description 'Run gh with the public_repo token (third-party public repos)'
    set -l tok (security find-generic-password -s gh-public-token -a bonds -w 2>/dev/null)
    if test -z "$tok"
        echo "gh-public: no 'gh-public-token' item in the login keychain." >&2
        echo "  store one with: security add-generic-password -U -s gh-public-token -a bonds -w (pbpaste)" >&2
        return 1
    end
    env GH_TOKEN=$tok gh $argv
end
