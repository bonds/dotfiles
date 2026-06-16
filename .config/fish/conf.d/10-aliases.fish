alias chatgpt "set -x OPENAI_API_KEY (security find-generic-password -w -a $LOGNAME -s \"openai api key\"); and command chatgpt"
alias crawl "crawl -rc ~/.config/crawl/init.txt"
alias day "date '+%Y%m%d'"
alias ghci "ghci -ghci-script ~/.config/ghc/ghci.rio.conf -ghci-script ~/.config/ghc/ghci.conf"
alias height "tput lines"
alias idris "rlwrap --history-filename ~/.local/idris.history idris2 --package contrib"

alias reset_camera "sudo usb-reset 0fd9:008a"
alias reset_usb "sudo rmmod xhci_pci; sudo modprobe xhci_pci"
alias reset_mouse "sudo rmmod hid_magicmouse; sudo modprobe hid_magicmouse"
alias sshc "ssh -o RequestTTY=no -o RemoteCommand=none"
function ssh-clean --description "Kill lingering SSH ControlMaster processes and clean sockets"
    for sock in ~/.local/ssh/*.control
        test -e "$sock"; or continue
        set -l pids (lsof -t "$sock" 2>/dev/null)
        test -n "$pids"; and kill $pids 2>/dev/null
        rm -f "$sock"
    end
end
alias ssht "ssh -o RemoteCommand=none"
alias width "tput cols"
alias xclip "command xclip -selection c"
function ssh --description "SSH with custom config"
    command ssh -F ~/.config/ssh/config $argv
end
complete -c ssh -w (command -s ssh)

if test "$_os" = darwin
    alias mtr "sudo mtr"
    alias battery "pmset -g batt"
end
