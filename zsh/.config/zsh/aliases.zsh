alias vim=nvim
alias code=vscodium
alias kctx="kubie ctx"
alias kns="kubie ns"
if ! command -v batcat &> /dev/null
then
    alias cat=cat
else
    alias cat=batcat
fi
alias cl=clear
alias vpnu='nmcli connection up "TADAVPN"'
alias vpnd='nmcli connection down "TADAVPN"'

sht() {
  ssh $1 -t -- /bin/sh -c 'tmux has-session && exec tmux attach || exec tmux'
}
