/**
 * Model Prices — billed prices in the model picker, lined up for comparison.
 *
 * pi's built-in `/model` selector cannot show this: each row is `id` +
 * `[provider]`, the only free text is `Model Name: <name>` under the list, and
 * an extension may not replace it (`app.model.select` is in
 * `RESERVED_KEYBINDINGS_FOR_EXTENSION_CONFLICTS`, and a command named `model`
 * is skipped in favour of the built-in). So this extension does two things:
 *
 *   1. `/prices` (and `ctrl+shift+l`) opens a picker whose rows are
 *      `<name>   in   out   cache` in billed USD per 1M tokens, aligned in
 *      columns so the four models can be compared at a glance. Enter switches
 *      with `pi.setModel`.
 *   2. It appends `· billed $in/$out/$cache` to each model's `name`, which is
 *      what the built-in `/model` prints for the highlighted model.
 *
 * "Billed" is list price × a multiplier, because Deep Infra discounts are not
 * in models.json (which holds list prices — the only price source pi has, as
 * `deepinfra` has no pi.dev catalog entry) and change without notice:
 *   - `session_start`: one GET of Deep Infra's catalogue, reading
 *     `metadata.discount` (0.51 → billed at 0.49×). The registry resolves the
 *     model's configured `apiKey`, which is the `!command` reading
 *     /run/agenix/hermes-deepinfra at request time, so no key handling here.
 *   - every turn after that: the same `usage.estimated_cost` `reported-cost.ts`
 *     trusts, divided by pi's list-price total for the same token counts. That
 *     is what was actually charged, so it outranks the published discount and
 *     an expired promo corrects itself on the next turn.
 *
 * Until a multiplier is known for a model, no price is shown at all rather than
 * a list price passed off as billed; the picker labels those rows as list.
 *
 * Applying a name means re-registering the provider's models: the registry
 * rebuilds its snapshot from models.json on every refresh (the built-in picker
 * triggers one), so mutating a Model in place would be lost. Only `name`
 * changes; every other field is copied from the live model, and re-registering
 * merges over the provider config, so apiKey/baseUrl survive. A rejected
 * registration or a dead catalogue is logged and leaves the plain names alone.
 */

import type { Model } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, ProviderStreamEvent } from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import { Container, Key, type SelectItem, SelectList, Spacer, Text } from "@earendil-works/pi-tui";

const PROVIDER = "deepinfra";
const CATALOG_URL = "https://api.deepinfra.com/v1/openai/models";

/** Marks where the generated suffix starts, so it can be replaced rather than appended twice. */
const SUFFIX = " · billed ";

/** SelectList pads the label column to this width; descriptions start at prefix (2) + this. */
const LABEL_COLUMN = 32;
const PRICE_COLUMN = LABEL_COLUMN + 2;

const MEASURED = 2;
const PUBLISHED = 1;

interface TokenCounts {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
}

/** model id → billed/list multiplier, with the priority of the source that set it. */
const multipliers = new Map<string, { value: number; source: number }>();

/**
 * Human-written part of each model name, captured once.
 *
 * Needed because the suffix is rebuilt from scratch on every apply: a model
 * whose `cost` is missing gets no suffix at all, so stripping would find
 * nothing and the generated text would be appended again each time. Capturing
 * the base once makes `formatName` idempotent for every model.
 */
const baseNames = new Map<string, string>();

