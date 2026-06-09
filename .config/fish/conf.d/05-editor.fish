if command --query hx
    set -x EDITOR hx
else if command --query helix
    set -x EDITOR helix
else if command --query kak
    set -x EDITOR kak
else if command --query nvim
    set -x EDITOR nvim
else if command --query vim
    set -x EDITOR vim
else
    set -x EDITOR vi
end
