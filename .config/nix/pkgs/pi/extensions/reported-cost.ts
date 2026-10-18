/**
 * Reported Cost — prefer the provider's own per-request cost over list prices.
 *
 * Why this exists: pi prices every request as `tokens × model.cost` (USD per
 * million tokens, from models.json or its bundled catalog). It never reads a
 * cost field out of the provider's response — `parseChunkUsage` in the
 * OpenAI-compatible API calls `calculateCost(model, usage)` and ignores
 * everything else. For a custom provider like Deep Infra there is also no
 * pi.dev catalog entry (`/api/models/providers/deepinfra` → 404), so models.json
 * is the only price source pi has.
 *
 * That is wrong in two ways for Deep Infra:
 *   1. It reports the real billed amount per request: `usage.estimated_cost`
 *      (present in streaming usage chunks too, which pi requests via
 *      `stream_options.include_usage`).
 *   2. Its list prices are not what you pay. DeepSeek-V4.1-Flash-1017 currently
 *      carries `metadata.discount: 0.51`, so the effective rate is 0.49 × the
 *      published 0.2/0.6 per million — `estimated_cost` reflects the discount,
 *      a static models.json price would overstate cost by ~2x, and promo
 *      discounts expire without notice.
 *
 * So: models.json keeps the published list prices (a sane fallback and the
 * shape of the split), and this extension rescales each finished message so
 * `usage.cost.total` equals the provider's reported amount, with the
 * input/output/cache components scaled proportionally.
 *
 * Mechanics (both hooks are public extension API, no internals):
 *   - `provider_stream_event` carries the parsed provider chunk before pi
 *     normalizes it, so the raw usage object is still visible. We stash the
 *     reported total keyed by provider+model+token counts.
 *   - `message_end` may replace the finalized message before pi persists it and
 *     before session totals are computed, so rewriting `usage.cost` there is
 *     what `/session` and the footer see.
 *
 * A provider that reports no cost (or a different API shape) is untouched:
 * the token-count match fails and pi's own number stands.
 */

import type { ExtensionAPI, MessageEndEvent, ProviderStreamEvent } from "@earendil-works/pi-coding-agent";

interface TokenCounts {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
}

interface ReportedCost extends TokenCounts {
	total: number;
}

/** Latest report per provider+model; one request at a time per model in practice. */
const reported = new Map<string, ReportedCost>();

function keyOf(provider: string, model: string): string {
	return `${provider}\u0000${model}`;
}

function num(value: unknown): number {
	const parsed = typeof value === "number" ? value : Number(value);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

/** Mirror of pi's OpenAI-compatible normalization, so counts are comparable. */
function tokensFromRawUsage(raw: unknown): TokenCounts | undefined {
	if (!raw || typeof raw !== "object") return undefined;
	const usage = raw as Record<string, unknown>;
	const details = (usage.prompt_tokens_details ?? {}) as Record<string, unknown>;
	const prompt = num(usage.prompt_tokens);
	const cacheRead = num(details.cached_tokens ?? usage.prompt_cache_hit_tokens ?? usage.cached_tokens);
	const cacheWrite = num(details.cache_write_tokens);
	return {
		input: Math.max(0, prompt - cacheRead - cacheWrite),
		output: num(usage.completion_tokens),
		cacheRead,
		cacheWrite,
	};
}

export default function (pi: ExtensionAPI) {
	pi.on("provider_stream_event", (event: ProviderStreamEvent) => {
		const data = event.data as { usage?: Record<string, unknown> } | undefined;
		const usage = data?.usage;
		if (!usage || typeof usage !== "object") return;

		// Deep Infra: `estimated_cost`. OpenRouter-style `cost` is the same idea.
		const reportedTotal = usage.estimated_cost ?? usage.cost;
		if (typeof reportedTotal !== "number" || !Number.isFinite(reportedTotal) || reportedTotal < 0) return;

		const tokens = tokensFromRawUsage(usage);
		if (!tokens) return;

		reported.set(keyOf(event.provider, event.model), { ...tokens, total: reportedTotal });
	});

	pi.on("message_end", (event: MessageEndEvent) => {
		const message = event.message;
		if (message.role !== "assistant") return;

		const key = keyOf(message.provider, message.model);
		const entry = reported.get(key);
		if (!entry) return;

		const usage = message.usage;
		const matches =
			entry.input === usage.input &&
			entry.output === usage.output &&
			entry.cacheRead === usage.cacheRead &&
			entry.cacheWrite === usage.cacheWrite;
		// Leave the entry in place on a mismatch: a cache-warming or routed request
		// can report usage without producing this message, and the next request
		// overwrites the key anyway.
		if (!matches) return;

		reported.delete(key);

		const cost = usage.cost;
		if (cost.total > 0) {
			const scale = entry.total / cost.total;
			cost.input *= scale;
			cost.output *= scale;
			cost.cacheRead *= scale;
			cost.cacheWrite *= scale;
			cost.total = entry.total;
		} else {
			// No base rates configured: spread the reported total over paid tokens.
			const paid = usage.input + usage.output + usage.cacheRead + usage.cacheWrite;
			const share = (tokens: number) => (paid > 0 ? (entry.total * tokens) / paid : 0);
			cost.input = share(usage.input);
			cost.output = share(usage.output);
			cost.cacheRead = share(usage.cacheRead);
			cost.cacheWrite = share(usage.cacheWrite);
			cost.total = entry.total;
		}

		return { message };
	});
}
