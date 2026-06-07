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

            # Fallback: derive changelog from GitHub homepage
            if test -z "$changelog_url" -o "$changelog_url" = "null"
                set -l homepage (command nix eval --raw "nixpkgs#$pkg.meta.homepage" 2>/dev/null)
                set -l gh_match (string match -r '^https://github\.com/([^/]+)/([^/]+)/?$' "$homepage")
                if test (count $gh_match) -ge 3
                    set -l gh_url "https://github.com/$gh_match[2]/$gh_match[3]"
                    # Try specific release tag first (most useful)
                    for tag in "v$new_ver" "$new_ver" "$pkg-$new_ver"
                        set changelog_url "$gh_url/releases/tag/$tag"
                        if command curl -sIL --max-time 4 "$changelog_url" 2>/dev/null | string match -q -r 'HTTP/[0-9.]+ 2[0-9][0-9]'
                            break
                        end
                        set changelog_url ""
                    end
                    # Fallback: try changelog files
                    if test -z "$changelog_url"
                        for path in CHANGELOG.md CHANGES.md RELEASE_NOTES.md NEWS.md ChangeLog CHANGELOG NEWS
                            set changelog_url "$gh_url/blob/main/$path"
                            if command curl -sIL --max-time 4 "$changelog_url" 2>/dev/null | string match -q -r 'HTTP/[0-9.]+ 2[0-9][0-9]'
                                break
                            end
                            set changelog_url ""
                        end
                    end
                end
            end

            # Fallback: guess GitHub URL from package name for well-known projects
            if test -z "$changelog_url"
                # Common GitHub naming conventions: {pkg}/{pkg}, {pkg}-users/{pkg}, {pkg}-engine/{pkg}
                for guess in "$pkg/$pkg" "$pkg-users/$pkg" "$pkg-engine/$pkg"
                    set -l gh_url "https://github.com/$guess"
                    # Try specific release tag first (most useful)
                    set changelog_url ""
                    for tag in "v$new_ver" "$new_ver" "$pkg-$new_ver"
                        set changelog_url "$gh_url/releases/tag/$tag"
                        if command curl -sIL --max-time 4 "$changelog_url" 2>/dev/null | string match -q -r 'HTTP/[0-9.]+ 2[0-9][0-9]'
                            break
                        end
                        set changelog_url ""
                    end
                    if test -z "$changelog_url"
                        # Fallback: try changelog files
                        for path in CHANGELOG.md CHANGES.md RELEASE_NOTES.md NEWS.md ChangeLog CHANGELOG NEWS
                            set changelog_url "$gh_url/blob/main/$path"
                            if command curl -sIL --max-time 4 "$changelog_url" 2>/dev/null | string match -q -r 'HTTP/[0-9.]+ 2[0-9][0-9]'
                                break
                            end
                            set changelog_url ""
                        end
                    end
                    if test -n "$changelog_url"
                        break
                    end
                end
            end

            if test -n "$changelog_url" -a "$changelog_url" != "null"
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
