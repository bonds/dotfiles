#!/usr/bin/env python3
"""Probe whether a user provider profile's get_usage_cost() overrides Hermes' price table.

Prints the cost Hermes computes for a fixed usage on the Deep Infra route, then
re-registers that provider with a get_usage_cost() that bills from the live
catalogue (list x (1 - discount)) and prints it again plus the ratio.

Run with the Hermes venv python (the store venv, not the system python):

    PY=$(ls -d /nix/store/*-hermes-agent-env/bin/python3 | head -1)
    "$PY" scripts/hermes-cost-probe.py [model-id]

Expected: BEFORE = tokens x list rate; AFTER = (1 - discount) x BEFORE. A ratio of
exactly (1 - discount) means the seam took; 1.0 means the profile was not picked
up. The script also re-checks the bundled profile's own overrides, which a naive
re-registration silently drops.
"""

from __future__ import annotations

import json
import sys
import urllib.request
from decimal import Decimal

CATALOG = "https://api.deepinfra.com/v1/openai/models"
PROVIDER = "deepinfra"
BASE_URL = "https://api.deepinfra.com/v1/openai"
MODEL = sys.argv[1] if len(sys.argv) > 1 else "deepseek-ai/DeepSeek-V4.1-Flash"

# A representative long-context turn: a cached prefix and a small reply.
USAGE = {"input_tokens": 51680, "output_tokens": 5905, "cache_read_tokens": 511616}
TIERS = ("input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens")


def catalog_entry(model_id: str) -> dict:
    with urllib.request.urlopen(CATALOG, timeout=10) as response:
        payload = json.load(response)
    for entry in payload.get("data", []):
        if entry.get("id") == model_id:
            return entry
    raise SystemExit(f"{model_id!r} is not in the Deep Infra catalogue")


def main() -> int:
    from agent.usage_pricing import (
        CanonicalUsage,
        CostResult,
        estimate_usage_cost,
        format_cost_label,
    )
    from providers import get_provider_profile, register_provider

    entry = catalog_entry(MODEL)
    metadata = entry.get("metadata") or {}
    pricing = metadata.get("pricing") or {}
    discount = Decimal(str(metadata.get("discount") or 0))
    factor = Decimal(1) - discount
    print(f"model={MODEL} pricing={pricing} discount={discount} -> billed at {factor}x list")

    usage = CanonicalUsage(**USAGE)
    before = estimate_usage_cost(MODEL, usage, provider=PROVIDER, base_url=BASE_URL)
    print("BEFORE:", before.amount_usd, before.status, before.source, before.pricing_version)

    base = get_provider_profile(PROVIDER)
    if base is None:
        raise SystemExit(f"no {PROVIDER!r} provider profile is registered")

    class Billed(type(base)):  # type: ignore[misc, valid-type]
        """Bills from the catalogue's discounted rate.

        Must not call estimate_usage_cost() again — it would recurse straight
        back into this method.
        """

        def get_usage_cost(self, model, usage):
            amount = Decimal(0)
            for tier in TIERS:
                rate = pricing.get(tier)
                if rate is None:
                    continue
                amount += Decimal(getattr(usage, tier, 0) or 0) * Decimal(str(rate)) * factor
            amount = amount / Decimal(1_000_000)
            return CostResult(
                amount_usd=amount,
                status="estimated",
                source="provider_models_api",
                label=format_cost_label(amount),
                pricing_version="deepinfra-catalogue-discount",
            )

    billed = Billed.__new__(Billed)
    billed.__dict__.update(base.__dict__)  # keep the bundled profile's own overrides
    register_provider(billed)

    after = estimate_usage_cost(MODEL, usage, provider=PROVIDER, base_url=BASE_URL)
    print("AFTER: ", after.amount_usd, after.status, after.source, after.pricing_version)
    if before.amount_usd:
        ratio = Decimal(after.amount_usd) / Decimal(before.amount_usd)
        print(f"ratio: {ratio}   (expected {factor} when the seam took)")

    # A wholesale replacement would have dropped this bundled override.
    kept = billed.build_api_kwargs_extras(reasoning_config={"enabled": False})
    print("bundled overrides kept:", kept == ({}, {"reasoning_effort": "none"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
