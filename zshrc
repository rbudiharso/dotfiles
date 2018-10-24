source $HOME/.antigen.zsh
source ~/.iterm2_shell_integration.zsh

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
antigen bundle asdf

antigen theme https://github.com/denysdovhan/spaceship-prompt spaceship

antigen apply
export PATH=~/.local/bin:$PATH
export PATH=~/Bin/flutter/bin:$PATH
export PATH=~/Bin:$PATH

export EDITOR='vim'

. $HOME/.asdf/completions/asdf.bash

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
	source /etc/profile.d/vte.sh
fi
export PATH="/usr/local/opt/v8@3.15/bin:$PATH"

# add alias file
. $HOME/.dotfiles/alias
