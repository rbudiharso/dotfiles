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

chsh -s $(which zsh)
git clone git@github.com:rbudiharso/dotfiles.git ~/.dotfiles
curl -L git.io/antigen > .antigen.zsh
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.7.1
ln -s ~/.dotfiles/zshrc ~/.zshrc
ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/asdfrc ~/.asdfrc
ln -s ~/.dotfiles/default-npm-packages ~/.default-npm-packages

```

## Install Fira Code font
```
cd ~/.local/share/fonts && curl -fLo "Fura Code Retina Nerd Font Complete.otf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Retina/complete/Fura%20Code%20Retina%20Nerd%20Font%20Complete.ttf
sudo fc-cache -f -v
```
