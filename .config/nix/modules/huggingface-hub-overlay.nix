final: prev: {
  python313Packages =
    prev.python313Packages
    // {
      click = prev.python313Packages.click.overridePythonAttrs (old: rec {
        version = "8.4.1";
        src = prev.fetchPypi {
          pname = "click";
          inherit version;
          hash = "sha256-1kafz8xdlr7gywg414xwn6smpwmi2iii3z2sap7ilkigigkpznvv";
        };
      });
      hf-xet = prev.python313Packages.hf-xet.overridePythonAttrs (old: rec {
        version = "1.5.1";
        src = prev.fetchFromGitHub {
          owner = "huggingface";
          repo = "xet-core";
          rev = "v${version}";
          hash = "sha256-0bczy0a8g7fnscpz2plq2pq0b8vapx9q5sny13rs2fa04ypq992f";
        };
      });
      huggingface-hub = prev.python313Packages.huggingface-hub.overridePythonAttrs (old: rec {
        version = "1.20.0";
        src = prev.fetchFromGitHub {
          owner = "huggingface";
          repo = "huggingface_hub";
          rev = "v${version}";
          hash = "sha256-aPOwQrmpiJdQpzH1+AD+gZysDO8FICEVCJ77mXN+Ebw=";
        };
      });
    };
}
