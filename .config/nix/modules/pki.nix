# Trust-store hardening shared by accismus (nix-darwin) and the NixOS hosts.
#
# `security.pki.caCertificateBlacklist` exists under the same name in both
# nix-darwin and NixOS and filters roots out of the `cacert` bundle that becomes
# /etc/ssl/certs/ca-certificates.crt. Names are the NSS nicknames from
# Mozilla's certdata.txt, not the certificate CN.
#
# Why: the eMudhra intermediate CA compromise (Oct 2026) put eight P-384 keys
# with a single-byte private key (d = 4, 56, 115, …) into the public trust
# graph. Browsers were patched out of band (CRLSet / OneCRL / Apple's block),
# but curl, git, python, node and every daemon read a static bundle and do not
# check revocation, so for them the only fix is removing the roots themselves.
# Two paths reach the compromised intermediates, hence two entries:
#
#   emSign ECC Root CA - G3       → emSign Root TLS CA - G3 → EM * TLS CA - G3x
#   Comodo AAA Services root      → (Sectigo cross-sign, May 2025)
#
# Verified 2026-10-21: with these two blacklisted, OpenSSL rejects both chain
# families, while 16 real endpoints (github, cache.nixos.org, pypi, npm,
# crates.io, docker, letsencrypt, …) still verify. See
# docs/learnings/2026-10-21-libressl-verify-ignores-aux-trust.md before
# concluding anything from `openssl verify` on macOS.
{
  lib,
  isDarwin,
  ...
}: {
  security.pki.caCertificateBlacklist = lib.mkDefault [
    "emSign ECC Root CA - G3"
    "Comodo AAA Services root"
  ];

  # nix-darwin only: OpenSSL-based tools built against the *nix profile's*
  # cacert fall back to /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
  # (nss-cacert-3.121 here, still trusting emSign). That profile belongs to the
  # Nix installer, not to `nr`, so the blacklist above never reaches it. Point
  # SSL_CERT_FILE at the nix-darwin-managed bundle instead. Trade-off: tools
  # that honour it stop seeing roots added to the login keychain.
  environment.variables.SSL_CERT_FILE = lib.mkIf isDarwin "/etc/ssl/certs/ca-certificates.crt";
}
