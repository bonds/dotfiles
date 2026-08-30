_: {
  # IRC client, connected to the soju bouncer on sophrosyne over the tailnet.
  #
  # soju acts as an IRCv3 bouncer: it holds the upstream connection to
  # Libera.Chat permanently, buffers messages while Halloy is closed, and
  # replays them on reconnect. Multiple devices can multiplex through it.
  #
  # The bouncer password is NOT stored in this config — it lives in the
  # agenix secret `soju-password` (encrypted blob at secrets/soju-password.age),
  # decrypted to /run/agenix/soju-password (macOS agenix mount) which Halloy
  # reads via password_file.
  programs.halloy = {
    enable = true;
    settings = {
      servers.bouncer = {
        nickname = "scott";
        # soju bouncer-networks: scoping the connection to a single network
        # (scott/libera) makes plain /join and channel commands work directly
        # instead of needing BouncerServ network-scoping gymnastics.
        username = "scott/libera";
        realname = "Scott";
        server = "sophrosyne";
        port = 6667;
        use_tls = false; # tailnet (WireGuard) already encrypts the wire
        # Read the soju password from the agenix-decrypted file (not this TOML).
        # macOS agenix mounts secrets under /run/agenix (ramdisk-backed).
        password_file = "/run/agenix/soju-password";
      };
    };
  };
}
