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
export TERM=tmux-256color
export SPICETIFY_INSTALL="/home/rbudiharso/.local/bin/spicetify-cli"
export PATH="$SPICETIFY_INSTALL:$PATH"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"

# Start configuration added by Zim install {{{
#
# User configuration sourced by all invocations of the shell
#

# Define Zim location
: ${ZIM_HOME=${ZDOTDIR:-${HOME}}/.zim}
# }}} End configuration added by Zim install
