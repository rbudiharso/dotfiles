export ZINIT_HOME="${XDG_DATA_HOME}/zinit/zinit.git"
export ZSH_CACHE_DIR="$XDG_DATA_HOME/zsh/cache"
export DIRENV_LOG_FORMAT=$'\033[2mdirenv: %s\033[0m'
export PATH=$HOME/.local/bin:$PATH
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export EDITOR="nvim"
export VISUAL="nvim"

# history
HISTSIZE=10000
HISTFILE="${XDG_DATA_HOME}/zsh/.zsh_history"
SAVEHIST=$HISTSIZE
HISTDUP=erase
mkdir -p "$(dirname "$HISTFILE")"
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

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

# snippet plugins
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl

# completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# shell integration
if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
eval "$(starship init zsh)"
eval "$(fzf --zsh)"
eval "$(atuin init zsh)"
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

# load completions
autoload -Uz compinit && compinit
zinit cdreplay -q

# cargo
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# libpq (macOS homebrew)
[[ -d /opt/homebrew/opt/libpq/bin ]] && export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# aliases
alias ls='ls --color'
alias ll='ls -lh --color'
alias la='ls -lah --color'
alias vim='nvim'
alias cl='clear'
alias awsp='export AWS_PROFILE=$(sed -n "s/^\[profile \(.*\)\]/\1/gp" ~/.aws/config | fzf)'
alias nbs="netbird status"
alias nbd="netbird down"
alias nbu="netbird up --management-url https://net.usetada.dev:33073"

# ECR login — set AWS_ECR_ACCOUNT and AWS_ECR_REGION in your environment or ~/.env.local
alias ecrlogin='aws ecr get-login-password --region "${AWS_ECR_REGION:-ap-southeast-1}" | docker login --username AWS --password-stdin "${AWS_ECR_ACCOUNT}.dkr.ecr.${AWS_ECR_REGION:-ap-southeast-1}.amazonaws.com"'

if command -v eza >/dev/null 2>&1; then
  alias ls="eza --icons=always"
  alias ll="eza -l --icons=always --group-directories-first"
  alias la="eza -la --icons=always --group-directories-first"
fi

# select kubernetes context
kctx() {
  if [ $# -eq 0 ]; then
    kubectl config use-context $(kubectl config get-contexts --no-headers|awk '{print $3}'|fzf)
  else
    kubectl config use-context $@
  fi
}

# change kubernetes namespace
kns() {
  if [ $# -eq 0 ]; then
    kubectl config set-context --current --namespace="$(kubectl get ns --no-headers|grep -v "Terminating"|awk '{print $1}'|fzf)"
  else
    kubectl config set-context --current --namespace="$@"
  fi
}

tmx() {
  # Don't nest tmux inside tmux
  if [ -n "$TMUX" ]; then
    echo "Already inside tmux"
    return 0
  fi

  # Optional session name, default: main
  local session="${1:-main}"

  # Start server quietly if needed
  tmux start-server >/dev/null 2>&1

  # If the named session exists, attach to it
  if tmux has-session -t "$session" 2>/dev/null; then
    exec tmux attach-session -t "$session"
    return
  fi

  # If any session exists, attach to the first one
  local first_session
  first_session="$(tmux list-sessions -F '#S' 2>/dev/null | head -n 1)"

  if [ -n "$first_session" ]; then
    exec tmux attach-session -t "$first_session"
    return
  fi

  # Otherwise create a new named session
  exec tmux new-session -s "$session"
}
