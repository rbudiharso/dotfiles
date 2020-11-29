# set env variable in .zshenv
# uncoment if you want to profile zsh startup time
# dont forget to uncomment zprof at the bottom of this file
# zmodload zsh/zprof

setopt HIST_SAVE_NO_DUPS

source $HOME/.asdf/asdf.sh

if [[ ! -f ~/.zpm/zpm.zsh ]]; then
	git clone --recursive https://github.com/zpm-zsh/zpm ~/.zpm
fi
source ~/.zpm/zpm.zsh
zpm load oh-my-zsh/fzf,type:omz
zpm load oh-my-zsh/git,type:omz
zpm load oh-my-zsh/common-aliases,type:omz
zpm load oh-my-zsh/command-not-found,type:omz
zpm load oh-my-zsh/helm,type:omz
zpm load oh-my-zsh/kubectl,type:omz
zpm load oh-my-zsh/safe-paste,type:omz
zpm load oh-my-zsh/tmux,type:omz
zpm load oh-my-zsh/zsh_reload,type:omz
zpm load zsh-users/zsh-autosuggestions,source:zsh-autosuggestions.zsh,async
zpm load zsh-users/zsh-completions,source:zsh-completions.plugin.zsh,async
# https://getantibody.github.io/
# source <(antibody init)
# antibody bundle < ~/.dotfiles/antibody/plugins.txt

# additional files
source ~/.dotfiles/zsh/.config/zsh/aliases.zsh

# set CAPSLOCK as Escape
setxkbmap -option caps:escape

eval "$(starship init zsh)"
neofetch --config ~/.dotfiles/neofetch.conf

export TERM=screen-256color

# ssf() {
#   host=$(grep -e "^Host " ~/.ssh/config | awk '{print $2}' | fzf)
#   echo "SSH session started, connecting to" $host
#   ssh $host
# }

autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# uncomment this to profile zsh startup time
# zprof
