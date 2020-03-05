# alias md5sum=md5
# alias envsubst=/usr/local/opt/gettext/bin/envsubst
alias vim=nvim
alias code=vscodium
alias kctx=kubectx
alias kns=kubens
alias catz=highlight --style base16/nord -O truecolor
alias cl=clear
alias hey='fortune|cowsay -f stegosaurus|lolcat'
alias k=kubectl
alias vpnu='nmcli connection up "TADA VPN 2"'
alias vpnd='nmcli connection down "TADA VPN 2"'
# remove oh-my-zsh grv alias for grv program
unalias grv 2>/dev/null

sht() {
  ssh $1 -t -- /bin/sh -c 'tmux has-session && exec tmux attach || exec tmux'
}
