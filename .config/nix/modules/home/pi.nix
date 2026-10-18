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
{
  config,
  lib,
  pkgs,
  ...
}: {
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
        }
      ];
    };
  };

  # settings.json is the opposite case: pi WRITES it at runtime (it bumped
  # `lastChangelogVersion` on first launch), so a read-only home.file symlink
  # would clobber pi's own writes. Merge our three keys in with jq instead —
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
      '.defaultProvider = "deepinfra"
       | .defaultModel = "deepseek-ai/DeepSeek-V4.1-Flash-1017"
       | .defaultThinkingLevel = "high"' "$piSettings" > "$piTmp"; then
      mv "$piTmp" "$piSettings"
    else
      rm -f "$piTmp"
      echo "warning: pi settings.json merge failed; left unchanged" >&2
    fi
  '';
}