function num(value: unknown): number {
	const parsed = typeof value === "number" ? value : Number(value);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

/** Same normalization as `reported-cost.ts`, so the token counts match pi's. */
function tokensFromRawUsage(raw: Record<string, unknown>): TokenCounts {
	const details = (raw.prompt_tokens_details ?? {}) as Record<string, unknown>;
	const prompt = num(raw.prompt_tokens);
	const cacheRead = num(details.cached_tokens ?? raw.prompt_cache_hit_tokens ?? raw.cached_tokens);
	const cacheWrite = num(details.cache_write_tokens);
	return {
		input: Math.max(0, prompt - cacheRead - cacheWrite),
		output: num(raw.completion_tokens),
		cacheRead,
		cacheWrite,
	};
}

/** USD per million tokens for one request, priced exactly as pi prices it. */
function listCost(model: Model<any>, tokens: TokenCounts): number {
	const cost = model.cost;
	if (!cost) return 0;
	return (
		(tokens.input * (cost.input ?? 0) +
			tokens.output * (cost.output ?? 0) +
			tokens.cacheRead * (cost.cacheRead ?? 0) +
			tokens.cacheWrite * (cost.cacheWrite ?? 0)) /
		1_000_000
	);
}

/** "0.098" — fixed 3 decimals, the shape used for in/out everywhere. */
function price(value: number): string {
	return value.toFixed(3);
}

/** "0.0029" — cache reads are an order of magnitude cheaper, so they need a digit more. */
function cachePrice(value: number): string {
	return value.toFixed(4);
}

function pad(text: string, width: number): string {
	return text.length >= width ? text : " ".repeat(width - text.length) + text;
}

function contextLabel(window: number): string {
	if (!window) return "";
	if (window >= 1_000_000) return `${Math.round((window / 1_048_576) * 10) / 10}M ctx`;
	return `${Math.round(window / 1024)}k ctx`;
}

function setMultiplier(modelId: string, value: number, source: number): boolean {
	const current = multipliers.get(modelId);
	if (current && current.source > source) return false;
	if (current && Math.abs(current.value - value) < 0.005) return false;
	multipliers.set(modelId, { value, source });
	return true;
}

/** Billed/list multiplier, or undefined while neither source has answered. */
function multiplierFor(model: Model<any>): number | undefined {
	return multipliers.get(model.id)?.value;
}

function stripSuffix(name: string): string {
	const at = name.indexOf(SUFFIX);
	return at === -1 ? name : name.slice(0, at);
}

function baseName(model: Model<any>): string {
	const known = baseNames.get(model.id);
	if (known !== undefined) return known;
	const base = stripSuffix(model.name);
	baseNames.set(model.id, base);
	return base;
}

/** Billed price of the three token kinds, or undefined until the discount is known. */
function billed(model: Model<any>): { input: string; output: string; cache: string } | undefined {
	const cost = model.cost;
	const multiplier = multiplierFor(model);
	if (!cost || (cost.input === 0 && cost.output === 0) || multiplier === undefined) return undefined;
	return {
		input: price(cost.input * multiplier),
		output: price(cost.output * multiplier),
		cache: cachePrice(cost.cacheRead * multiplier),
	};
}

/** The picker's columns: `0.098  0.294  0.0029`, padded so every row aligns. */
function priceColumns(model: Model<any>): string {
	const prices = billed(model);
	if (!prices) return `${pad("—", 6)} ${pad("—", 6)} ${pad("—", 7)}`;
	return `${pad(prices.input, 6)} ${pad(prices.output, 6)} ${pad(prices.cache, 7)}`;
}

function formatName(model: Model<any>): string {
	const prices = billed(model);
	if (!prices) return baseName(model);
	return `${baseName(model)}${SUFFIX}$${prices.input}/$${prices.output}/$${prices.cache}`;
}

export default function (pi: ExtensionAPI) {
	/** Re-register the provider's models with freshly formatted names. */
	function apply(ctx: ExtensionContext): void {
		const models = ctx.modelRegistry.getAll().filter((model) => model.provider === PROVIDER);
		if (models.length === 0) return;

		let changed = false;
		const renamed = models.map((model) => {
			const name = formatName(model);
			if (name === model.name) return model;
			changed = true;
			return { ...model, name };
		});
		if (!changed) return;

		try {
			pi.registerProvider(PROVIDER, { models: renamed });
		} catch (error) {
			// Keep the plain names; the picker is a convenience, not a dependency.
			console.error(`model-prices: ${error instanceof Error ? error.message : String(error)}`);
		}
	}

	/** Measured multiplier from one request, when the provider reports a cost. */
	function observe(event: ProviderStreamEvent, ctx: ExtensionContext): void {
		const usage = (event.data as { usage?: Record<string, unknown> } | undefined)?.usage;
		if (!usage || typeof usage !== "object") return;

		const reported = num(usage.estimated_cost ?? usage.cost);
		if (reported <= 0) return;

		const model = ctx.modelRegistry.find(event.provider, event.model);
		if (!model) return;

		const tokens = tokensFromRawUsage(usage);
		if (tokens.input + tokens.output + tokens.cacheRead + tokens.cacheWrite === 0) return;

		const list = listCost(model, tokens);
		if (list <= 0) return;

		// A ratio outside this band means the two numbers disagree about
		// something structural (different pricing basis, or a partial report),
		// not a discount — leave the published value alone.
		const ratio = reported / list;
		if (ratio < 0.05 || ratio > 5) return;

		setMultiplier(model.id, Math.round(ratio * 1000) / 1000, MEASURED);
	}

	/** Published multiplier from Deep Infra's catalogue; one call per session. */
	async function refreshCatalog(ctx: ExtensionContext): Promise<void> {
		const model = ctx.modelRegistry.getAll().find((entry) => entry.provider === PROVIDER);
		if (!model) return;

		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
		if (!auth.ok || !auth.apiKey) return;

		const response = await fetch(CATALOG_URL, {
			headers: { Authorization: `Bearer ${auth.apiKey}` },
			signal: AbortSignal.timeout(10_000),
		});
		if (!response.ok) return;

		const body = (await response.json()) as {
			data?: Array<{ id?: string; metadata?: { discount?: number | null } }>;
		};

		let changed = false;
		for (const entry of body.data ?? []) {
			if (!entry?.id) continue;
			const discount = num(entry.metadata?.discount);
			// No discount published means full price — still worth recording, so a
			// model that stopped being discounted drops its discount note.
			const value = discount > 0 && discount < 1 ? Math.round((1 - discount) * 1000) / 1000 : 1;
			if (setMultiplier(entry.id, value, PUBLISHED)) changed = true;
		}
		if (changed) apply(ctx);
	}

	/** The models worth comparing: the session's scope (the ctrl+p cycle) if set. */
	function pickableModels(ctx: ExtensionContext): Model<any>[] {
		const chat = (model: Model<any>) => model.provider === PROVIDER && (model.type ?? "chat") === "chat";
		const scoped = ctx.scopedModels.map((entry) => entry.model).filter(chat);
		if (scoped.length > 0) return scoped;
		return ctx.modelRegistry.getAll().filter(chat);
	}

	function detailLine(model: Model<any>): string {
		const parts = [baseName(model), `${model.provider}/${model.id}`];
		const context = contextLabel(model.contextWindow);
		if (context) parts.push(context);
		const multiplier = multiplierFor(model);
		if (multiplier === undefined) parts.push("no discount data yet");
		else if (Math.abs(multiplier - 1) >= 0.005) {
			const percent = Math.round(Math.abs(1 - multiplier) * 100);
			parts.push(multiplier < 1 ? `${percent}% off list` : `${percent}% over list`);
		}
		return parts.join(" · ");
	}

	async function showPicker(ctx: ExtensionContext): Promise<void> {
		if (ctx.mode !== "tui") {
			ctx.ui.notify("Prices need the interactive UI.", "warning");
			return;
		}

		const models = pickableModels(ctx);
		if (models.length === 0) {
			ctx.ui.notify("No models to price.", "warning");
			return;
		}

		const currentIndex = models.findIndex((model) => model.id === ctx.model?.id && model.provider === ctx.model?.provider);

		const items: SelectItem[] = models.map((model, index) => ({
			value: `${model.provider}/${model.id}`,
			label: `${index === currentIndex ? "✓ " : ""}${baseName(model)}`,
			description: priceColumns(model),
		}));

		const result = await ctx.ui.custom<string | null>((tui, theme, _kb, done) => {
			const container = new Container();
			container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
			container.addChild(new Spacer(1));
			container.addChild(
				new Text(
					`${theme.fg("accent", theme.bold("Billed prices"))}${theme.fg("muted", " · USD per 1M tokens")}`,
					0,
					0,
				),
			);
			container.addChild(
				new Text(
					theme.fg("muted", `${" ".repeat(PRICE_COLUMN)}${pad("in", 6)} ${pad("out", 6)} ${pad("cache", 7)}`),
					0,
					0,
				),
			);
			container.addChild(new Spacer(1));

			const list = new SelectList(items, Math.min(items.length, 12), {
				selectedPrefix: (text) => theme.fg("accent", text),
				selectedText: (text) => theme.fg("accent", text),
				description: (text) => theme.fg("muted", text),
				scrollInfo: (text) => theme.fg("dim", text),
				noMatch: (text) => theme.fg("warning", text),
			}, { minPrimaryColumnWidth: LABEL_COLUMN, maxPrimaryColumnWidth: LABEL_COLUMN });

			const detail = new Text("", 0, 0);
			const describe = (value: string) => {
				const model = models.find((entry) => `${entry.provider}/${entry.id}` === value);
				detail.setText(theme.fg("muted", `  ${model ? detailLine(model) : ""}`));
			};

			list.onSelectionChange = (item) => describe(item.value);
			list.onSelect = (item) => done(item.value);
			list.onCancel = () => done(null);
			if (currentIndex >= 0) list.setSelectedIndex(currentIndex);
			describe(items[Math.max(0, currentIndex)]?.value ?? items[0].value);

			container.addChild(list);
			container.addChild(new Spacer(1));
			container.addChild(detail);
			container.addChild(new Text(theme.fg("dim", "  ↑↓ choose · enter switch · esc cancel"), 0, 0));
			container.addChild(new Spacer(1));
			container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));

			return {
				render(width: number) {
					return container.render(width);
				},
				invalidate() {
					container.invalidate();
				},
				handleInput(data: string) {
					list.handleInput(data);
					tui.requestRender();
				},
			};
		});

		if (!result) return;

		const chosen = models.find((model) => `${model.provider}/${model.id}` === result);
		if (!chosen) return;
		if (currentIndex >= 0 && models[currentIndex] === chosen) return;

		const switched = await pi.setModel(chosen);
		if (!switched) {
			ctx.ui.notify(`No credentials for ${chosen.provider}/${chosen.id}.`, "warning");
		}
	}

	pi.registerCommand("prices", {
		description: "Compare models by billed price and switch",
		handler: async (_args, ctx) => {
			await showPicker(ctx);
		},
	});

	// Not ctrl+l: `app.model.select` is a reserved keybinding that extensions
	// may not override, so the built-in selector keeps that key.
	pi.registerShortcut(Key.ctrlShift("l"), {
		description: "Compare models by billed price",
		handler: async (ctx) => {
			await showPicker(ctx);
		},
	});

	pi.on("session_start", (_event, ctx) => {
		apply(ctx);
		void refreshCatalog(ctx).catch((error: unknown) => {
			console.error(`model-prices: catalogue refresh failed: ${error instanceof Error ? error.message : String(error)}`);
		});
	});

	pi.on("provider_stream_event", (event, ctx) => {
		observe(event, ctx);
	});

	// Rename at the end of a turn rather than per stream event: the multiplier
	// has settled by then, and a re-registration per token chunk would churn the
	// model snapshot for nothing.
	pi.on("turn_end", (_event, ctx) => {
		apply(ctx);
	});
}
