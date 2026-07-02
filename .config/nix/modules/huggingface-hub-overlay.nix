# TEMPORARY: bump huggingface-hub and its dependencies.
#
# Remove once nixpkgs-stable provides:
#   - huggingface-hub >= 1.21.0
#   - click     >= 8.4.0   (nixpkgs-stable has 8.3.1)
#   - hf-xet    >= 1.5.1   (nixpkgs-stable has 1.4.3)
#
# Source fetched by commit SHA (dereferenced tag) for stability.
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
      typer = super.typer.overrideAttrs (old: {
        doInstallCheck = false;
        installCheckPhase = "";
      });
      huggingface-hub = super.huggingface-hub.overridePythonAttrs (old: rec {
        version = "1.21.0";
        src = prev.fetchFromGitHub {
          owner = "huggingface";
          repo = "huggingface_hub";
          rev = "aea9b9de1284f54862df99820f963d6030803860";
          hash = "sha256-xjImbt+oeVk3XpqmR1CVllBurNgYRwcYN69NdFmj13I=";
        };
      });
    };
  };
in {
  python313Packages = python.pkgs;
}
