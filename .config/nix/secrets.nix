let
  sophrosyne = "age1vxpudu9t80ta3wejdfugt9t3vxlk4t4uswu92t6juq0kd40h73rsvrv088";
  accismus-yubikey = "age1yubikey1qwh2pyyk0fv6n37gh4aav8njtvmxlegm3fsegsmek0w4wu7nkl3gk00hkpq";
  accismus-host = "age1h5dxs39pnxxsh986engn2w6f2y337khvx6kmxlrucnfl878w7vgsp4k7fl";
in {
  "/Users/scott/.config/nix/secrets/ddns-token.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/email-pass.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/dst-cluster-token.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/searx-secret-key.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/reel-ig-cookies.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/osaurus-api-key.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  "/Users/scott/.config/nix/secrets/soju-password.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  "/Users/scott/.config/nix/secrets/hermes-openrouter.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  # DeepInfra API key for Hermes Agent. Content is the env line
  # (`DEEPINFRA_API_KEY=<key>`), merged into $HERMES_HOME/.env alongside the
  # OpenRouter key. Separate file per provider so the two rotate independently.
  "/Users/scott/.config/nix/secrets/hermes-deepinfra.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  # DeepInfra API key for OpenCode (the opencode `deepinfra` provider's
  # `settings.apiKey`, read through a `{file:...}` substitution). Content is the
  # BARE key, not an env line, because OpenCode reads the file verbatim. Its own
  # file (not Hermes') so each harness's key rotates independently.
  "/Users/scott/.config/nix/secrets/opencode-deepinfra.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  # Serper web-search key for Raven (tools.web.search.apiKey). Content is the
  # bare key; an activation script merges it into ~/.raven/config.json.
  "/Users/scott/.config/nix/secrets/serper-api-key.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
}
