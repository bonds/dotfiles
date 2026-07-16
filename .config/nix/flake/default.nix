{
  systems = ["aarch64-darwin" "x86_64-linux"];
  imports = [
    ./formatter.nix
    ./checks.nix
    ./shells.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
