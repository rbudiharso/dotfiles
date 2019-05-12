# My dotfiles
ZSH with [Antigen](https://github.com/zsh-users/antigen)

## Prequesities
1. git

## Getting Started

### Ubuntu
```
sudo apt install -y \
  apt-transport-https \
  build-essential \
  git \
  ca-certificates \
  curl \
  gnupg-agent \
  software-properties-common \
  gnome-calendar \
  tlp \
  python3-distutils \
  python3-testresources \
  jq \
  zsh

git config --global user.email "rbudiharso@gmail.com"
git config --global user.name "Rahmat Budiharso"

# docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
# kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
# vscodium
wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | sudo apt-key add -
echo 'deb https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/repos/debs/ vscodium main' | sudo tee --append /etc/apt/sources.list.d/vscodium.list
# insomnia
echo "deb https://dl.bintray.com/getinsomnia/Insomnia /" | sudo tee -a /etc/apt/sources.list.d/insomnia.list
wget --quiet -O - https://insomnia.rest/keys/debian-public.key.asc | sudo apt-key add -
# google chrome
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
# yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

sudo apt install -y \
  neovim \
  vscodium \
  insomnia \
  google-chrome-beta \
  yarn \
  docker-ce \
  docker-ce-cli \
  containerd.io

sudo groupadd docker
sudo usermod -aG docker $USER

# kubectx & kubens
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
python /tmp/get-pip.py --user
python3 /tmp/get-pip.py --user

pip install awscli --upgrade --user
pip3 install awscli --upgrade --user

mkdir $HOME/Bin
chsh -s $(which zsh)
git clone git@github.com:rbudiharso/dotfiles.git ~/.dotfiles
curl -L git.io/antigen > .antigen.zsh
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.7.1
ln -s ~/.dotfiles/zshrc ~/.zshrc
ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/asdfrc ~/.asdfrc
ln -s ~/.dotfiles/default-npm-packages ~/.default-npm-packages
ln -s ~/.dotfiles/init.vim ~/.config/nvim/init.vim
ln -s ~/.dotfiles/local_init.vim ~/.config/nvim/local_init.vim
ln -s ~/.dotfiles/local_bundles.vim ~/.config/nvim/local_bundles.vim
```

## Install Fira Code font
```
cd ~/.local/share/fonts && curl -fLo "Fura Code Retina Nerd Font Complete.otf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Retina/complete/Fura%20Code%20Retina%20Nerd%20Font%20Complete.ttf
sudo fc-cache -f -v
```

# Fedora

Download and install nerd font
Get dotfiles from Google drive (.ssh, .kube, .aws)

```
git config --global user.email "rbudiharso@gmail.com"
git config --global user.name "Rahmat Budiharso"

sudo dnf install -y zsh util-linux-user gnome-tweaks make zlib-devel openssl-devel bzip2-devel readline-devel sqlite-devel jq tlp tlp-rdw tilix

git clone git@github.com:rbudiharso/dotfiles.git ~/.dotfiles
curl -L git.io/antigen > .antigen.zsh
git clone https://github.com/asdf-vm/asdf.git ~/.asdf

chsh -s $(which zsh)

ln -s ~/.dotfiles/zshrc ~/.zshrc
ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/asdfrc ~/.asdfrc
ln -s ~/.dotfiles/default-npm-packages ~/.default-npm-packages
ln -s ~/.dotfiles/init.vim ~/.config/nvim/init.vim
ln -s ~/.dotfiles/local_init.vim ~/.config/nvim/local_init.vim
ln -s ~/.dotfiles/local_bundles.vim ~/.config/nvim/local_bundles.vim

Logout

asdf plugin-add nodejs
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring
asdf install nodejs 10.15.3
asdf global nodejs 10.15.3

asdf plugin-add python
asdf install python 2.7.16
asdf global python 2.7.16

asdf plugin-add golang
asdf install golang 1.12.5
asdf global golang 1.12.5

asdf plugin-add ruby
asdf install ruby 2.6.3
asdf global ruby 2.6.3

asdf plugin-add kubectl
asdf install kubectl 1.14.1
asdf global kubectl 1.14.1

sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo sed -i 's/$releasever/29/' /etc/yum.repos.d/docker-ce.repo
sudo rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
sudo dnf config-manager --add-repo https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/repos/rpms/
sudo dnf install -y fedora-workstation-repositories
sudo dnf config-manager --set-enabled google-chrome
sudo dnf install -y google-chrome-beta docker-ce docker-ce-cli containerd.io vscodium yarn neovim python3-neovim

pip install --upgrade --user pip
pip install --user awscli
pip install --user awsebcli
pip3 install --user awscli
pip3 install --user awsebcli
pip install --user pynvim
pip install --user neovim
gem install neovim
npm install -g neovim

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
Logout


# gruvbox (for gnome-terminal, tilix)
bash -c  "$(wget -qO- https://git.io/vQgMr)"
select 56 (gruvbox dark)
# gedit
https://raw.githubusercontent.com/morhetz/gruvbox-contrib/master/gedit/gruvbox-dark.xml
# gruvbox for tilix, use this if the step above does not work
git clone git@github.com:MichaelThessel/tilix-gruvbox.git
cd tilix-gruvbox
sudo cp gruvbox-* /usr/share/tilix/schemes
cd ..
rm -rf tilix-gruvbox


# vimix GTK theme
git clone git@github.com:vinceliuice/vimix-gtk-themes.git ~/Downloads/vimix-gtk-themes
cd ~/Downloads/vimix-gtk-themes
./Install -c dark -t beryl -s laptop

```
