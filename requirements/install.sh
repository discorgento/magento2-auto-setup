#!/bin/bash -e

RELATIVE_DIR=$(dirname "$0")
LOG_FILE="$RELATIVE_DIR"/install.log
echo '' > "$LOG_FILE"

# Check if its Ubuntu, Fedora, or Arch and act accordingly
PACKAGE_MANAGERS=(apt dnf pacman)
for PACKAGE_MANAGER in "${PACKAGE_MANAGERS[@]}"; do
  # shellcheck disable=SC2086
  [ -n "$(which $PACKAGE_MANAGER 2> /dev/null)" ] && break
done

SETUP_SCRIPT="$RELATIVE_DIR"/package-manager/"$PACKAGE_MANAGER".sh
[ ! -e "$SETUP_SCRIPT" ] && echo 'Unsupported distro.' && exit 1

# Grant sudo access
echo 'Please provide your sudo password (to allow needed packages installation): '
SUDO_PASS=$(gum input --password --placeholder 'Your password')
sudo -k
# shellcheck disable=SC2024
echo "$SUDO_PASS" | sudo -S echo 'granted.'

[ ! -x "$SETUP_SCRIPT" ] && chmod +x "$SETUP_SCRIPT"
./"$SETUP_SCRIPT" &>> "$LOG_FILE"

# Post-install one-time common setup
[ ! "$(getent group docker)" ] && sudo groupadd docker
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker

echo 'Requirements fullfied. {{ Bold "Please reboot" }} before setuping your first project.' | gum format -t template
