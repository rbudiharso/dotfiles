export SHELL=/bin/zsh
export XDG_CONFIG_HOME="$HOME/.config"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export ZSH_CACHE_DIR="$ZDOTDIR/cache"
export HISTFILE="$ZDOTDIR/.zhistory"
export HISTSIZE=10000
export SAVEHIST=10000
export PATH=$HOME/.local/bin:$HOME/.platformio/penv/bin:$PATH
export EDITOR="nvim"
export VISUAL="nvim"
export TERM=xterm-256color
export PATH="$HOME/.asdf/shims:$PATH"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH="$HOME/.kubescape/bin:$PATH"
export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"
export ZSH_THEME="dracula-pro"
# export FZF_BASE=/usr/share/doc/fzf

# Start configuration added by Zim install {{{
#
# User configuration sourced by all invocations of the shell
#

# Define Zim location
: ${ZIM_HOME=${ZDOTDIR:-${HOME}}/.zim}
# }}} End configuration added by Zim install
