# TEMPORARY: bump huggingface-hub to 1.21.0 and its dependencies.
#
# Remove this file (and its `nixpkgs.overlays` reference in flake.nix) once
# nixpkgs-stable provides:
#   - huggingface-hub >= 1.21.0
#   - click     >= 8.4.0   (nixpkgs-stable has 8.3.1)
#   - hf-xet    >= 1.5.1   (nixpkgs-stable has 1.4.3)
#
# Also remove the typer installCheck disable once typer supports click 8.4.x.
final: prev: let
  python = prev.python313.override {
    packageOverrides = self: super: {
      click = super.click.overridePythonAttrs (old: rec {
        version = "8.4.1";
        src = prev.fetchPypi {
          pname = "click";
          inherit version;
          hash = "sha256-kYtWM+3fa0HDLU9FS/DegQBlx04/fb+O5UUvi+iNPpY=";
        };
      });
      hf-xet = super.hf-xet.overridePythonAttrs (old: rec {
        version = "1.5.1";
        src = prev.fetchFromGitHub {
          owner = "huggingface";
          repo = "xet-core";
          tag = "v${version}";
          hash = "sha256-TqSErydAOaHzCN7qglO/aqMF8BWYXvEv09adhxTwny0=";
        };
        sourceRoot = "${src.name}/hf_xet";
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          pname = "hf-xet";
          inherit version src sourceRoot;
          hash = "sha256-pwHUIkx+Dk8fGOVxRJKLswLjQB+sKzpyOOeqV6+Xyxo=";
        };
      });
      # TEMPORARY: typer's installCheck fails with click 8.4.1 error message format.
      # Remove once typer upstream supports click >= 8.4.0.
      typer = super.typer.overrideAttrs (old: {
        doInstallCheck = false;
        installCheckPhase = "";
      });
      huggingface-hub = super.huggingface-hub.overridePythonAttrs (old: rec {
        version = "1.21.0";
        src = prev.fetchFromGitHub {
          owner = "huggingface";
          repo = "huggingface_hub";
          rev = "v${version}";
          hash = "sha256-2zdlY40zatah4Ef/CBmt3GnBC2DrO3X3EZRMYEkkQEg=";
        };
      });
    };
  };
in {
  python313Packages = python.pkgs;
}
