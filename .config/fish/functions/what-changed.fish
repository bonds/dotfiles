function what-changed -d "Show release notes for packages updated between two system closures"
    set -l old_system $argv[1]
    set -l new_system $argv[2]

    if test -z "$old_system" -o -z "$new_system"
        echo "Usage: what-changed <old-store-path> <new-store-path>" >&2
        echo "Example:" >&2
        echo "  what-changed /nix/store/xxx-darwin-system /nix/store/yyy-darwin-system" >&2
        echo "" >&2
        echo "Automatically called by 'nr' when the system closure changes." >&2
        return 1
    end

    echo ""
    set_color cyan --bold
    echo "━━━ Package Changes ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    set_color normal
    echo ""

    set -l diff_output (command nix store diff-closures $old_system $new_system 2>&1)
    if test $status -ne 0
        set_color red
        echo "Error: $diff_output" >&2
        set_color normal
        return 1
    end

    set -l found 0
    for line in $diff_output
        set -l parsed (string match -r '^([a-zA-Z0-9._-]+): (.+) → (.+)' $line)
        if test (count $parsed) -ge 4
            set -l pkg $parsed[2]
            set -l old_ver (string trim $parsed[3])
            set -l new_ver (string trim (string replace -r ',.*$' '' $parsed[4]))

            if test "$old_ver" = "∅" -o "$new_ver" = "∅"
                continue
            end

            set found 1
            set_color --bold
            echo -n "  $pkg  "
            set_color normal
            set_color brblack
            echo -n "$old_ver"
            set_color green
            echo -n " → "
            set_color normal
            set_color brblack
            echo "$new_ver"
            set_color normal

            set -l changelog_url (command nix eval --raw "nixpkgs#$pkg.meta.changelog" 2>/dev/null)
            set -l pkg_desc (command nix eval --raw "nixpkgs#$pkg.meta.description" 2>/dev/null)
            if test -n "$changelog_url" -a "$changelog_url" != "null"
                set_color brblack
                echo "  ────────────────────────────────────────────"
                set_color normal
                _fetch_changelog "$changelog_url" "$pkg" "$pkg_desc"
                echo ""
            else if test -n "$pkg_desc" -a "$pkg_desc" != "null"
                set_color yellow
                echo "  $pkg — $pkg_desc"
                set_color normal
                echo ""
            else
                echo ""
            end
        end
    end

    if test "$found" -eq 0
        echo "  (no version changes detected)"
    end
    echo ""
end
