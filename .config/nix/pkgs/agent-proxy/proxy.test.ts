/**
 * Phase 0 acceptance tests for agent-proxy.
 *
 * These exist because the two ways a proxy silently ruins a harness are
 * invisible in normal use until something breaks at the worst moment:
 *
 *   1. It buffers. The harness still works, but streaming stalls and a long
 *      reasoning response looks like a hang.
 *   2. It rewrites headers. `content-encoding` left behind after Bun
 *      transparently decompressed the body makes the client see corrupt JSON;
 *      a stale `content-length` truncates it.
 *
 * Everything here runs against a local mock upstream — no network, no API key,
 * no cost.
 */

import { afterEach, describe, expect, test } from "bun:test";
import { createProxy, type ProxyHandle } from "./proxy";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** Mock provider. Returns its origin and a stop function. */
function mockUpstream(
	handler: (request: Request) => Response | Promise<Response>,
): { origin: string; stop: () => void } {
	const server = Bun.serve({
		port: 0,
		hostname: "127.0.0.1",
		idleTimeout: 0,
		fetch: handler,
	});
	return {
		origin: `http://127.0.0.1:${server.port}`,
		stop: () => server.stop(true),
	};
}

const cleanups: Array<() => void> = [];

/**
 * Send a request line verbatim. Needed because `fetch` normalizes `//` in a
 * path, which is exactly the input that distinguishes a correct proxy from one
 * that can be redirected at another host.
 */
function rawRequest(
	port: number,
	requestLine: string,
	timeoutMs = 2000,
): Promise<string> {
	return new Promise((resolve, reject) => {
		let buffer = "";
		let settled = false;
		const finish = (action: () => void) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			action();
		};
		const timer = setTimeout(
			() =>
				finish(() =>
					reject(
						new Error(`raw request timed out, got: ${buffer.slice(0, 200)}`),
					),
				),
			timeoutMs,
		);

		Bun.connect({
			hostname: "127.0.0.1",
			port,
			socket: {
				open(socket) {
					socket.write(
						`${requestLine}\r\n` +
							`Host: 127.0.0.1:${port}\r\n` +
							"Content-Type: application/json\r\n" +
							"Content-Length: 2\r\n" +
							"Connection: close\r\n\r\n{}",
					);
				},
				data(socket, chunk) {
					buffer += decoder.decode(chunk);
					// Headers are enough to judge where the request landed; waiting
					// for close is unreliable once the server keeps the socket alive.
					if (buffer.includes("\r\n\r\n")) {
						finish(() => resolve(buffer));
						socket.end();
					}
				},
				close() {
					finish(() => resolve(buffer));
				},
				error(_socket, error) {
					finish(() => reject(error));
				},
			},
		}).catch((error) => finish(() => reject(error)));
	});
}

function track<T extends { stop: () => void }>(thing: T): T {
	cleanups.push(() => thing.stop());
	return thing;
}

function proxyFor(origin: string): ProxyHandle {
	return track(
		createProxy({
			upstream: origin,
			port: 0,
			onError: () => {
				/* expected in the failure tests */
			},
		}),
	);
}

afterEach(() => {
	while (cleanups.length > 0) cleanups.pop()?.();
});

describe("passthrough", () => {
	test("forwards status, body and headers unchanged", async () => {
		const payload = JSON.stringify({ id: "cmpl-1", choices: [] });
		const upstream = track(
			mockUpstream(
				async () =>
					new Response(payload, {
						status: 201,
						headers: { "content-type": "application/json", "x-mock": "kept" },
					}),
			),
		);

		const proxy = proxyFor(upstream.origin);
		const response = await fetch(
			`http://127.0.0.1:${proxy.port}/v1/openai/chat/completions`,
			{
				method: "POST",
				headers: { "content-type": "application/json" },
				body: JSON.stringify({ model: "m", messages: [] }),
			},
		);

		expect(response.status).toBe(201);
		expect(response.headers.get("x-mock")).toBe("kept");
		expect(await response.text()).toBe(payload);
	});

	test("forwards the request body and Authorization header intact", async () => {
		let seenBody = "";
		let seenAuth = "";
		let seenPath = "";

		const upstream = track(
			mockUpstream(async (request) => {
				seenBody = await request.text();
				seenAuth = request.headers.get("authorization") ?? "";
				seenPath = new URL(request.url).pathname;
				return Response.json({ ok: true });
			}),
		);

		const proxy = proxyFor(upstream.origin);
		const requestBody = JSON.stringify({ model: "m", stream: true });
		await fetch(`http://127.0.0.1:${proxy.port}/v1/openai/chat/completions`, {
			method: "POST",
			headers: {
				authorization: "Bearer test-token",
				"content-type": "application/json",
			},
			body: requestBody,
		});

		expect(seenBody).toBe(requestBody);
		expect(seenAuth).toBe("Bearer test-token");
		// The provider's own path survives even though `upstream` is an origin.
		expect(seenPath).toBe("/v1/openai/chat/completions");
	});

	test("a wrong upstream content-length cannot truncate the body", async () => {
		// A stale framing header is the classic proxy bug: the client reads
		// `content-length` bytes and stops, so the JSON is cut mid-token and the
		// harness reports a parse error rather than a transport error.
		const upstream = track(
			mockUpstream(
				() => new Response("hello", { headers: { "content-length": "999" } }),
			),
		);
		const proxy = proxyFor(upstream.origin);
		const response = await fetch(`http://127.0.0.1:${proxy.port}/v1/openai/x`);

		expect(await response.text()).toBe("hello");

		// If a length is present at all it must describe the body we sent.
		const declared = response.headers.get("content-length");
		if (declared !== null) expect(Number(declared)).toBe(5);
	});
});

