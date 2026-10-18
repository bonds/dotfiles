# pi (earendil-works/pi) — Deep Infra provider + DeepSeek-V4.1-Flash-1017 default.
#
# accismus-only: this module is imported solely by the accismus home-manager
# block (hosts/accismus/configuration.nix), so it needs no `enable` option —
# same shape as polyptych.nix.
#
# The API key is NOT stored here. pi's config has no keychain/agenix binding,
# but its `apiKey` accepts a leading `!command` which it runs at request time;
# models.json therefore carries only a command that reads the key out of the
# agenix-decrypted env file — the SAME secret hermes-agent uses
# (secrets/hermes-deepinfra.age → /run/agenix/hermes-deepinfra, declared in
# hosts/accismus/configuration.nix, mode 0400 owner scott). Only the reference
# is tracked; the literal key never enters the (public) repo.
#
# Everything pi READS is a read-only home.file symlink into this repo, so the
# setup is reproducible on any machine and reviewable in git:
#
#   pkgs/pi/extensions/   safety extensions (protected paths, permission gate,
#                         git checkpoint, dirty-repo guard)
#   pkgs/pi/skills/       code-review skill
#   pkgs/pi/prompts/      /review, /ship, /nr, /learn
#   pkgs/pi/keybindings.json
#   (mcp.json is generated below)
#
# Only settings.json is merged instead of symlinked, because pi writes it at
# runtime. Consequence of the symlinks: `pi install` / `pi mcp add` cannot
# persist into these paths — edit the repo and re-run `nr` instead.
{
  config,
  lib,
  pkgs,
  ...
}: let
  piConfig = ../../pkgs/pi;
in {
  # pi only READS models.json (its writable, auto-refreshed catalog is
  # models-store.json), so a read-only home.file symlink is safe here.
  home.file.".pi/agent/models.json".text = builtins.toJSON {
    providers.deepinfra = {
      name = "Deep Infra";
      baseUrl = "https://api.deepinfra.com/v1/openai";
      api = "openai-completions";
      apiKey = "!/usr/bin/sed -n 's/^DEEPINFRA_API_KEY=//p' /run/agenix/hermes-deepinfra";
      models = [
        {
          id = "deepseek-ai/DeepSeek-V4.1-Flash-1017";
          name = "DeepSeek V4.1 Flash 1017 (Deep Infra)";
          api = "openai-completions";
          reasoning = true;
          input = ["text" "image"];
          contextWindow = 1048576;
          maxTokens = 1048576;
          compat.maxTokensField = "max_tokens";

          # USD per MILLION tokens — required for /session and the footer to
          # show a cost at all. Without this object pi reports every request
          # at $0: pi prices requests as `tokens x model.cost` and never reads
          # a cost field out of the provider response, and `deepinfra` has no
          # pi.dev catalog entry to supply prices.
          #
          # These are Deep Infra's LIST prices for this model
          # (`curl api.deepinfra.com/v1/openai/models` -> metadata.pricing):
          # input 0.2, output 0.6, cache_read 0.006. There is no cache_write
          # price (prompt caching is implicit, writes bill at the input rate),
          # and the OpenAI-compatible API only reports cached_tokens
          # (cacheRead), so cacheWrite tokens stay 0.
          #
          # They are NOT what we are billed: this model currently carries
          # `metadata.discount: 0.51`, so the effective rate is 0.49x of list,
          # and discounts expire without notice. The `reported-cost.ts`
          # extension (pkgs/pi/extensions/) rewrites each finished message's
          # usage.cost from Deep Infra's own per-request `usage.estimated_cost`,
          # rescaling these components proportionally. So: keep list prices
          # here as the shape/fallback, let the extension supply the real
          # number. If Deep Infra stops reporting a cost, /session falls back
          # to roughly 2x the true cost until this object is updated.
          cost = {
            input = 0.2;
            output = 0.6;
            cacheRead = 0.006;
            cacheWrite = 0.2;
          };
        }
      ];
    };
  };

  # Skills, prompts, extensions and keybindings: read-only, discovered by
  # convention (no settings arrays needed).
  home.file.".pi/agent/extensions".source = piConfig + "/extensions";
  home.file.".pi/agent/skills".source = piConfig + "/skills";
  home.file.".pi/agent/prompts".source = piConfig + "/prompts";
  home.file.".pi/agent/keybindings.json".source = piConfig + "/keybindings.json";

  # MCP servers. reel-summarize-mcp runs on sophrosyne and speaks streamable
  # HTTP; the `/sse` path is only a path name (pi rejects the legacy SSE
  # transport, not this URL). Reachable over Tailscale only. The bearer token
  # is optional on the server side; set REEL_SUMMARIZE_MCP_TOKEN here if it is
  # ever enabled there.
  home.file.".pi/agent/mcp.json".text = builtins.toJSON {
    mcpServers.reel-summarize = {
      url = "http://sophrosyne.taileafac.ts.net:8892/sse";
      description = "Summarize Instagram Reels: transcript, sampled frames, vision OCR, final summary.";
    };
  };

  # settings.json is the opposite case: pi WRITES it at runtime (it bumped
  # `lastChangelogVersion` on first launch), so a read-only home.file symlink
  # would clobber pi's own writes. Merge our keys in with jq instead —
  # the same preserve-all-other-keys pattern used for Raven's config.json in
  # hosts/accismus/configuration.nix postActivation. Idempotent, so a re-run
  # never aborts activation under `set -e`.
  home.activation.piSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    piSettings="${config.home.homeDirectory}/.pi/agent/settings.json"
    mkdir -p "$(dirname "$piSettings")"
    if [ ! -f "$piSettings" ]; then
      echo '{}' > "$piSettings"
    fi
    piTmp="$(mktemp "$piSettings.XXXXXX")"
    if ${pkgs.jq}/bin/jq \
      '."$schema" = "https://pi.dev/schemas/settings.schema.json"
       | .defaultProvider = "deepinfra"
       | .defaultModel = "deepseek-ai/DeepSeek-V4.1-Flash-1017"
       | .defaultThinkingLevel = "high"
       | .theme = "system"
       | .quietStartup = "header"
       | .enableInstallTelemetry = false' "$piSettings" > "$piTmp"; then
      mv "$piTmp" "$piSettings"
    else
      rm -f "$piTmp"
      echo "warning: pi settings.json merge failed; left unchanged" >&2
    fi
  '';
}
