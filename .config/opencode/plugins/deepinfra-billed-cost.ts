// Re-prices Deep Infra models at the rate Deep Infra actually bills.
//
// OpenCode computes a step's cost itself, from the selected model's `cost`
// (`tokens × price / 1e6`), and never reads the provider's own
// `usage.estimated_cost`. Deep Infra runs per-model standing discounts (e.g.
// 51% off DeepSeek-V4.1-Flash-1017, 75% off Ling-3.1-flash), so the built-in
// figure overstates the bill unless prices are already discounted.
//
// This plugin reads Deep Infra's live catalogue and, through a model
// transform, reprices each Deep Infra model from its own `metadata.pricing`
// scaled by `(1 - metadata.discount)`. The catalogue price is the billed base;
// the model's configured price is only scaled as a fallback when the catalogue
// omits pricing. Models without a discount are left alone.
//
// Cost is computed once per step at completion, so this only affects steps
// taken while the plugin is loaded — recorded history is never rewritten.
//
// Fails safe: if the catalogue cannot be read, the configured (list) prices
// stay in force.

import { Plugin } from "@opencode/plugin"

const CATALOG_URL = "https://api.deepinfra.com/v1/openai/models"
const PROVIDER_ID = "deepinfra"
const REFRESH_MS = 30 * 60 * 1000
const MIN_REFRESH_MS = 60 * 1000
const FETCH_TIMEOUT_MS = 5000

type Pricing = {
  input_tokens?: number | null
  output_tokens?: number | null
  cache_read_tokens?: number | null
  cache_write_tokens?: number | null
}

type CatalogEntry = {
  id?: string
  metadata?: { discount?: number | null; pricing?: Pricing | null }
}

type Discount = {
  factor: number
  pricing?: Pricing
}

// modelID (as sent to Deep Infra) -> its discount. A discount of 0.51 means
// 51% off, i.e. bill at 0.49x the list price.
async function loadCatalog(): Promise<Map<string, Discount>> {
  const response = await fetch(CATALOG_URL, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  })
  if (!response.ok) throw new Error(`catalogue returned ${response.status}`)

  const body = (await response.json()) as { data?: CatalogEntry[] }
  const catalog = new Map<string, Discount>()
  for (const entry of body.data ?? []) {
    const discount = entry.metadata?.discount
    if (!entry.id || typeof discount !== "number") continue
    if (discount <= 0 || discount >= 1) continue
    catalog.set(entry.id, {
      factor: 1 - discount,
      pricing: entry.metadata?.pricing ?? undefined,
    })
  }
  return catalog
}

export default Plugin.define({
  id: "deepinfra.billed-cost",
  async setup(ctx) {
    // Captured by the transform below; replaced wholesale before each reload.
    let catalog = new Map<string, Discount>()

    await ctx.model.transform((editor) => {
      for (const model of editor.list(PROVIDER_ID)) {
        const entry = catalog.get(model.modelID)
        if (!entry) continue
        const { factor, pricing } = entry
        // Transforms replay from the source definition, so this reprices the
        // configured cost exactly once per rebuild.
        editor.update(PROVIDER_ID, model.id, (draft) => {
          draft.cost = draft.cost.map((tier) => {
            // The catalogue price is authoritative for the base tier. A
            // tiered entry (>200k context) has no catalogue equivalent, so it
            // is scaled instead.
            const useCatalog = tier.tier === undefined && pricing !== undefined
            const price = (catalogValue: number | null | undefined, fallback: number) =>
              useCatalog && catalogValue != null ? catalogValue * factor : fallback * factor
            return {
              ...tier,
              input: price(pricing?.input_tokens, tier.input),
              output: price(pricing?.output_tokens, tier.output),
              cache: {
                read: price(pricing?.cache_read_tokens, tier.cache.read),
                write: price(pricing?.cache_write_tokens, tier.cache.write),
              },
            }
          })
        })
      }
    })

    let lastFetch = 0
    let warned = false
    let running: Promise<void> | null = null

    const refresh = async (force = false): Promise<void> => {
      if (running) return running
      if (!force && Date.now() - lastFetch < MIN_REFRESH_MS) return

      running = (async () => {
        try {
          catalog = await loadCatalog()
          lastFetch = Date.now()
          warned = false
          await ctx.model.reload()
        } catch (error) {
          // Keep list prices; warn once so a persistent outage is not noisy.
          if (!warned) {
            warned = true
            console.warn(
              `deepinfra.billed-cost: keeping list prices (${error instanceof Error ? error.message : error})`,
            )
          }
        } finally {
          running = null
        }
      })()
      return running
    }

    await refresh(true)

    // A discount can appear or expire between polls; re-check when a session
    // starts work rather than waiting up to REFRESH_MS. MIN_REFRESH_MS keeps
    // rapid back-to-back sessions from hammering the catalogue.
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (event.type === "session.execution.started") void refresh()
        }
      } catch {
        // Subscription ends when the plugin unloads.
      }
    })()

    const timer = setInterval(() => void refresh(), REFRESH_MS)
    return () => {
      controller.abort()
      clearInterval(timer)
    }
  },
})