describe("streaming", () => {
	test("delivers SSE chunks as they arrive, not buffered", async () => {
		const CHUNKS = 5;
		const GAP_MS = 40;

		const upstream = track(
			mockUpstream(() => {
				const stream = new ReadableStream<Uint8Array>({
					async start(controller) {
						for (let i = 0; i < CHUNKS; i++) {
							controller.enqueue(encoder.encode(`data: {"i":${i}}\n\n`));
							await Bun.sleep(GAP_MS);
						}
						controller.close();
					},
				});
				return new Response(stream, {
					headers: { "content-type": "text/event-stream" },
				});
			}),
		);

		const proxy = proxyFor(upstream.origin);
		const started = performance.now();
		const response = await fetch(
			`http://127.0.0.1:${proxy.port}/v1/openai/chat/completions`,
			{ method: "POST", body: "{}" },
		);

		expect(response.headers.get("content-type")).toContain("text/event-stream");

		const reader = response.body!.getReader();
		const arrivals: Array<{ at: number; text: string }> = [];
		while (true) {
			const { done, value } = await reader.read();
			if (done) break;
			arrivals.push({ at: performance.now(), text: decoder.decode(value) });
		}
		const total = performance.now() - started;

		// Every byte still arrives, in order.
		expect(arrivals.map((a) => a.text).join("")).toBe(
			Array.from({ length: CHUNKS }, (_, i) => `data: {"i":${i}}\n\n`).join(""),
		);

		// And it arrives progressively. This is the assertion that fails if the
		// proxy ever starts accumulating the body before forwarding it.
		expect(arrivals.length).toBeGreaterThanOrEqual(3);
		expect(total).toBeGreaterThan(GAP_MS * 3);
		expect(arrivals[0]!.at - started).toBeLessThan(GAP_MS * 3);
	});

	test("a mid-stream upstream failure ends the stream instead of hanging", async () => {
		const upstream = track(
			mockUpstream(() => {
				const stream = new ReadableStream<Uint8Array>({
					async start(controller) {
						controller.enqueue(encoder.encode('data: {"i":0}\n\n'));
						await Bun.sleep(10);
						controller.error(new Error("upstream died"));
					},
				});
				return new Response(stream, {
					headers: { "content-type": "text/event-stream" },
				});
			}),
		);

		const proxy = proxyFor(upstream.origin);
		const response = await fetch(
			`http://127.0.0.1:${proxy.port}/v1/openai/chat/completions`,
			{ method: "POST", body: "{}" },
		);
		const reader = response.body!.getReader();

		const settled = (async () => {
			try {
				while (!(await reader.read()).done) {
					// drain until it throws or closes
				}
				return "closed";
			} catch {
				return "errored";
			}
		})();

		// A hang is the failure mode: the client would sit forever.
		const outcome = await Promise.race([
			settled,
			Bun.sleep(2000).then(() => "hung" as const),
		]);
		expect(outcome).not.toBe("hung");
	});
});

describe("operational", () => {
	test("healthz reports the resolved upstream", async () => {
		const upstream = track(mockUpstream(() => Response.json({ ok: true })));
		const proxy = proxyFor(upstream.origin);
		const response = await fetch(`http://127.0.0.1:${proxy.port}/healthz`);
		const body = (await response.json()) as { ok: boolean; upstream: string };
		expect(body.ok).toBe(true);
		expect(body.upstream).toBe(upstream.origin);
	});

	test("added latency stays under 20ms at p50", async () => {
		const upstream = track(mockUpstream(() => Response.json({ ok: true })));
		const proxy = proxyFor(upstream.origin);
		const directUrl = `${upstream.origin}/v1/openai/chat/completions`;
		const proxiedUrl = `http://127.0.0.1:${proxy.port}/v1/openai/chat/completions`;

		const measure = async (url: string) => {
			const samples: number[] = [];
			for (let i = 0; i < 30; i++) {
				const started = performance.now();
				await fetch(url, { method: "POST", body: "{}" }).then((r) => r.text());
				// First 5 are warm-up (DNS, connection pool, JIT).
				if (i >= 5) samples.push(performance.now() - started);
			}
			samples.sort((a, b) => a - b);
			return samples[Math.floor(samples.length / 2)]!;
		};

		const direct = await measure(directUrl);
		const proxied = await measure(proxiedUrl);

		expect(proxied - direct).toBeLessThan(20);
		expect(proxied).toBeLessThan(50);
	});

	test("refuses an upstream that is not a bare origin", () => {
		expect(() =>
			createProxy({ upstream: "https://api.deepinfra.com/v1/openai", port: 0 }),
		).toThrow(/origin/);
	});

	test("a protocol-relative path cannot redirect the request to another host", async () => {
		// `//evil.example.com/x` is a valid request line, but fetch/curl normalize
		// it away at the client. A raw socket is the only way to send it, and it
		// is the case that matters: resolved as a relative URL the path becomes
		// protocol-relative, so the request — and the bearer token on it — would
		// go to the other host.
		let seenPath = "";
		let seenHost = "";
		const upstream = track(
			mockUpstream((request) => {
				seenPath = new URL(request.url).pathname;
				seenHost = request.headers.get("host") ?? "";
				return Response.json({ ok: true });
			}),
		);

		const proxy = proxyFor(upstream.origin);
		const raw = await rawRequest(proxy.port, "POST //evil.example.com/x HTTP/1.1");

		expect(raw).toContain("200");
		expect(seenPath).toContain("evil.example.com");
		// It arrived as a path on the configured upstream, never as a host.
		expect(seenHost).not.toContain("evil.example.com");
	});
});
