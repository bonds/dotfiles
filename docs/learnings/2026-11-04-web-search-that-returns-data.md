# Web search and status pages: which endpoints actually return data

**Date:** 2026-11-04

## Symptom

Research from a shell kept returning "successful" responses with no data in them:

- **Reddit** — every HTML and JSON fetch returned `403`, including `old.reddit.com`,
  the `jina.ai` reader, and public `redlib` instances.
- **DuckDuckGo** — `html.duckduckgo.com/html/` returned a `202` challenge page;
  the `lite` variant the same.
- **Brave** — HTML search worked for about ten queries, then served a CAPTCHA.
- **Bing** — `200` for everything, including `&format=rss`, but the same cached
  ten results for every query, and quoted phrases ignored.
- **Mojeek** `403`, **Downdetector** `403`, **Yahoo** `500`.
- **Microsoft 365 status** — `status.cloud.microsoft` is a JS SPA and the
  marketing page answers `Your request has been blocked`.

The trap is the `200`: a status code says the request was served, not that the
query ran. Two of these (Bing RSS, the M365 SPA) return plausible-looking bodies
that contain no answer at all.

## Cause

Search engines and status pages now assume a browser: they gate on a JS
challenge, a cookie, or a user agent, and the gate is often served with `200`.
Reddit blocks datacenter IPs outright. A SPA fetches its data from an
undocumented JSON endpoint that only exists inside the bundle.

## Fix

- **Reddit comments:** `https://www.reddit.com/comments/<id>.rss?limit=200` —
  works unauthenticated, returns comments as RSS entries. Space calls **≥15 s**
  or it answers `429`.
- **Brave, from a shell:** plain `curl` with a desktop user agent, then split on
  `<div class="snippet svelte-` and strip tags (the first `href` is the URL):

  ```bash
  curl -sSL -G https://search.brave.com/search \
    --data-urlencode 'q=<query>' -A '<desktop UA>'
  ```

- **DuckDuckGo HTML:** still works as a `POST` to
  `https://html.duckduckgo.com/html/` **with a `Referer` header** — the `202` is
  the missing-referer branch, not a block.
- **A SPA's JSON endpoint:** find it in the bundle rather than guessing:

  ```bash
  rg -o '"/?api/[a-zA-Z0-9/_-]*"' /dist/app.<hash>.js
  ```

  For Microsoft 365 consumer service health that yields
  `https://status.cloud.microsoft/api/posts/m365Consumer` (also `/azure`, `/mac`,
  `/ppac`) — undocumented, but stable enough to script.
- **When a fetch looks empty, check for the tell:** a challenge or welcome shell
  contains the word "enable JavaScript", a CAPTCHA, or a `<noscript>` block.
  Treat those as failures even at `200`.

## Evidence

Sessions 2026-11-04 (Reddit/Brave/DDG/Bing) and 2026-11-13 (Microsoft 365 status
API, found by the `rg -o '"/?api/…"'` technique on the SPA bundle).
