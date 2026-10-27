# LibreSSL's `openssl verify` ignores aux trust, so it reports OK for a rejected root

## Symptom

Auditing whether a CA bundle still trusted a compromised root, `openssl verify`
said `OK` for *every* store on the machine — including a bundle built minutes
earlier with that root blacklisted:

```console
$ openssl verify -CAfile $NEW -untrusted chain.pem chain.pem
chain.pem: OK
$ $OSSL verify -show_chain -CAfile $NEW -untrusted chain.pem chain.pem   # OpenSSL 3.6.5
error 28 at 2 depth lookup: certificate rejected
```

The same binary also printed its usage screen for `-show_chain` (an option it
does not implement), so a bad invocation looks like a failed verification
rather than an unsupported flag.

`x509` has the same gap. LibreSSL has no `-ext`, so a script asking it for a
certificate's extensions got a usage dump instead:

```console
$ /usr/bin/openssl x509 -noout -ext subjectAltName -in leaf.pem
unknown option -ext
usage: x509 [-C] [-addreject arg] ...
```

Any modern `x509` flag is OpenSSL-3-only.

## Cause

`/usr/bin/openssl` on macOS is LibreSSL, and its `verify` ignores the aux trust
data carried by `-----BEGIN TRUSTED CERTIFICATE-----` blocks. nixpkgs'
`buildcatrust` emits exactly those blocks — that is how `cacert` encodes NSS
trust bits, and therefore how `security.pki.caCertificateBlacklist` (and
`pkgs.cacert.override { blacklist = …; }`) takes effect. To LibreSSL a rejected
root is just a root.

## Fix

Judge a trust store with OpenSSL 3, not the system one:

```bash
OSSL=$(ls /nix/store/*-openssl-3*-bin/bin/openssl | head -1)
$OSSL verify -show_chain -CAfile <bundle> -untrusted <chain> <chain>
```

The same binary covers `x509 -ext`, or skip the CLI altogether and parse the
PEM with python's `cryptography` (`x509.load_pem_x509_certificate(...)`), which
is what the forging test ended up doing.

And prefer a real handshake over a store query — that is what a client
actually does:

```bash
echo | $OSSL s_client -connect host:443 -servername host \
  -CAfile <bundle> -verify_return_error
```

Both `openssl verify` and `s_client` ignore revocation, so "OK" only means
"this bundle trusts this chain *if* nothing checks CRLs".

## Evidence

`session://pi/01a15ca8-85da-71f0-9f75-d46c785b899e#turn-188`

Found by searching the archive for a verbatim phrase from this entry (2 hit(s) for `error 28 at 2 depth lookup: certificate rejected`), within 3 days of the entry date.

> learning({"cause":"`/usr/bin/openssl` on macOS is LibreSSL, and its `verify` ignores the aux trust data in `-----BEGIN TRUSTED CERTIFICATE-----` blocks. nixpkgs' `buildcatrust` emits exactly those blo
