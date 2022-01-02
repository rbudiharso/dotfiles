#!/bin/sh

set -x

# Manual
# download dotfiles from gdrive and put them in $HOME except config

# Automatic
chmod 600 $HOME/.kube/config
chmod -R 400 $HOME/.ssh/*
mkdir -p $HOME/.local/bin
mkdir -p $HOME/.local/share/applications

git config --global user.email "rbudiharso@gmail.com"
git config --global user.name "Rahmat Budiharso"

cd $HOME/Downloads
# Fonts with ligature
curl -Lso FantasqueSansMono.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FantasqueSansMono.zip
curl -Lso FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip
curl -Lso Hasklig.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Hasklig.zip
curl -Lso JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/JetBrainsMono.zip

unzip FantasqueSansMono.zip
unzip FiraCode.zip
unzip Hasklig.zip
unzip JetBrainsMono.zip

mkdir -p $HOME/.local/share/fonts
mv *.ttf $HOME/.local/share/fonts
rm -rf ./*

# Slack
curl -Lso /tmp/slack.rpm https://downloads.slack-edge.com/releases/linux/4.23.0/prod/x64/slack-4.23.0-0.1.fc21.x86_64.rpm

# K8s Lens
curl -Lso /tmp/lens.rpm https://api.k8slens.dev/binaries/Lens-5.3.3-latest.20211223.1.x86_64.rpm

# onefetch
cd /tmp
curl -Lso /tmp/onefetch.tar.gz https://github.com/o2sh/onefetch/releases/download/v2.8.0/onefetch-linux.tar.gz
tar -xvzf /tmp/onefetch.tar.gz
mv /tmp/onefetch $HOME/.local/bin/onefetch

# a bunch of sudo commands
sudo fc-cache -fv $HOME/.local/share/fonts

sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf update -y
sudo dnf install -y neovim zsh stow fzf tmux vifm kitty alacritty sway swaylock swayidle bat wofi grim slurp waybar libnsl wl-clipboard xclip awscli mako curl git util-linux-user neofetch gnome-shell-extension-user-theme wlogout gnome-tweaks light playerctl flatpak NetworkManager-tui openssl-devel readline-devel zlib-devel gcc-c++ polkit-gnome kanshi swappy pngquant pulseaudio-utils telegram-desktop mozilla-fira-sans-fonts
sudo dnf install -y /tmp/slack.rpm
sudo dnf install -y /tmp/lens.rpm
sudo flatpak install -y flathub com.spotify.Client

cd $HOME
git clone https://github.com/asdf-vm/asdf.git ~/.asdf
source $HOME/.asdf/asdf.sh
for name in starship kubectl helm k9s kubie nodejs; do asdf plugin-add $name; done
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
asdf install nodejs lts && asdf global nodejs lts
asdf install helm 3.7.2 && asdf global helm 3.7.2
asdf install starship 1.1.1 && asdf global starship 1.1.1
asdf install kubectl 1.23.1 && asdf global kubectl 1.23.1
asdf install k9s 0.24.18 && asdf global k9s 0.25.18
asdf install kubie 0.16.0 && asdf global kubie 0.16.0

cd $HOME/.dotfiles
ln -s $HOME/.dotfiles/zsh/.config/zsh/.zshenv $HOME/.zshenv
stow nvim zsh tmux vifm starship sway kitty mako swaylock swaynag waybar wofi wlogout asdf alacritty

sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
   https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
pip install awscli awsebcli autotiling neovim
mkdir -p $HOME/.config/zsh/.zim
curl -Lso $HOME/.config/zsh/.zim/zimfw.zsh https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
zsh ~/.config/zsh/.zim/zimfw.zsh install

nvim +PlugInstall +qall

# better git diff
git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"

# change our shell to ZSH
chsh -s $(which zsh)

# GNOME theme Graphite
git clone https://github.com/vinceliuice/Graphite-gtk-theme ~/Downloads/Graphite-gtk-theme
cd ~/Downloads/Graphite-gtk-theme
./install.sh -t green

gsettings set org.gnome.desktop.interface gtk-theme 'Graphite-green-light'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Fira Sans Bold 12'
gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode NF weight=450 12'
gsettings set org.gnome.desktop.interface document-font-name 'Fira Sans 12'
gsettings set org.gnome.desktop.interface font-name 'Fira Sans 12'

gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true

# disable default keybinding
for i in {1..9}; do
  gsettings set "org.gnome.shell.keybindings" "switch-to-application-$i" "[]"
done

