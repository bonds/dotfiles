# The Deep Infra provider block, shared by every harness here that speaks the
# pi models format: pi (`~/.pi/agent/models.json`, JSON) and OMP
# (`~/.omp/agent/models.yml`, YAML). Both accept the same camelCase field names,
# so one nix attrset feeds both — models, prices and the API-key command cannot
# drift between the two agents.
#
# The API key is NOT stored here. `apiKey` accepts a leading `!command`, which
# the harness runs at request time; this reads the key out of the
# agenix-decrypted env file — the SAME secret hermes-agent uses
# (secrets/hermes-deepinfra.age -> /run/agenix/hermes-deepinfra, declared in
# hosts/accismus/configuration.nix, mode 0400 owner scott). Only the reference is
# tracked; the literal key never enters the (public) repo.
#
# Cost fields are Deep Infra's LIST prices (USD per MILLION tokens), which the
# harnesses need to report a cost at all; the per-request billed figure comes
# from Deep Infra's own `usage.estimated_cost` (pi's reported-cost.ts extension
# rewrites usage.cost from it). See modules/home/pi.nix for the full story.
{
  name = "Deep Infra";
  baseUrl = "https://api.deepinfra.com/v1/openai";
  api = "openai-completions";
  apiKey = "!/usr/bin/sed -n 's/^DEEPINFRA_API_KEY=//p' /run/agenix/hermes-deepinfra";
  models = [
    {
      id = "deepseek-ai/DeepSeek-V4.1-Flash-1017";
      # Plain label: `model-prices.ts` appends the billed prices, which
      # is what the built-in /model selector prints for the highlighted
      # model (`Model Name: <name>`) — its rows are `id` + `[provider]`
      # only, and an extension may not replace it (a command named
      # `model` is skipped in favour of the built-in). Billed rather than
      # list prices live there because the discount is per model, and
      # that is also why they are not written here: this file is static,
      # the discount is not.
      name = "DeepSeek V4.1 Flash 1017";
      api = "openai-completions";
      reasoning = true;
      input = ["text" "image"];
      contextWindow = 1048576;
      # Deep Infra reports `max_tokens` == `context_length` for this
      # model (metadata, `curl api.deepinfra.com/v1/openai/models`), so
      # this is the provider's own ceiling, not a typo. pi clamps it to
      # the room left in the context anyway.
      maxTokens = 1048576;
      compat.maxTokensField = "max_tokens";

      # USD per MILLION tokens — required for /session and the footer
      # to show a cost at all. Without this object pi reports every
      # request at $0: pi prices requests as `tokens x model.cost` and
      # never reads a cost field out of the provider response, and
      # `deepinfra` has no pi.dev catalog entry to supply prices.
      #
      # These are Deep Infra's LIST prices for this model
      # (`curl api.deepinfra.com/v1/openai/models` -> metadata.pricing):
      # input 0.2, output 0.6, cache_read 0.006. There is no cache_write
      # price (prompt caching is implicit, writes bill at the input
      # rate), and the OpenAI-compatible API only reports cached_tokens
      # (cacheRead), so cacheWrite tokens stay 0.
      #
      # They are NOT what we are billed: this model currently carries
      # `metadata.discount: 0.51`, so the effective rate is 0.49x of
      # list, and discounts expire without notice. The `reported-cost.ts`
      # extension (pkgs/pi/extensions/) rewrites each finished message's
      # usage.cost from Deep Infra's own per-request
      # `usage.estimated_cost`, rescaling these components
      # proportionally. So: keep list prices here as the
      # shape/fallback, let the extension supply the real number. If
      # Deep Infra stops reporting a cost, /session falls back to
      # roughly 2x the true cost until this object is updated.
      cost = {
        input = 0.2;
        output = 0.6;
        cacheRead = 0.006;
        cacheWrite = 0.2;
      };
    }

    # Cheap/fast partners for Ctrl+P cycling (`enabledModels` below).
    # All four are cheaper than the 1017 on input and all but Qwen3.8
    # Flash are vision-capable; prices are Deep Infra's list prices from
    # the same `metadata.pricing` response as the model above. Where
    # `metadata.discount` is set it is noted per model — list price is
    # kept here as the fallback shape, and `reported-cost.ts` supplies
    # the real per-request number.
    {
      # $0.20/$2.50 list, discount 0.25 (billed ~0.75x). 256k context,
      # not 1M — the tightest of the four. Dense 27B, so output is the
      # expensive side; good for short answers, not long generations.
      id = "Qwen/Qwen3.8-27B";
      name = "Qwen3.8 27B";
      api = "openai-completions";
      reasoning = true;
      input = ["text" "image"];
      contextWindow = 262144;
      maxTokens = 262144;
      compat.maxTokensField = "max_tokens";
      cost = {
        input = 0.2;
        output = 2.5;
        cacheRead = 0.05;
        cacheWrite = 0.2;
      };
    }
    {
      # $0.075/$0.25 list, no discount — the cheapest output rate in
      # the cycle by an order of magnitude, with the 1017's 1M context.
      id = "zai-org/GLM-5.3-Flash";
      name = "GLM-5.3 Flash";
      api = "openai-completions";
      reasoning = true;
      input = ["text" "image"];
      contextWindow = 1048576;
      maxTokens = 1048576;
      compat.maxTokensField = "max_tokens";
      cost = {
        input = 0.075;
        output = 0.25;
        cacheRead = 0.015;
        cacheWrite = 0.075;
      };
    }
    {
      # $0.113/$0.382 list, no discount. Text-only (its catalogue tags
      # are chat/prompt_cache/reasoning_effort — no `vision`, unlike the
      # 27B), 1M context at a flat rate across the whole window, and it
      # accepts a reasoning effort. Sits between GLM (cheaper) and MiMo
      # (pricier) on output.
      id = "Qwen/Qwen3.8-Flash";
      name = "Qwen3.8 Flash";
      api = "openai-completions";
      reasoning = true;
      input = ["text"];
      contextWindow = 1000000;
      maxTokens = 1000000;
      compat.maxTokensField = "max_tokens";
      cost = {
        input = 0.113;
        output = 0.382;
        # Catalogue reports 0.01409999988; rounded, and only the
        # reported per-request cost is billed anyway.
        cacheRead = 0.0141;
        cacheWrite = 0.113;
      };
    }
    {
      # $0.14/$0.28 list, discount 0.05 (billed ~0.95x). Omnimodal
      # (text/image/video/audio) with 1M context and a very cheap
      # cache read, so it is the pick for long cached-context runs.
      id = "XiaomiMiMo/MiMo-V2.6-Flash";
      name = "MiMo V2.6 Flash";
      api = "openai-completions";
      reasoning = true;
      input = ["text" "image"];
      contextWindow = 1048576;
      maxTokens = 1048576;
      compat.maxTokensField = "max_tokens";
      cost = {
        input = 0.14;
        output = 0.28;
        cacheRead = 0.0028;
        cacheWrite = 0.14;
      };
    }
  ];
}
