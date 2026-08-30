let
  sophrosyne = "age1vxpudu9t80ta3wejdfugt9t3vxlk4t4uswu92t6juq0kd40h73rsvrv088";
  accismus-yubikey = "age1yubikey1qwh2pyyk0fv6n37gh4aav8njtvmxlegm3fsegsmek0w4wu7nkl3gk00hkpq";
  accismus-host = "age1h5dxs39pnxxsh986engn2w6f2y337khvx6kmxlrucnfl878w7vgsp4k7fl";
in {
  "/Users/scott/.config/nix/secrets/ddns-token.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/email-pass.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/dst-cluster-token.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/searx-secret-key.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/osaurus-api-key.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  "/Users/scott/.config/nix/secrets/soju-password.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
  "/Users/scott/.config/nix/secrets/hermes-openrouter.age".publicKeys = [sophrosyne accismus-yubikey accismus-host];
}
