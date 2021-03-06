#!/bin/sh

set -x

# Manual
# download dotfiles from gdrive and put them in homedir except config

# Automatic
chmod 600 $HOME/.kube/config
chmod -R 400 $HOME/.ssh/*
mkdir -p $HOME/.local/bin
mkdir -p $HOME/.local/share/applications

git config --global user.email "rbudiharso@gmail.com"
git config --global user.name "Rahmat Budiharso"

# Slack
curl -Lso /tmp/slack.rpm https://downloads.slack-edge.com/linux_releases/slack-4.11.3-0.1.fc21.x86_64.rpm

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

# onefetch
cd /tmp
curl -Lso /tmp/onefetch.tar.gz https://github.com/o2sh/onefetch/releases/download/v2.8.0/onefetch-linux.tar.gz
tar -xvzf /tmp/onefetch.tar.gz
mv /tmp/onefetch $HOME/.local/bin/onefetch

# a bunch of sudo commands
sudo fc-cache -fv $HOME/.local/share/fonts

sudo dnf update -y
sudo dnf install -y zsh stow fzf tmux vifm kitty alacritty sway swaylock swayidle bat wofi grim slurp waybar libnsl wl-clipboard xclip awscli mako curl git util-linux-user neofetch gnome-shell-extension-user-theme wlogout redshift-gtk gnome-tweaks light playerctl flatpak NetworkManager-tui openssl-devel readline-devel zlib-devel gcc-c++ polkit-gnome kanshi swappy pngquant
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo dnf install -y /tmp/slack.rpm
sudo flatpak install -y flathub com.spotify.Client

cd $HOME
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.0
source $HOME/.asdf/asdf.sh
for name in neovim starship kubectl helm k9s kubie nodejs; do asdf plugin-add $name; done
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
asdf install helm 3.4.1 && asdf global helm 3.4.1
asdf install neovim 0.4.4 && asdf global neovim 0.4.4
asdf install starship 0.47.0 && asdf global starship 0.47.0
asdf install kubectl 1.19.4 && asdf global kubectl 1.19.4
asdf install k9s 0.24.1 && asdf global k9s 0.24.1
asdf install kubie 0.11.1 && asdf global kubie 0.11.1

cd $HOME/.dotfiles
ln -s $HOME/.dotfiles/zsh/.config/zsh/.zshenv $HOME/.zshenv
stow nvim zsh tmux vifm starship sway kitty mako swaylock swaynag waybar wofi wlogout asdf alacritty
asdf install nodejs 14.15.3 && asdf global nodejs 14.15.3

git clone https://github.com/k-takata/minpac.git ~/.config/nvim/pack/minpac/opt/minpac
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
pip install awscli awsebcli autotiling neovim
mkdir -p $HOME/.config/zsh/.zim
curl -Lso $HOME/.config/zsh/.zim/zimfw.zsh https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
zsh ~/.config/zsh/.zim/zimfw.zsh install

nvim +Pu +qall

cd $HOME/Downloads
# Telegram
curl -Lso telegram.desktop.tar.xz https://telegram.org/dl/desktop/linux
tar -xf telegram.desktop.tar.xz
mv Telegram/Telegram $HOME/.local/bin/Telegram
chmod +x $HOME/.local/bin/Telegram
cat > $HOME/.local/share/applications/Telegram.desktop <<END
[Desktop Entry]
Version=1.0
Name=Telegram Desktop
Comment=Official desktop version of Telegram messaging app
TryExec=/home/rbudiharso/.local/bin/Telegram
Exec=/home/rbudiharso/.local/bin/Telegram -workdir /home/rbudiharso/.local/share/TelegramDesktop/ -- %u
Icon=telegram
Terminal=false
StartupWMClass=TelegramDesktop
Type=Application
Categories=Chat;Network;InstantMessaging;Qt;
MimeType=x-scheme-handler/tg;
Keywords=tg;chat;im;messaging;messenger;sms;tdesktop;
X-GNOME-UsesNotifications=true
END

# Lens
curl -Lso $HOME/.local/bin/Lens.AppImage https://github.com/lensapp/lens/releases/download/v4.0.6/Lens-4.0.6.AppImage
chmod +x $HOME/.local/bin/Lens.AppImage
cat > $HOME/.local/share/applications/Lens.desktop <<END
[Desktop Entry]
Version=1.0
Name=Lens Kubernetes Dashboard
TryExec=/home/rbudiharso/.local/bin/Lens.AppImage
Exec=/home/rbudiharso/.local/bin/Lens.AppImage
Icon=Lens
Terminal=false
StartupWMClass=LensDashboard
Type=Application
END

# better git diff
git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"

# change our shell to ZSH
chsh -s $(which zsh)
