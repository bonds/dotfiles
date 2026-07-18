{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs;
    [
      alejandra # nix code formatter
      ast-grep # AST-aware code search and rewrite (for oh-my-openagent)
      (pkgs.writeShellScriptBin "ast" "exec ${pkgs.ast-grep}/bin/ast-grep \"$@\"") # ast alias for oh-my-openagent
      atuin # synced shell history database
      gh # GitHub CLI
      helix # modal text editor (vim-like)
      nil # Nix language server
      ripgrep # fast grep for searching code
      rlwrap # readline wrapper for interactive programs
      starship # customizable cross-shell prompt
      tokei # fast code line and language counter
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      cabal-install # Haskell build tool and package manager
      ghc # Glasgow Haskell Compiler
      idris2 # functional language with dependent types
    ];
}
