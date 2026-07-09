{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    alejandra # nix code formatter
    ast-grep # AST-aware code search and rewrite (for oh-my-openagent)
    (pkgs.writeShellScriptBin "sg" "exec ${pkgs.ast-grep}/bin/ast-grep \"$@\"") # sg alias for oh-my-openagent
    atuin # synced shell history database
    cabal-install # Haskell build tool and package manager
    gh # GitHub CLI
    ghc # Glasgow Haskell Compiler
    helix # modal text editor (vim-like)
    idris2 # functional language with dependent types
    ripgrep # fast grep for searching code
    rlwrap # readline wrapper for interactive programs
    starship # customizable cross-shell prompt
    tokei # fast code line and language counter
  ];
}
