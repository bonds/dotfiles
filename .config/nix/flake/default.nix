{
  systems = ["aarch64-darwin" "x86_64-linux"];
  imports = [
    ./formatter.nix
    ./checks.nix
    ./devShells.nix
    ./packages.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
