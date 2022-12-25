#!/bin/bash -e

sudo pacman -S --noconfirm --needed docker{,-compose} gum
[ ! "$(getent group docker)" ] && sudo groupadd docker
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker
