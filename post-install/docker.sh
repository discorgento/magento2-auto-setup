#!/bin/bash -e

[ ! "$(getent group docker)" ] && sudo groupadd docker
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker
