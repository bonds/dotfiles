{lib, ...}: {
  programs.fish.enable = lib.mkDefault true;
  programs.fish.interactiveShellInit = ''
    function fish_command_not_found
      set -l cmd $argv[1]
      set -l attrs (nix-locate --minimal --no-group --type x --type s --whole-name --at-root /bin/$cmd 2>/dev/null)
      set -l len (count $attrs)
      if test $len -eq 0
        __fish_default_command_not_found_handler $argv
        return 127
      end
      set -l green (set_color green)
      set -l cyan (set_color cyan)
      set -l yellow (set_color yellow)
      set -l cmd_color (set_color brwhite)
      set -l reset (set_color normal)
      if test $len -eq 1
        printf >&2 \
          '%sThe program %s%s%s is not installed, but is available in nixpkgs.%s\n\n' \
          "$yellow" "$cmd_color" "$cmd" "$yellow" "$reset"
        printf >&2 '  %sPackage:%s  nixpkgs#%s\n\n' "$green" "$reset" "$attrs[1]"
        printf >&2 '  %sInstall:%s   nix profile install nixpkgs#"%s"\n' "$cyan" "$reset" "$attrs[1]"
        printf >&2 '  %sTry once:%s  nix shell nixpkgs#"%s" -c %s\n' "$cyan" "$reset" "$attrs[1]" "$cmd"
      else
        printf >&2 \
          '%sThe program %s%s%s is not installed, but is available in nixpkgs.%s\n\n' \
          "$yellow" "$cmd_color" "$cmd" "$yellow" "$reset"
        printf >&2 '  %sPackages:%s\n' "$green" "$reset"
        set -l max 10
        set -l shown 0
        for attr in $attrs
          if test $shown -ge $max
            break
          end
          printf >&2 '    nixpkgs#%s\n' "$attr"
          set shown (math $shown + 1)
        end
        if test $len -gt $max
          printf >&2 '    …and %s more\n' (math $len - $max)
        end
        printf >&2 '\n'
        printf >&2 '  %sInstall:%s   nix profile install nixpkgs#"<package>"\n' "$cyan" "$reset"
        printf >&2 '  %sTry once:%s  nix shell nixpkgs#"<package>" -c %s\n' "$cyan" "$reset" "$cmd"
      end
      return 127
    end
  '';
}
