function killmovie
    for s in /tmp/mpv-left /tmp/mpv-mid /tmp/mpv-right
        test -S "$s" && echo '{ "command": ["quit"] }' | nc -U "$s" 2>/dev/null
    end
end
