# Phase C — Integration Log: laya pre-filter in reel-summarize-mcp

## Context
The laya line-salience pre-filter (Phase C) was wired into the reel-summarize-mcp
service on sophrosyne (`REEL_SUMMARIZE_LAYA_ENABLED=true`, package wrapper sets
`LAYA_CHECKPOINT_DIR`). Verification (28 Sep) revealed the pre-filter was **silently
off in production**: `laya_calibration.json` was not shipped in the built package,
so `filter_lines()` hit `calibration load failed` and fell back to keep-every-line.

## Root cause
`pkgs/reel-summarize/pyproject.toml` had no `[tool.setuptools.package-data]`, so
setuptools shipped only `.py` files. `reel_summarize/stages/laya.py` computes the
calibration path from the module dir (`laya_calibration.json` must sit next to
`reel_summarize/__init__.py`), and `_load_mapping()` raises when absent — even with
`laya_use_calibration=False` — which degrades to "keep every line".

## Fix (committed)
Commit `6f59fc19` — "reel-summarize: ship laya_calibration.json in package
(pre-filter was silently off)":
- `pyproject.toml`: added `[tool.setuptools.package-data] reel_summarize =
  ["laya_calibration.json"]`
- `default.nix`: version `0.1.0` → `0.2.0` to match `pyproject.toml` (chose 0.2.0
  — pyproject already carried 0.2.0, and the feature set grew since 0.1.0)

## Step 1 — temp files removed
`.laya-fix-test.py.tmp` and `.laya-fix-run.sh.tmp` under
`pkgs/reel-summarize/` were removed (already gone before this log; confirmed gone).

## Step 2 — packaging fix + version
Confirmed in `pkgs/reel-summarize/pyproject.toml` (package-data present) and
`default.nix` (version 0.2.0). Working tree clean; commit `6f59fc19` contains both.

## Step 3 — proof the JSON ships (build on sophrosyne, x86_64-linux)
Built the fixed package on sophrosyne (single SSH connection; laya/torch are
linux-scoped so building locally on aarch64-darwin would fail):
```
nix build --impure --expr 'let f = builtins.getFlake (toString /home/scott/.config/nix);
  pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
  in pkgs.callPackage /home/scott/.config/nix/pkgs/reel-summarize-mcp {}' -o /tmp/rsmcp-fixed
```
Result:
```
find /tmp/rsmcp-fixed -name laya_calibration.json
=> /nix/store/a6vszxsgysfciqkdjyk1yi5yhndcfax4-reel-summarize-0.2.0/lib/python3.13/site-packages/reel_summarize/laya_calibration.json
JSON PRESENT
```
(The `reel-summarize-0.2.0` derivation, not the old `-0.1.0` store paths which lack
the JSON.)

## Step 4 — functional test on sophrosyne with the FIXED package
Ran `filter_lines(lines, cfg)` with the fixed package's wrapped env
(`PYTHONPATH` from the built MCP wrapper, `LAYA_CHECKPOINT_DIR` store path,
`REEL_SUMMARIZE_LAYA_ENABLED=true`), raw threshold 0.30 (deployed default,
calibration opt-in off):

```
module LAYA_CHECKPOINT_DIR = '/nix/store/11ajg55q6yrp76d6r0c5j825rgh1z9qq-laya-checkpoint-55cf4c4'
_router_models() = {'english': '/nix/store/11ajg55q6yrp76d6r0c5j825rgh1z9qq-laya-checkpoint-55cf4c4'}
calibration exists: True @ .../a6vszx...-reel-summarize-0.2.0/.../laya_calibration.json
mapping steps: 7
INPUT_LINES=23
RESULT: INPUT=23 KEPT=22 DROPPED=1 elapsed=19.1s
⚠ laya: filtered 1/23 low-salience lines (threshold=0.3 raw)
```
Before the fix the same run returned `23 → 23`, elapsed 0.0s, stderr
`calibration load failed ... keeping every line`.

Reference (not deployed default): calibration on → 10 → 0 (aggressive; matches
`laya.py` docstring that calibrated thresholds > ~0.33 keep nothing).

Interpretation: the pre-filter now genuinely engages (model inference runs, 19s,
removes lines). With raw threshold 0.30 the model's raw scores are low so only 1
line was removed on this synthetic salience-heavy sample — a threshold-tuning
question, not a packaging failure. (Earlier probe: raw p(include) ≈ 0.05–0.34.)

## Step 5 — quick checks
`nix build .#checks.aarch64-darwin.secrets-check` (gitleaks) → **no leaks found**.
alejandra format not needed (no .nix change in this commit beyond version string;
and pyproject.toml isn't nix-formatted).

## Step 8 — POST-`nr` PRODUCTION VERIFICATION (28 Sep ~10:04, requester follow-up)

Scott ran `nr` (~10:03). Production now verified LIVE (single batched SSH):

- **Deployed system**: `/run/current-system` → `/nix/store/ain31qpqc731y6ihzp471d36j4i7kvjk-nixos-system-sophrosyne-26.05.20260926.5e2305d`, generation `system-430-link`.
- **Deployed MCP package**: `ExecStart` = `/nix/store/3m2ma4fcp5mwvna6a1byv6fn7zyczgbl-reel-summarize-mcp-0.1.0/bin/reel-summarize-mcp`.
- **Calibration JSON ships**: `/nix/store/a6vszxsgysfciqkdjyk1yi5yhndcfax4-reel-summarize-0.2.0/lib/python3.13/site-packages/reel_summarize/laya_calibration.json` (1017 bytes) — referenced by the deployed wrapper.
- **Functional test (deployed env, `REEL_SUMMARIZE_LAYA_ENABLED=true`, raw threshold 0.30)**: `INPUT_LINES=23 SHORTLIST=22 DROPPED=1 elapsed=19.1s`, stderr `⚠ laya: filtered 1/23 low-salience lines (threshold=0.3 raw)`. **SHORTLIST < INPUT = True** — real inference, no fallback.
- **Journal** since restart: zero `laya|calibrat|keeping every line` lines → no fallback warning.
- **Service**: `active`, restarted `Mon 2026-09-28 10:03:43 PDT` (immediately after `nr`).

Git nuance (reported plainly): sophrosyne's bare-repo checkout HEAD is `f628ec1` —
commit `6f59fc19` is NOT in sophrosyne's git history (pushes were blocked by
Secretive/TouchID "agent refused operation" twice, neither remote advanced). The fix
is live because the working-tree files carry it (`pyproject.toml` line 19
package-data; `default.nix` version 0.2.0) and `nr` builds from the working tree.
Pushes to both remotes still pending. NOTE: deployed MCP store hash equals the
earlier `/tmp/rsmcp-fixed` build (same inputs → same derivation) — byte-for-byte the
fixed package.

## Step 6 — push
- `git push sophrosyne main`: **blocked** — Secretive/TouchID `agent refused
  operation` (2 attempts). NOT pushed as of log write.
- `git push origin main` (GitHub backup): pending same.

## Step 7 — detached build on sophrosyne
Pending — will kick with `nohup nix build ... > /tmp/soph-build5.log 2>&1 &`
(no activation; Scott runs `nr` himself).