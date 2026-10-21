# `security.pki` does not reach the bundle nix OpenSSL tools actually fall back to

## Symptom

After adding a root to `security.pki.caCertificateBlacklist` (nix-darwin) and
building, `/etc/ssl/certs/ca-certificates.crt` no longer contained it — but nix
`python3` still accepted a certificate chaining to that root:

```console
$ /run/current-system/sw/bin/python3 -c 'import ssl; print(ssl.get_default_verify_paths())'
DefaultVerifyPaths(cafile='/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt', …)
```

## Cause

`security.pki` only builds the file it points `NIX_SSL_CERT_FILE` at
(`/etc/ssl/certs/ca-certificates.crt`). Nothing reads `NIX_SSL_CERT_FILE`
except nix itself: OpenSSL honours `SSL_CERT_FILE`, and with that unset it uses
its compiled-in default, which on nix-darwin is the **installer's** profile
bundle `/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt` (here
`nss-cacert-3.121`, 145 roots). That profile is not rebuilt by `nr`, so it
drifts arbitrarily far behind the system's own cacert — 5 NSS releases in this
case, and still shipping a root the system had blacklisted.

## Fix

Pin `SSL_CERT_FILE` at the nix-darwin-managed bundle in the same module, so
every OpenSSL-based tool (python, curl, git, ruby, perl) agrees with the system:

```nix
environment.variables.SSL_CERT_FILE = lib.mkIf isDarwin "/etc/ssl/certs/ca-certificates.crt";
```

Caveat worth knowing before debugging a "certificate verify failed" that used
to work: anything honouring `SSL_CERT_FILE` stops seeing roots added to the
login keychain (mkcert, corporate MITM roots). `environment.variables` lands in
`/etc/zshenv` → `/nix/store/…-set-environment`, so it applies to login shells
and whatever they spawn — *not* to launchd daemons, which need their own
`Environment` entry (as `modules/minecraft-bedrock.nix` and `modules/dst-server.nix`
already do).
