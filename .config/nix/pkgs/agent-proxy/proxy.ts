/**
 * agent-proxy — phase 0: a transparent, SSE-safe passthrough.
 *
 * The failure mode this fixes: every harness (pi, opencode, hermes, osaurus)
 * already persists *its own idea* of the conversation, in its own format, in
 * its own database — and loses it when the store is pruned or the harness is
 * replaced. What none of them can tell you afterwards is what the model
 * actually saw: the exact system prompt, which skills were loaded, the tool
 * schemas, the sampling parameters. That only exists on the wire.
 *
 * So the proxy sits in front of the provider and becomes the single capture
 * point for four harnesses instead of four integrations. Phase 0 deliberately
 * captures *nothing*: it only proves that a request can pass through without
 * being changed and without being buffered, because a proxy that buffers SSE
 * would stall every harness and a proxy that rewrites headers would break
 * streaming, tool calls, or both.
 *
 * Deliberate choices:
 *   - `upstream` is an *origin*, and the request path is forwarded verbatim.
 *     Every harness is configured with a base URL that already contains the
 *     provider's path (`/v1/openai`), so the incoming path is complete. This
 *     also means the proxy cannot be used as an open proxy: the target host
 *     comes from config, never from the request.
 *   - `accept-encoding: identity` is forced. Bun decompresses response bodies
 *     transparently while leaving `content-encoding` in the headers, which
 *     would make a captured body and its declared encoding disagree. Identity
 *     sidesteps that, and SSE never benefits from compression anyway.
 *   - hop-by-hop headers are stripped in both directions (RFC 9110 §7.6.1).
 *     Forwarding `content-length` after a body is re-framed is how you get a
 *     truncated response that looks fine to the client.
 *   - `idleTimeout: 0` because a reasoning model can be silent inside an SSE
 *     stream for minutes, and the default timeout would kill the connection
 *     mid-thought.
 *   - the client's abort signal is passed upstream, so a harness that gives up
 *     also stops the provider generating (and billing).
 */

const DEFAULT_UPSTREAM = "https://api.deepinfra.com";
const DEFAULT_PORT = 8787;
const DEFAULT_HOSTNAME = "127.0.0.1";

/** Connection-scoped headers that must not be relayed (RFC 9110 §7.6.1). */
const HOP_BY_HOP = [
	"connection",
	"keep-alive",
	"proxy-authenticate",
	"proxy-authorization",
	"proxy-connection",
	"te",
	"trailer",
	"transfer-encoding",
	"upgrade",
];

export interface ProxyOptions {
	/** Provider origin, e.g. `https://api.deepinfra.com`. No path. */
	upstream?: string;
	/** Port to bind. Defaults to `AGENT_PROXY_PORT` or 8787. */
	port?: number;
	/** Interface to bind. Defaults to `AGENT_PROXY_HOST` or 127.0.0.1. */
	hostname?: string;
	/** Called on any upstream failure; defaults to stderr. */
	onError?: (error: unknown) => void;
}

export interface ProxyHandle {
	port: number;
	hostname: string;
	upstream: string;
	stop: () => void;
}

/**
 * Start the proxy. Returns the bound port so tests can use port 0.
 */
export function createProxy(options: ProxyOptions = {}): ProxyHandle {
	const upstream = new URL(
		options.upstream ?? process.env.AGENT_PROXY_UPSTREAM ?? DEFAULT_UPSTREAM,
	);
	if (upstream.pathname !== "/" || upstream.search !== "") {
		throw new Error(
			`upstream must be an origin with no path, got ${upstream.href}`,
		);
	}

	const hostname =
		options.hostname ?? process.env.AGENT_PROXY_HOST ?? DEFAULT_HOSTNAME;
	const port =
		options.port ??
		(process.env.AGENT_PROXY_PORT
			? Number(process.env.AGENT_PROXY_PORT)
			: DEFAULT_PORT);

	const startedAt = performance.now();
	const report =
		options.onError ??
		((error: unknown) => {
			console.error("[agent-proxy] upstream error:", error);
		});

	const server = Bun.serve({
		port,
		hostname,
		// A reasoning model can be quiet inside an SSE stream for minutes.
		idleTimeout: 0,
		async fetch(request) {
			const url = new URL(request.url);

			if (url.pathname === "/healthz") {
				return Response.json({
					ok: true,
					upstream: upstream.origin,
					uptime_ms: Math.round(performance.now() - startedAt),
				});
			}

			// Path is forwarded verbatim; only scheme+host come from config, so
			// the request cannot redirect the proxy at another host.
			//
			// Assigning `pathname` rather than resolving a relative URL is
			// deliberate: `new URL("//evil.example.com/x", origin)` treats the
			// path as protocol-relative and escapes to a different host, which
			// would forward the caller's bearer token to an attacker.
			const target = new URL(upstream.origin);
			target.pathname = url.pathname;
			target.search = url.search;

			const headers = new Headers(request.headers);
			for (const name of HOP_BY_HOP) headers.delete(name);
			headers.delete("host");
			headers.delete("content-length");
			headers.set("accept-encoding", "identity");

			const hasBody = request.method !== "GET" && request.method !== "HEAD";

			try {
				const upstreamResponse = await fetch(target, {
					method: request.method,
					headers,
					body: hasBody ? request.body : undefined,
					signal: request.signal,
					redirect: "manual",
					// Node requires this for a streaming request body; Bun accepts it
					// and ignores it. Harmless in both.
					duplex: "half",
				} as RequestInit & { duplex: "half" });

				const responseHeaders = new Headers(upstreamResponse.headers);
				for (const name of HOP_BY_HOP) responseHeaders.delete(name);
				// The body arrives decompressed (or identity), so the encoding and
				// length the upstream declared no longer describe it.
				responseHeaders.delete("content-encoding");
				responseHeaders.delete("content-length");

				const bodyless =
					request.method === "HEAD" ||
					upstreamResponse.status === 204 ||
					upstreamResponse.status === 304;

				return new Response(
					bodyless ? null : upstreamResponse.body,
					{
						status: upstreamResponse.status,
						statusText: upstreamResponse.statusText,
						headers: responseHeaders,
					},
				);
			} catch (error) {
				report(error);
				// A stable shape, so a harness shows something useful instead of
				// "Unexpected end of JSON input".
				return Response.json(
					{
						error: {
							type: "proxy_upstream_error",
							message: error instanceof Error ? error.message : String(error),
						},
					},
					{ status: 502 },
				);
			}
		},
	});

	return {
		port: server.port ?? port,
		hostname,
		upstream: upstream.origin,
		stop: () => server.stop(true),
	};
}

if (import.meta.main) {
	const proxy = createProxy();
	console.log(
		`[agent-proxy] ${proxy.hostname}:${proxy.port} -> ${proxy.upstream}`,
	);
}
