function _fetch_changelog -a url
    if not command --query python3
        echo "  (install python3 to see release notes)"
        return 1
    end

    # Case 1: GitHub blob URLs → raw content (CHANGELOG.md, RelNotes, etc.)
    set -l m (string match -r '^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)' $url)
    if test (count $m) -ge 5
        set -l raw_url "https://raw.githubusercontent.com/$m[2]/$m[3]/$m[4]/$m[5]"
        command curl -sL --max-time 8 "$raw_url" 2>/dev/null | python3 -sc '
import sys
data = sys.stdin.read(50000)
if not data.strip(): sys.exit(0)
lines = [l.strip() for l in data.split("\n") if l.strip()]
if lines:
    print("\n".join(lines[:25]))
    if len(lines) > 25: print("  ... (truncated)")
' 2>/dev/null
        return
    end

    # Case 2: GitHub releases URLs → use gh release view
    set -l m2 (string match -r '^https://github\.com/([^/]+)/([^/]+)/releases/tag/(.+)' $url)
    if test (count $m2) -ge 4
        if command --query gh
            set -l release_notes (command gh release view $m2[4] --repo "$m2[2]/$m2[3]" --json body --jq '.body' 2>/dev/null)
            if test -n "$release_notes"
                echo "$release_notes" | python3 -sc '
import sys
data = sys.stdin.read()
lines = [l.strip() for l in data.split("\n") if l.strip()]
if lines:
    print("\n".join(lines[:25]))
    if len(lines) > 25: print("  ... (truncated)")
' 2>/dev/null
                return
            end
        end
    end

    # Case 3: Other URLs → fetch and extract text
    command curl -sL --max-time 8 "$url" 2>/dev/null | python3 -sc '
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
    print("\n".join(lines[:25]))
    if len(lines) > 25:
        print("  ... (truncated)")
' 2>/dev/null
end
