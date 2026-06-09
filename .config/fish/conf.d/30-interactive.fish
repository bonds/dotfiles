if status is-interactive
    if command --query starship
        set ssc "$HOME/.config/starship/$_os.toml"
        if locale 2>&1 | grep -q UTF-8; and test -e "$ssc"
            set -x STARSHIP_CONFIG $ssc
        else
            set -x STARSHIP_CONFIG ~/.config/starship/plain.toml
        end
        starship init fish | source
    end
    if command --query atuin
        atuin init fish | source
    end
    if test -n "$SSH_CONNECTION" && not set --query TMUX && command --query tmux
        exec tmux new -A -s remote
    end
    set fzf_directory_opts --bind "ctrl-o:execute($EDITOR {} &> /dev/tty)"
    set fzf_fd_opts --hidden --exclude=.git
end
