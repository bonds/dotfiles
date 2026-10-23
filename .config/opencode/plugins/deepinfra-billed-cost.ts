// Re-prices Deep Infra models at the rate Deep Infra actually bills.
//
// OpenCode computes a step's cost itself, from the selected model's `cost`
// (`tokens × price / 1e6`), and never reads the provider's own
// `usage.estimated_cost`. Deep Infra runs standing discounts (e.g. 51% off
// DeepSeek-V4.1-Flash-1017), so the built-in figure overstates the bill unless
// the configured prices are already discounted.
//
// This plugin reads the live catalogue (`metadata.discount`) and scales each
// Deep Infra model's cost tiers by (1 - discount) through a model transform.
// Cost is computed once per step at completion, so this only affects steps
// taken while the plugin is loaded — recorded history is never rewritten.
//
// Fails safe: if the catalogue cannot be read, the configured (list) prices
// stay in force.

import { Plugin } from "@opencode/plugin"

const CATALOG_URL = "https://api.deepinfra.com/v1/openai/models"
const PROVIDER_ID = "deepinfra"
const REFRESH_MS = 30 * 60 * 1000
const FETCH_TIMEOUT_MS = 5000

type CatalogEntry = {
  id?: string
  metadata?: { discount?: number | null }
}

// modelID (as sent to Deep Infra) -> discount, e.g. 0.51 means 51% off.
async function loadDiscounts(): Promise<Map<string, number>> {
  const response = await fetch(CATALOG_URL, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  })
  if (!response.ok) throw new Error(`catalogue returned ${response.status}`)

  const body = (await response.json()) as { data?: CatalogEntry[] }
  const discounts = new Map<string, number>()
  for (const entry of body.data ?? []) {
    const discount = entry.metadata?.discount
    if (!entry.id || typeof discount !== "number") continue
    if (discount <= 0 || discount >= 1) continue
    discounts.set(entry.id, discount)
  }
  return discounts
}

export default Plugin.define({
  id: "deepinfra.billed-cost",
  async setup(ctx) {
    // Captured by the transform below; replaced wholesale before each reload.
    let discounts = new Map<string, number>()

    await ctx.model.transform((editor) => {
      for (const model of editor.list(PROVIDER_ID)) {
        const discount = discounts.get(model.modelID)
        if (discount === undefined) continue
        const factor = 1 - discount
        // Transforms replay from the source definition, so this scales the
        // configured list price exactly once per rebuild.
        editor.update(PROVIDER_ID, model.id, (draft) => {
          draft.cost = draft.cost.map((tier) => ({
            ...tier,
            input: tier.input * factor,
            output: tier.output * factor,
            cache: {
              read: tier.cache.read * factor,
              write: tier.cache.write * factor,
            },
          }))
        })
      }
    })

    let warned = false
    const refresh = async () => {
      try {
        discounts = await loadDiscounts()
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
      }
    }

    await refresh()
    const timer = setInterval(() => void refresh(), REFRESH_MS)
    return () => clearInterval(timer)
  },
})
