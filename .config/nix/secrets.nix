let
  sophrosyne = "age1vxpudu9t80ta3wejdfugt9t3vxlk4t4uswu92t6juq0kd40h73rsvrv088";
  accismus-yubikey = "age1yubikey1qwh2pyyk0fv6n37gh4aav8njtvmxlegm3fsegsmek0w4wu7nkl3gk00hkpq";
in {
  "/Users/scott/.config/nix/secrets/ddns-token.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/email-pass.age".publicKeys = [sophrosyne accismus-yubikey];
  "/Users/scott/.config/nix/secrets/dst-cluster-token.age".publicKeys = [sophrosyne accismus-yubikey];
}
