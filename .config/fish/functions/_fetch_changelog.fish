function _fetch_changelog -a url pkg_name pkg_desc
    if test -n "$pkg_desc" -a "$pkg_desc" != "null"
        echo "$pkg_name — $pkg_desc"
    end

    function __print_lines -a pkg_name
        set -l buf
        while read -l line
            set line (string trim -- "$line")
            if test -n "$line"
                set -a buf "$line"
            end
        end
        if test (count $buf) -eq 0
            return
        end

        if command --query ollama
            set -l text (printf '%s\n' $buf | head -c 10000)
            set -l summary (printf '%s' "Summarize in 1 line: what changed in $pkg_name. Be brief.

$text" | env OLLAMA_HOST=192.168.4.43:11434 timeout 20 ollama run gemma3:270m 2>/dev/null | string collect)
            if test -n "$summary"
                set -l clean (echo "$summary" | string replace -ra '\e\[[0-9;]*[a-zA-Z]' '' | string trim)
                if test -n "$clean"
                    echo "$clean"
                    return
                end
            end
        end

        for i in (seq 1 (math "min(25, "(count $buf)")"))
            echo $buf[$i]
        end
        if test (count $buf) -gt 25
            echo "  ... (truncated)"
        end
    end

    # Case 1: GitHub blob URLs → raw content (CHANGELOG.md, RelNotes, etc.)
    set -l m (string match -r '^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)' $url)
    if test (count $m) -ge 5
        set -l raw_url "https://raw.githubusercontent.com/$m[2]/$m[3]/$m[4]/$m[5]"
        command curl -sL --max-time 8 "$raw_url" 2>/dev/null | head -c 50000 | __print_lines $pkg_name
        return
    end

    # Case 2: GitHub releases URLs → use gh release view
    set -l m2 (string match -r '^https://github\.com/([^/]+)/([^/]+)/releases/tag/(.+)' $url)
    if test (count $m2) -ge 4
        if command --query gh
            set -l release_notes (command gh release view $m2[4] --repo "$m2[2]/$m2[3]" --json body --jq '.body' 2>/dev/null)
            if test -n "$release_notes"
                echo "$release_notes" | __print_lines $pkg_name
                return
            end
        end
    end

    # Case 3: Other URLs → fetch and attempt text extraction
    set -l content (command curl -sL --max-time 8 "$url" 2>/dev/null)
    if test -z "$content"
        return
    end

    # Try lynx for HTML rendering, fall back to basic tag stripping
    if command --query lynx
        echo "$content" | command lynx -stdin -dump -nolist 2>/dev/null | head -c 40000 | __print_lines $pkg_name
    else if command --query w3m
        echo "$content" | command w3m -dump -T text/html 2>/dev/null | head -c 40000 | __print_lines $pkg_name
    else if command --query python3
        echo "$content" | python3 -sc '
import sys, re
from html.parser import HTMLParser
data = sys.stdin.read(80000)
if not data.strip(): sys.exit(0)
if re.search(r"(?i)<(?:html|!doctype)\b", data[:500]):
    class P(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.text = []
            self.skip = False
        def handle_starttag(self, tag, attrs):
            if tag in ("script","style","nav","header","footer","nav"):
                self.skip = True
            if tag in ("br","p","li","tr","h1","h2","h3","h4","dd","dt"):
                self.text.append("\n")
        def handle_endtag(self, tag):
            if tag in ("script","style","nav","header","footer","nav"):
                self.skip = False
            if tag in ("p","li","tr","h1","h2","h3","h4","dd","dt"):
                self.text.append("\n")
        def handle_data(self, d):
            if not self.skip:
                self.text.append(d)
    parser = P()
    parser.feed(data)
    data = "".join(parser.text)
lines = [l.strip() for l in data.split("\n")]
lines = [l for l in lines if l]
if lines:
    print("\n".join(lines))
' 2>/dev/null | __print_lines $pkg_name
    else
        echo "$content" | head -c 30000 | string trim | string match -rv '^\s*<[^>]*>\s*$' | string replace -ra '<[^>]+>' '' | string trim | string match -rv '^$' | __print_lines $pkg_name
    end
end
