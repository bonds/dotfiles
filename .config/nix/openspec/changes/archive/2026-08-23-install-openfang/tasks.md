## 1. Package

- [ ] 1.1 Create `pkgs/openfang/default.nix` lix package (pinned v0.6.9, sha256 `sha256-QwmwvPKtxdrEV3biAICHqK0HKTPxrmmP+NTgb7a4dgI=`, tarball `openfang-x86_64-unknown-linux-gnu.tar.gz`, extract to `$out/bin/openfang`)
- [ ] 1.2 Format `default.nix` with alejandra

## 2. Host wiring

- [ ] 2.1 Add `openfang` via `pkgs.callPackage ../../pkgs/openfang {}` to `environment.systemPackages` in `hosts/sophrosyne/configuration.nix`
- [ ] 2.2 Format the edited file with alejandra

## 3. Verification

- [ ] 3.1 Run `nix flake check --no-build` (format + secrets) locally
- [ ] 3.2 Evaluate the sophrosyne config (`openspec validate install-openfang`)
- [ ] 3.3 Commit and push both remotes (origin, sophrosyne)