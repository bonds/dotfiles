{
  systems = ["aarch64-darwin" "x86_64-linux"];
  imports = [
    ./formatter.nix
    ./checks.nix
    ./pre-commit.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
