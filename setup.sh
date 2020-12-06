#!/bin/sh

set -x 

# Manual
# download dotfiles from gdrive and put them in homedir except config

# Automatic
chmod 600 $HOME/.kube/config
chmod -R 400 $HOME/.ssh/*
mkdir -p $HOME/.local/bin
mkdir -p $HOME/.local/share/applications
sudo dnf update -y
sudo dnf install -y zsh stow fzf tmux vifm kitty sway swaylock swayidle bat wofi grim slurp waybar libnsl wl-clipboard xclip awscli gammastep mako curl git util-linux-user neofetch

git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.0
source $HOME/.asdf/asdf.sh
for name in neovim starship kubectl helm k9s; do asdf plugin-add $name; done
asdf install helm 3.4.1 && asdf global helm 3.4.1
asdf install neovim 0.4.4 && asdf global neovim 0.4.4
asdf install starship 0.47.0 && asdf global starship 0.47.0
asdf install kubectl 1.19.4 && asdf global kubectl 1.19.4
asdf install k9s 0.24.1 && asdf global k9s 0.24.1

git clone https://github.com/rbudiharso/dotfiles.git $HOME/.dotfiles && cd $HOME/.dotfiles
ln -s $HOME/.dotfiles/zsh/.config/zsh/.zshenv $HOME/.zshenv
stow nvim zsh tmux vifm starship sway kitty mako swaylock swaynag waybar wofi wlogout

git clone https://github.com/k-takata/minpac.git ~/.config/nvim/pack/minpac/opt/minpac
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
pip install awscli awsebcli
mkdir -p $HOME/.config/zsh/.zim
curl -Lso $HOME/.config/zsh/.zim/zimfw.zsh https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
zsh ~/.config/zsh/.zim/zimfw.zsh install

nvim +Pu +qall

cd $HOME/Downloads
# Slack
curl -Lso  slack.rpm https://downloads.slack-edge.com/linux_releases/slack-4.11.3-0.1.fc21.x86_64.rpm
sudo dnf install -y slack.rpm

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
TryExec=/home/rbudiharso/.local/bin/Telegram/Telegram
Exec=/home/rbudiharso/.local/bin/Telegram/Telegram -workdir /home/rbudiharso/.local/share/TelegramDesktop/ -- %u
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
curl -Lso $HOME/.local/bin/Lens.AppImage https://github.com/lensapp/lens/releases/download/v3.6.9/Lens-3.6.9.AppImage
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
sudo fc-cache -fv $HOME/.local/share/fonts

# VSCodium
sudo rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=gitlab.com_paulcarroty_vscodium_repo\nbaseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg" |sudo tee -a /etc/yum.repos.d/vscodium.repo
sudo dnf install codium

chsh -s $(which zsh)
