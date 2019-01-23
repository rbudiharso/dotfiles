# my dotfiles
ZSH with [Antigen](https://github.com/zsh-users/antigen)

## Prequesities
1. git

## Getting Started

1. Install zsh (google it for your OS)
2. `chsh -s $(which zsh)`
1. `git clone git@github.com:rbudiharso/dotfiles.git ~/.dotfiles`
3. `curl -L git.io/antigen > .antigen.zsh`
4. `git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.5.1`
5. `ln -s ~/.dotfiles/zshrc ~/.zshrc`
6. `ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf`
7. `ln -s ~/.dotfiles/asdfrc ~/.asdfrc`
7. `ln -s ~/.dotfiles/default-npm-packages ~/.default-npm-packages`

## Install Fira Code font
`cd ~/.local/share/fonts && curl -fLo "Fura Code Retina Nerd Font Complete.otf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Retina/complete/Fura%20Code%20Retina%20Nerd%20Font%20Complete.ttf`
`sudo fc-cache -f -v`
