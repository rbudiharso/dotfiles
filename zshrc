source $HOME/.antigen.zsh

# POWERLEVEL9K_MODE='awesome-fontconfig'
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(\
  context \
  dir \
  vcs \
  newline \
)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(\
  node_version \
  go_version \
  php_version \
  pyenv \
  chruby \
  aws \
  aws_eb_env \
  kubecontext \
  battery \
)

SPACESHIP_PROMPT_ORDER=(
  time          # Time stamps section
  user          # Username section
  dir           # Current directory section
  host          # Hostname section
  git           # Git section (git_branch + git_status)
  # hg            # Mercurial section (hg_branch  + hg_status)
  package       # Package version
  node          # Node.js section
  ruby          # Ruby section
  elixir        # Elixir section
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
  battery       # Battery level and status
  # vi_mode       # Vi-mode indicator
  jobs          # Background jobs indicator
  exit_code     # Exit code section
  char          # Prompt character
)

SPACESHIP_CHAR_SYMBOL=" "
SPACESHIP_GIT_SYMBOL=" "
SPACESHIP_NODE_SYMBOL=" "
SPACESHIP_RUBY_SYMBOL=" "
SPACESHIP_DOCKER_SYMBOL=" "
SPACESHIP_BATTERY_SYMBOL_CHARGING=""
SPACESHIP_BATTERY_SYMBOL_DISCHARGING=""
SPACESHIP_AWS_SYMBOL=" "
SPACESHIP_PACKAGE_SYMBOL=" "
SPACESHIP_KUBECONTEXT_SYMBOL=" "

antigen use oh-my-zsh
antigen bundle git
antigen bundle git-extras
antigen bundle git-flow
antigen bundle git-prompt
antigen bundle git-remote-branch
antigen bundle github
antigen bundle gitignore
antigen bundle docker
antigen bundle docker-compose
antigen bundle command-not-found
antigen bundle history
antigen bundle safe-paste
antigen bundle screen
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-completions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle greymd/docker-zsh-completion
antigen bundle dbz/kube-aliases
antigen bundle asdf

antigen theme https://github.com/denysdovhan/spaceship-prompt spaceship
# antigen theme bhilburn/powerlevel9k powerlevel9k

antigen apply
export PATH=~/.local/bin:$PATH
export PATH=~/Bin:$PATH
export PATH=$PATH:$HOME/.linkerd2/bin

export EDITOR='vim'

. $HOME/.asdf/completions/asdf.bash

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
	source /etc/profile.d/vte.sh
fi
export PATH="/usr/local/opt/v8@3.15/bin:$PATH"

# add alias file
. $HOME/.dotfiles/alias

# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
# [[ -f /home/rbudiharso/.asdf/installs/nodejs/10.13.0/.npm/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh ]] && . /home/rbudiharso/.asdf/installs/nodejs/10.13.0/.npm/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.zsh
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
# [[ -f /home/rbudiharso/.asdf/installs/nodejs/10.13.0/.npm/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh ]] && . /home/rbudiharso/.asdf/installs/nodejs/10.13.0/.npm/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.zsh
if [ /usr/local/bin/kubectl ]; then source <(kubectl completion zsh); fi
