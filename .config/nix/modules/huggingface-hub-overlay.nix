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
      typer = super.typer.overridePythonAttrs (old: {
        doInstallCheck = false;
      });
      huggingface-hub = super.huggingface-hub.overridePythonAttrs (old: rec {
        version = "1.20.0";
        src = prev.fetchFromGitHub {
          owner = "huggingface";
          repo = "huggingface_hub";
          rev = "v${version}";
          hash = "sha256-aPOwQrmpiJdQpzH1+AD+gZysDO8FICEVCJ77mXN+Ebw=";
        };
      });
    };
  };
in {
  python313Packages = python.pkgs;
}
