export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CONFIG_HOME="${HOME}/.config"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# cargo
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
