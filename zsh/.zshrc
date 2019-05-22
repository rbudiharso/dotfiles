# uncoment if you want to profile zsh startup time
# dont forget to uncomment zprof at the bottom of this file
# zmodload zsh/zprof
export EDITOR='nvim'

[ -f ~/.alias ] && source ~/.alias

if [ $ASDF_DIR ]; then
  export PATH=$(asdf where golang)/packages/bin:$PATH
fi

# workaround for tilix
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
  source /etc/profile.d/vte.sh
fi

SPACESHIP_CHAR_SYMBOL=" "
SPACESHIP_GIT_SYMBOL=" "
SPACESHIP_NODE_SYMBOL=" "
SPACESHIP_DOCKER_SYMBOL=" "
SPACESHIP_AWS_SYMBOL=" "
SPACESHIP_PACKAGE_SYMBOL=" "
SPACESHIP_KUBECONTEXT_SYMBOL=" "

SPACESHIP_PROMPT_ORDER=(
  # time          # Time stamps section
  # user          # Username section
  dir           # Current directory section
  # host          # Hostname section
  git           # Git section (git_branch + git_status)
  # hg            # Mercurial section (hg_branch  + hg_status)
  package       # Package version
  node          # Node.js section
  # ruby          # Ruby section
  # elixir        # Elixir section
  # xcode         # Xcode section
  # swift         # Swift section
  golang        # Go section
  # php           # PHP section
  # rust          # Rust section
  # haskell       # Haskell Stack section
  # julia         # Julia section
  docker        # Docker section
  aws           # Amazon Web Services section
  # venv          # virtualenv section
  # conda         # conda virtualenv section
  # pyenv         # Pyenv section
  # dotnet        # .NET section
  # ember         # Ember.js section
  kubecontext   # Kubectl context section
  # terraform     # Terraform workspace section
  exec_time     # Execution time
  line_sep      # Line break
  #battery       # Battery level and status
  # vi_mode       # Vi-mode indicator
  jobs          # Background jobs indicator
  exit_code     # Exit code section
  char          # Prompt character
)

source $HOME/.antigen.zsh

antigen use oh-my-zsh
antigen bundle git
antigen bundle safe-paste
antigen bundle diff-so-fancy
antigen bundle asdf
antigen bundle clipboard
antigen bundle docker
antigen bundle zsh-users/zsh-completions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-syntax-highlighting
# antigen bundle zdharma/fast-syntax-highlighting
antigen bundle Dbz/kube-aliases

antigen theme denysdovhan/spaceship-prompt
antigen apply

# uncomment this to profile zsh startup time
# zprof
