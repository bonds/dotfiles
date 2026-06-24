final: prev: {
  python313Packages =
    prev.python313Packages
    // {
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
