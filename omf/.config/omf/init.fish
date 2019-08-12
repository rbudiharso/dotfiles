# set CAPSLOCK as Escape
setxkbmap -option caps:escape

set -U EDITOR 'nvim'
set -U fish_user_paths $HOME/.local/bin $HOME/Bin $HOME/.asdf/shims /usr/local/bin /usr/sbin /usr/bin $fish_user_paths

eval (starship init fish)
