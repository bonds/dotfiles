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
          hash = "sha256-wA1gvo5xrY+iXRAcAUQ6ulDAn+GeC6CzVKQMGUR46m8=";
        };
      });
    };
}
