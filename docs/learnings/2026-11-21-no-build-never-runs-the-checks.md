# `nix flake check --no-build` evaluates the checks and runs none of them

**Symptom.** The pre-push hook announced
`nix flake check --no-build --all-systems … (format/deadnix/gitleaks/machine evals)`
and printed `all checks + direct evals passed`, so the gate looked like it
covered formatting, deadnix, statix and secret scanning. It covered none of
them: a tree with a formatting violation, a statix finding or a planted secret
pushed clean. The only things actually enforced were evaluation errors and the
three explicit machine evals further down the hook.

**Cause.** `--no-build` evaluates every check derivation and builds none, so
`format-check`, `deadnix-check`, `statix-check`, `secrets-check`,
`what-changed-test` and `reel-summarize-test` were all evaluated into `.drv`
files and then dropped. `--all-systems` is why: building the `x86_64-linux`
checks on this machine needs a Linux builder.

**Fix.** Keep the eval pass (cheap, all systems, catches eval errors) and add a
build pass for the four cheap checks of the *pushing* system:

```sh
system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
for check in format-check deadnix-check statix-check secrets-check; do
	nix build --no-link --no-write-lock-file ".#checks.$system.$check"
done
```

Capture the output in a variable and print it only on failure — piping into
`tail` would report the pipeline's status, not `nix build`'s.

## Dead end worth remembering: `deadnix -L` is load-bearing

The `deadnix-check` in `flake/checks.nix` runs `deadnix -L --fail .`, and a bare
`deadnix --fail .` is *stricter*: it also flags unused lambda patterns. Those are
deliberately out of scope, because a lambda pattern is the `callPackage`
interface — `pkgs/transcribe-cpp-python` took `transcribe-cpp` without using it,
and `pkgs/reel-summarize-mcp` passed it explicitly. Removing the pattern alone
broke the eval with

```
error: function 'anonymous lambda' called with unexpected argument 'transcribe-cpp'
```

If you do delete such an argument, delete the caller's explicit pass in the same
edit. Otherwise leave it: under `-L` it is not dead code, it is the signature.
