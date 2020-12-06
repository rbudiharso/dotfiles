alias vim=nvim
alias code=vscodium
alias kctx="kubie ctx"
alias kns="kubie ns"
if ! command -v batcat &> /dev/null
then
    alias cat=bat
else
    alias cat=batcat
fi
alias cl=clear
alias vpnu='nmcli connection up "TADAVPN"'
alias vpnd='nmcli connection down "TADAVPN"'

alias ecrlogin="aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin 876683363342.dkr.ecr.ap-southeast-1.amazonaws.com"

sht() {
  ssh $1 -t -- /bin/sh -c 'tmux has-session && exec tmux attach || exec tmux'
}
