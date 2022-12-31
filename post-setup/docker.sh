#!/bin/bash -e

sudo groupadd docker
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker
