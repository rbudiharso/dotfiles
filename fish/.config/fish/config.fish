# aliases
alias cl=clear
alias vim=nvim
alias code=vscodium
alias kctx="kubie ctx"
alias kns="kubie ns"
if ! command -v batcat &> /dev/null
    alias cat=bat
else
    alias cat=batcat
end
alias ecrlogin="aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-1.amazonaws.com"

set -g theme_display_date no

source $HOME/.asdf/asdf.fish

# set CAPSLOCK as Escape
setxkbmap -option caps:escape

starship init fish | source
neofetch --config ~/.dotfiles/neofetch.conf
