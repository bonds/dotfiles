function movie
    if test (count $argv) -eq 0
        echo "usage: movie <file>" >&2
        return 1
    end
    set file "$argv[1]"
    if not test -f "$file"
        echo "movie: file not found: $file" >&2
        return 1
    end

    set dims (ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=p=0 "$file" 2>/dev/null)
    if test -n "$dims"
        set vw (string split ',' -- $dims)[1]
        set vh (string split ',' -- $dims)[2]
    else
        set vw 1920
        set vh 1080
    end

    set third (math "floor($vw / 3)")
    set leftover (math "$vw - (3 * $third)")
    set third_left (math "$third + $leftover")

    for s in /tmp/mpv-left /tmp/mpv-mid /tmp/mpv-right
        rm -f "$s"
    end

    mpv --fs --screen=1 --pause \
        --vf=crop=$third_left:$vh:0:0 \
        --input-ipc-server=/tmp/mpv-left "$file" &>/dev/null &

    mpv --fs --screen=0 --pause \
        --vf=crop=$third:$vh:$third_left:0 \
        --input-ipc-server=/tmp/mpv-mid "$file" &>/dev/null &

    mpv --fs --screen=2 --pause \
        --vf=crop=$third:$vh:(math "$third_left + $third"):0 \
        --input-ipc-server=/tmp/mpv-right "$file" &>/dev/null &

    sleep 1.5

    for s in /tmp/mpv-left /tmp/mpv-mid /tmp/mpv-right
        test -S "$s" && echo '{ "command": ["set_property", "pause", false] }' | nc -U "$s" 2>/dev/null
    end

    echo "Use killmovie to close all 3." >&2
end
