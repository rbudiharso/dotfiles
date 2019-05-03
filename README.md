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

```
# docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
# for fedora 30 while no repo exists
sudo sed -i 's/$releasever/29/' /etc/yum/repos.d/docker-ce.repo
# kubectl
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo dnf install -y kubectl
# vscodium
sudo rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg 
sudo dnf config-manager --add-repo https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/repos/rpms/
sudo dnf install vscodium
# insomnia
wget -O ~/Bin/insomnia.AppImage https://updates.insomnia.rest/downloads/linux/latest
# Google Chrome
sudo dnf install fedora-workstation-repositories
sudo dnf config-manager --set-enabled google-chrome
sudo dnf install google-chrome-beta
# Yarn
curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | sudo tee /etc/yum.repos.d/yarn.repo
sudo dnf install yarn
```
