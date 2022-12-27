# Discorgento Auto Setup
Build a ridiculously optimized Magento 2 local dev environment in minutes - with a single command.

**Are you a newcomer on Magento 2?**  
Welcome. And forget the manual setup of its [complex tech stack](https://experienceleague.adobe.com/docs/commerce-operations/installation-guide/system-requirements.html).

**Are you a senior Magento developer?**  
Forget tons of repetitive commands you have been issuing for years with the [handy aliases](@todo) that comes with this tool.

**Do you have a Magento 2 agency?**  
Drastically cut down the time spent (aka costs) with onboarding. 

## Requirements
One of the following operating systems (or a derivate of them):
 - Ubuntu 22.04+
 - Arch 2022+
 - Fedora 36+

And `git`. Probably you already have it, but just in case:  
 - Ubuntu: `sudo apt install -y git`  
 - Arch: `sudo pacman -S --noconfirm git`  
 - Fedora: `sudo dnf install -y git`  

## Install
[One-time-only] Execute the following command to install this tool:
```sh
INSTALL_DIR=~/.local/share/dg-m2-auto-setup bash -c 'git clone https://github.com/discorgento/magento2-auto-setup "$INSTALL_DIR" && cd "$INSTALL_DIR" && ./install.sh && cd - > /dev/null'
```

## Usage
From now on whenever you want to setup a store, just use the following command:
```sh
dg-setup-m2 git@yourprovider.com:path/to/repo.git
```
> 💡 Naturally, remember to replace the `git@yourprovider.com:path/to/repo.git` with the git-cloneable url of your M2 store repository.

Now type your sudo password, wait a few minutes, and *voi là*!
