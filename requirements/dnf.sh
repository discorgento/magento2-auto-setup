#!/bin/bash -e

# setup repositories
## gum
echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo

# install packages
sudo dnf install -y bc docker{,-compose} gum jq
