# macOS `strip` inflates non-Mach-O files in a nix build

**Date:** 2026-11-14

## Symptom

Packaging Swival (`pkgs/swival`) from vendored wheels produced a 1.7 GB store
path where the same wheel set installed by pip is 417 MB. The bloat was four
"icons" that are 4.5 KB in the wheel:

```
$ ls -l $out/lib/swival/litellm/proxy/swagger/favicon.ico
-r--r--r--@ 7 root  wheel  808452160 Dec 31  1969 .../favicon.ico
```

Only the first ~4 KB of each file was real; the rest was zeros, and `du` counted
1.5 GB of allocated blocks for one of them.

## Cause

`fixupPhase`'s `stripping (with command strip and flags -S) in …/lib …/bin`
runs over **every** file in the output, not just ELF/Mach-O. nixpkgs' cctools
`strip` does not skip the files it cannot parse — it rewrites them, padded out to
a size derived from the input, so a 4.5 KB `.ico` becomes 808 MB (and two others
539 MB). Nothing in the build fails; only the size changes.

Nix's store import does not preserve sparseness, so the zeros become real disk.

## Fix

Set `dontStrip = true` when the derivation's binaries are already stripped
upstream — which is the case for anything unpacked from Python wheels:

```nix
dontUnpack = true;
dontBuild = true;
dontStrip = true;  # macOS strip mangles non-Mach-O files (see this entry)
```

1.7 GB → 417 MB, and the icons stay 4495 bytes.

Bisect it the same way next time: `overrideAttrs {dontStrip = true;}` versus
`overrideAttrs {dontFixup = true;}` on the same expression.
