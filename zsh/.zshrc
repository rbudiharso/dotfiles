# uncoment if you want to profile zsh startup time
# dont forget to uncomment zprof at the bottom of this file
# zmodload zsh/zprof

# autoload -Uz compinit
# compinit -i

test -r $HOME/.asdf/asdf.sh && source $HOME/.asdf/asdf.sh
# test -r $HOME/.asdf/completions/asdf.bash && source $HOME/.asdf/completions/asdf.bash

export EDITOR='nvim'
export PATH=~/.local/bin:$PATH
export PATH=~/.asdf/shims:$PATH

# if [ $ASDF_DIR ]; then
#   export PATH=$(asdf where golang)/packages/bin:$PATH
# fi

export ZSH=$HOME/.cache/antibody/https-COLON--SLASH--SLASH-github.com-SLASH-robbyrussell-SLASH-oh-my-zsh
# source <(antibody init)
# antibody bundle < ~/.dotfiles/antibody/plugins.txt

# load antibody staticaly
source ~/.dotfiles/antibody/plugins.sh

# additional files
source ~/.dotfiles/zsh.d/aliases.zsh
# source ~/.dotfiles/zsh.d/helm-completion.zsh

# test -r "~/.dir_colors" && eval $(dircolors ~/.dir_colors)

# set CAPSLOCK as Escape
# setxkbmap -option caps:escape

eval "$(starship init zsh)"
neofetch --config ~/.dotfiles/neofetch.conf
# uncomment this to profile zsh startup time
# zprof
