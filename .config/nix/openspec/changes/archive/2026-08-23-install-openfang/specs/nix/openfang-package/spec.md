## Purpose

Provides a nix-managed, version-pinned, sha256-verified OpenFang binary package and the ability for NixOS hosts (sophrosyne) to install it declaratively via `environment.systemPackages`.

## ADDED Requirements

### Requirement: OpenFang package provided by flake
The flake SHALL provide an `openfang` package that fetches the official OpenFang Linux release tarball, verifies its integrity against a pinned sha256 hash, extracts the single `openfang` executable, and installs it as a runnable binary.

#### Scenario: Package evaluates
- **WHEN** the `openfang` package is referenced via `pkgs.callPackage ../../pkgs/openfang {}`
- **THEN** the package evaluates to a derivation whose `bin/openfang` is the pinned, hashed OpenFang binary

#### Scenario: Hash mismatch is caught
- **WHEN** the fetched tarball's SHA-256 does not match the pinned hash
- **THEN** the build fails rather than installing an unverified binary

### Requirement: NixOS host opts into install
A NixOS host SHALL be able to install the OpenFang binary system-wide by adding the package to `environment.systemPackages`.

#### Scenario: Sophrosyne install
- **WHEN** `hosts/sophrosyne/configuration.nix` lists `openfang` in `environment.systemPackages`
- **THEN** the server system exposes an `openfang` command after rebuild

### Requirement: Reproducible pinned release
The package SHALL pin an exact OpenFang release version so rebuilds are deterministic and do not drift with `latest`.

#### Scenario: Deterministic rebuild
- **WHEN** sophrosyne is rebuilt at a later date
- **THEN** the same pinned OpenFang version and hash are used unless the package is explicitly bumped