[
  (import ../modules/ollama-overlay.nix)
  (import ../modules/osxphotos-overlay.nix)
  (import ../modules/zen-browser-overlay.nix)
  (import ../modules/opencode-overlay.nix)
  (import ../modules/safari-web-app-overlay.nix)
  (import ../modules/daisydisk-overlay/default.nix)
  # Replace packages that fail to build due to cctools ld64 crash on arm64
  # with cached builds from the store (avoiding builtins.storePath which is
  # forbidden in pure eval mode — use literal store paths in runCommand).
  (final: prev: {
    caffeine = prev.runCommand "caffeine-1.1.4" {} ''
      ln -s /nix/store/agv65m9wf9z1bdxsj37kjss2ajlsf6aw-caffeine-1.1.4 "$out"
    '';
    whisper-cpp = prev.runCommand "whisper-cpp-1.8.7" {} ''
      ln -s /nix/store/mh2kal7l6hflvwxqp0bpk6609vh8n2vk-whisper-cpp-1.8.7 "$out"
    '';
    starship = prev.runCommand "starship-1.26.0" {} ''
      ln -s /nix/store/bdxd2la52jv7gh4sy46na0clc0jafrqv-starship-1.26.0 "$out"
    '';
    mpv = prev.runCommand "mpv-0.41.0" {} ''
      ln -s /nix/store/03zfgn8fi73mrnr848y69vhb6nn04zwp-mpv-0.41.0 "$out"
    '';
    lima = prev.runCommand "lima-2.1.4" {} ''
      ln -s /nix/store/qjwdmr860nm9d3pfk85plgpj21rcmwqg-lima-2.1.4 "$out"
    '';
    lima-full = prev.runCommand "lima-full-2.1.4" {} ''
      ln -s /nix/store/6xz75wd0nqjjwssyvrlx4jb7ayv7ayd7-lima-full-2.1.4 "$out"
    '';
  })
]
