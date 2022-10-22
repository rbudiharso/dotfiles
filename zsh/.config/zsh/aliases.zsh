alias vim=nvim
# alias code=vscodium
alias k=kubectl

if command -v exa &> /dev/null
then
    alias ls=exa
    alias ll='exa -l'
    alias la='exa -la'
fi

if ! command -v batcat &> /dev/null
then
    alias cat=bat
    alias catp="bat -pp"
else
    alias cat=batcat
    alias catp="batcat -pp"
fi
alias cl=clear

alias ecrlogin="aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-1.amazonaws.com"

sht() {
  ssh $1 -t -- /bin/sh -c 'tmux has-session && exec tmux attach || exec tmux'
}

alias kctx="kubectl config use-context"
kns() {
    kubectl config set-context --current --namespace="$@"
}
