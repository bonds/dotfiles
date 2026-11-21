# pi.dev/packages lists download counts only in the HTML, sorted by most downloads

**Date:** 2026-11-21

## Symptom

Wanted the popular third-party pi packages; pi.dev has no API for it — `https://pi.dev/api/packages` returns 501, and the docs only mention the gallery URL, not how it ranks.

## Cause

The gallery at https://pi.dev/packages is server-rendered and defaults to the "Most downloads" sort; each card carries `data-package-name` and `data-package-downloads` (monthly count, npm-wide). Counts are npm installs across every harness, so a multi-harness package such as billion-context outranks pi-only ones. Do not filter on `data-package-types`: it is blank for some packages that are extensions (billion-context is blank there but its page says `Types extension`), so read the `Types` line on the package page instead.

## Fix / takeaway

curl -s https://pi.dev/packages -o /tmp/p.html then grep `data-package-card` and pull `data-package-name="..."` / `data-package-downloads="..."`; per-package pages render `Downloads 3.9M/mo · 1.2M/wk` and a `Types` line.
