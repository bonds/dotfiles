function _fetch_changelog -a url pkg_name pkg_desc
    if test -n "$pkg_desc" -a "$pkg_desc" != "null"
        set_color brblack
        if command --query python3
            echo "$pkg_desc" | python3 -sc "
import textwrap, shutil, sys
w = shutil.get_terminal_size().columns
desc = sys.stdin.read().strip()
if desc:
    print(textwrap.fill(desc, w, initial_indent='  ↳ ', subsequent_indent='    '))
" 2>/dev/null
        else
            echo "  ↳ $pkg_desc"
        end
        set_color normal
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
            set -l text (printf '%s\n' $buf | head -c 5000)
            if test (string length -- "$text") -lt 100
                set_color brblack
                echo "  (no release notes available)"
                set_color normal
                return
            end
            set -l summary (printf '%s' "Below is the changelog. Summarize ONLY the specific changes. Do NOT describe what $pkg_name is or does. Write 3-5 specific bullet points. Include PR numbers, commit hashes, or version bumps if present. No generic filler. Respond in English.

$text" | timeout 20 ollama run gemma3:270m 2>/dev/null | string collect)
            if test -n "$summary"
                # Strip ANSI codes and split into lines
                set -l lines (echo "$summary" | string replace -ra '\e\[[0-9;]*[a-zA-Z]' '' | string trim | string split \n)
                set -l bullets
                set -l non_bullets
                set -l in_bullets 0
                for line in $lines
                    set line (string trim -- "$line")
                    if test -z "$line"
                        continue
                    end
                    if string match -q -r '^[\*\-\d]' "$line"
                        set in_bullets 1
                        # Strip leading bullet markers and bold
                        set line (string replace -ra '^\s*[\*\-\d]+\.?\s*' '' "$line" | string replace -ra '\*\*' '' | string trim)
                        if test -n "$line"
                            set -a bullets "$line"
                        end
                    else if test $in_bullets -eq 1 -a (count $bullets) -gt 0
                        # Continuation of last bullet (terminal word-wrap)
                        set line (echo "$line" | string replace -ra '\*\*' '' | string trim)
                        if test -n "$line"
                            set bullets[-1] "$bullets[-1] $line"
                        end
                    else
                        # Preamble (before first bullet) — save in case no bullets found
                        set -a non_bullets "$line"
                    end
                end
                if test (count $bullets) -gt 0
                    set -l max_bullets 5
                    set -l bcount (count $bullets)
                    for i in (seq 1 (math "min($max_bullets, $bcount)"))
                        set -l b (echo "$bullets[$i]" | string replace -ra '(\w+)\s+\1' '$1' | string trim)
                        set_color brblack
                        if command --query python3
                            echo "$b" | python3 -sc "
import textwrap, shutil, sys
w = shutil.get_terminal_size().columns
line = sys.stdin.read().strip()
if line:
    print(textwrap.fill(line, w, initial_indent='  • ', subsequent_indent='    '))
" 2>/dev/null
                        else
                            echo "  • $b"
                        end
                        set_color normal
                    end
                    if test $bcount -gt $max_bullets
                        set_color brblack
                        echo "  … and "(math "$bcount - $max_bullets")" more changes"
                        set_color normal
                    end
                    return
                end
                # No bullets found — dump as single line fallback
                if test (count $non_bullets) -gt 0
                    set_color brblack
                    set -l fb (string join ' ' $non_bullets)
                    if command --query python3
                        echo "$fb" | python3 -sc "
import textwrap, shutil, sys
w = shutil.get_terminal_size().columns
line = sys.stdin.read().strip()
if line:
    print(textwrap.fill(line, w, initial_indent='  ', subsequent_indent='    '))
" 2>/dev/null
                    else
                        echo "  $fb"
                    end
                    set_color normal
                    return
                end
            end
        end

        set_color brblack
        for i in (seq 1 (math "min(25, "(count $buf)")"))
            set -l l (string trim -- "$buf[$i]")
            if command --query python3
                echo "$l" | python3 -sc "
import textwrap, shutil, sys
w = shutil.get_terminal_size().columns
line = sys.stdin.read().strip()
if line:
    print(textwrap.fill(line, w, initial_indent='  ', subsequent_indent='    '))
" 2>/dev/null
            else
                echo "  $l"
            end
        end
        if test (count $buf) -gt 25
            echo "  ... (truncated)"
        end
        set_color normal
    end

    echo ""

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
        set -l owner $m2[2]
        set -l repo $m2[3]
        set -l tag $m2[4]
        if command --query gh
            set -l release_notes (command gh release view $tag --repo "$owner/$repo" --json body --jq '.body' 2>/dev/null)
            if test -n "$release_notes"
                echo "$release_notes" | __print_lines $pkg_name
                return
            end
        end
        # Fallback: try raw changelog files at the tagged commit
        for path in ChangeLog NEWS CHANGES.md CHANGELOG.md RELEASE_NOTES.md NEWS.md
            set -l raw_url "https://raw.githubusercontent.com/$owner/$repo/$tag/$path"
            if command curl -sL --max-time 4 "$raw_url" 2>/dev/null | head -c 1000 | string match -q -r '(?i)change|fix|version|release|bug'
                command curl -sL --max-time 8 "$raw_url" 2>/dev/null | head -c 50000 | __print_lines $pkg_name
                return
            end
        end
        return
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
