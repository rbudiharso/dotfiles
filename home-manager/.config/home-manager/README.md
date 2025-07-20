# Nix Linux

## Prerequisities
1. nixos or determinate-nix

## Getting started
```shell
$ git clone https://github.com/rbudiharso/dotfiles.git ~/.dotfiles
$ nix run github:nix-community/home-manager/release-25.05 -- switch --flake ~/.dotfiles/nix-linux/.config/nix/
```
