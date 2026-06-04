{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    alejandra # nix code formatter
    atuin # synced shell history database
    cabal-install # Haskell build tool and package manager
    gh # GitHub CLI
    ghc # Glasgow Haskell Compiler
    helix # modal text editor (vim-like)
    idris2 # functional language with dependent types
    nh # nix helper for rebuilds and garbage collection
    ripgrep # fast grep for searching code
    rlwrap # readline wrapper for interactive programs
    starship # customizable cross-shell prompt
    tokei # fast code line and language counter
  ];
}
