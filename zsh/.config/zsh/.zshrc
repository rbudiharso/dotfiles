XDG_CONFIG_HOME="${HOME}/.config"
XDG_DATA_HOME="${HOME}/.local/share"
ZINIT_HOME="${XDG_DATA_HOME}/zinit/zinit.git"
ZDOTDIR="$XDG_CONFIG_HOME/zsh"
ZSH_CACHE_DIR="$XDG_DATA_HOME/zsh/cache"
DIRENV_LOG_FORMAT=$'\033[2mdirenv: %s\033[0m'
PATH=$HOME/.local/bin:$PATH
# PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
PATH="$HOME/Library/Python/3.9/bin:$PATH"
EDITOR="nvim"
VISUAL="nvim"

if command -v devbox >/dev/null 2>&1
then
  eval "$(devbox global shellenv --init-hook)"
fi

# auto install zinit
if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# use zinit
source "${ZINIT_HOME}/zinit.zsh"

# plugins, use turbo with "lucid"
zinit lucid wait for zsh-users/zsh-syntax-highlighting
zinit lucid wait for zsh-users/zsh-completions
zinit lucid wait for zsh-users/zsh-autosuggestions
zinit lucid wait for Aloxaf/fzf-tab

# snippet plugin
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
# zinit snippet OMZP::asdf

# load completions
autoload -Uz compinit && compinit
zinit cdreplay -q

# history
HISTSIZE=5000
HISTFILE="${XDG_DATA_HOME}/zsh/.zsh_history"
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# shell integration
eval "$(starship init zsh)"
eval "$(fzf --zsh)"
eval "$(direnv hook zsh)"
eval "$(atuin init zsh)"

# aliases
alias ls='ls --color'
alias ll='ls -lh --color'
alias la='ls -lah --color'
alias vim='nvim'
alias cl='clear'
alias awsp='export AWS_PROFILE=$(sed -n "s/^\[profile \(.*\)\]/\1/gp" ~/.aws/config | fzf)'
alias ecrlogin='aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-1.amazonaws.com'

# select kubernetes context
kctx() {
  if [ $# -eq 0 ]; then
    kubectl config use-context $(k config get-contexts --no-headers|awk '{print $3}'|fzf)
  else
    kubectl config use-context $@
  fi
}

# change kubernetes namespace
kns() {
  if [ $# -eq 0 ]; then
    kubectl config set-context --current --namespace="$(kubectl get ns --no-headers|grep -v \"Terminating\"|awk '{print $1}'|fzf)"
  else
    kubectl config set-context --current --namespace="$@"
  fi
}

# fastfetch
