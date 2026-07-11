[
  (import ../modules/ollama-overlay.nix)
  (import ../modules/osxphotos-overlay.nix)
  (import ../modules/zen-browser-overlay.nix)
  (import ../modules/opencode-overlay.nix)
  (import ../modules/safari-web-app-overlay.nix)
  (import ../modules/daisydisk-overlay/default.nix)
  # Replace packages that fail to build due to cctools ld64 crash on arm64
  # with their last known working builds from the store.
  (final: prev: let
    # Helper: create a derivation that wraps an existing store path
    useCached = name: path:
      prev.runCommand name {} ''
        if [ -L "$out" ]; then rm "$out"; fi
        ln -s ${builtins.storePath path} "$out"
      '';
  in {
    caffeine = useCached "caffeine-1.1.4" "/nix/store/agv65m9wf9z1bdxsj37kjss2ajlsf6aw-caffeine-1.1.4";
    whisper-cpp = useCached "whisper-cpp-1.8.7" "/nix/store/mh2kal7l6hflvwxqp0bpk6609vh8n2vk-whisper-cpp-1.8.7";
    starship = useCached "starship-1.26.0" "/nix/store/bdxd2la52jv7gh4sy46na0clc0jafrqv-starship-1.26.0";
    mpv = useCached "mpv-0.41.0" "/nix/store/03zfgn8fi73mrnr848y69vhb6nn04zwp-mpv-0.41.0";
    lima = useCached "lima-2.1.4" "/nix/store/qjwdmr860nm9d3pfk85plgpj21rcmwqg-lima-2.1.4";
    lima-full = useCached "lima-full-2.1.4" "/nix/store/6xz75wd0nqjjwssyvrlx4jb7ayv7ayd7-lima-full-2.1.4";
  })
]
