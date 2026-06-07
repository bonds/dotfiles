{
  description = "what-changed: show nix system package changelogs using LLM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    mkCheck = pkgs: name: buildInputs: script:
      pkgs.runCommand name {inherit buildInputs;} ''
        ${script}
        touch $out
      '';
  in {
    packages = forAllSystems (system: {
      default = (pkgsFor system).callPackage ./default.nix {};
    });

    overlays.default = final: prev: {
      what-changed = final.callPackage ./default.nix {};
    };

    nixosModules.default = import ./module.nix;
    darwinModules.default = import ./module.nix;

    checks = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
      format = mkCheck pkgs "what-changed-format" [pkgs.alejandra] ''
        cd ${self}
        alejandra -c . || (echo "Run: alejandra ." && exit 1)
      '';
      python = mkCheck pkgs "what-changed-python" (with pkgs; [python3]) ''
                ${pkgs.python3}/bin/python3 -c "
        import ast, sys
        import glob
        for f in glob.glob('${self}/what_changed/*.py'):
            with open(f) as fh:
                ast.parse(fh.read())
            print(f'Syntax OK: {f}')
        " 2>&1
      '';
      pytest = let
        py = pkgs.python3.withPackages (ps: [ps.pytest ps.tomli-w ps.httpx]);
      in
        mkCheck pkgs "what-changed-tests" [py] ''
          export HOME=$(mktemp -d)
          export PYTHONPATH=${self}:$PYTHONPATH
          ${py}/bin/pytest ${self}/tests -v --tb=short
        '';
    });

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
