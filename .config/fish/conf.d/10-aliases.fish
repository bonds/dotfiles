alias chatgpt "set -x OPENAI_API_KEY (security find-generic-password -w -a $LOGNAME -s \"openai api key\"); and command chatgpt"
alias crawl "crawl -rc ~/.config/crawl/init.txt"
alias day "date '+%Y%m%d'"
alias ghci "ghci -ghci-script ~/.config/ghc/ghci.rio.conf -ghci-script ~/.config/ghc/ghci.conf"
alias height "tput lines"
alias idris "rlwrap --history-filename ~/.local/idris.history idris2 --package contrib"

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
    alias reset_camera "sudo usb-reset 0fd9:008a"
    alias reset_usb "sudo rmmod xhci_pci; sudo modprobe xhci_pci"
    alias reset_mouse "sudo rmmod hid_magicmouse; sudo modprobe hid_magicmouse"
    alias mtr "sudo mtr"
    alias battery "pmset -g batt"
else
    alias reset_camera "doas usb-reset 0fd9:008a"
    alias reset_usb "doas rmmod xhci_pci; doas modprobe xhci_pci"
    alias reset_mouse "doas rmmod hid_magicmouse; doas modprobe hid_magicmouse"
    alias mtr "doas mtr"
end

alias config='git --git-dir=$HOME/.config/dotfiles/ --work-tree=$HOME'
alias noise='play -n synth pinknoise vol 0.5 bass +3 treble -6'

function newpost --description "Create a new dated Hugo blog post in ~/Documents/undated/repos/blog"
    set -l blogdir $HOME/Documents/undated/repos/blog
    set -l argc (count $argv)
    if test $argc -lt 1
        echo "usage: newpost <title>"
        return 1
    end
    if not test -d $blogdir
        echo "newpost: blog dir not found: $blogdir"
        return 1
    end
    # slugify: lowercase, collapse non-alphanumerics to hyphens, trim edges
    set -l title (string join " " $argv)
    set -l slug (echo $title | string lower | string replace -r -a "[^a-z0-9]+" "-" | string trim -l -r -c "-")
    if test -z "$slug"
        echo "newpost: could not derive a slug from the title"
        return 1
    end
    set -l fname (date "+%Y-%m-%d")-$slug.md
    set -l old $PWD
    cd $blogdir
    hugo new content/posts/$fname
    set -l st $status
    if test $st -eq 0
        $EDITOR content/posts/$fname
    end
    cd $old
    return $st
end
