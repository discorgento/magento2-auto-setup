#!/bin/bash -e

INSTALL_DIR=$(dirname "$0")
LOG_FILE="$INSTALL_DIR"/install.log
echo '' > "$LOG_FILE"

# Check the system based on the available package manager and act accordingly
PACKAGE_MANAGERS=(apt dnf pacman)
for PACKAGE_MANAGER in "${PACKAGE_MANAGERS[@]}"; do
  # shellcheck disable=SC2086
  [ -n "$(which $PACKAGE_MANAGER 2> /dev/null)" ] && break
done

# If there's no deps installer for given package manager, it's a unsupported system
DEPENDENCIES_INSTALLER="$INSTALL_DIR"/requirements/package-manager/"$PACKAGE_MANAGER".sh
[ ! -e "$DEPENDENCIES_INSTALLER" ] && echo 'Unsupported system.' && exit 1

# Welcome message
echo 'Installing basic needed system deps.. '
sudo -k

[ ! -x "$DEPENDENCIES_INSTALLER" ] && chmod +x "$DEPENDENCIES_INSTALLER"
./"$DEPENDENCIES_INSTALLER" &>> "$LOG_FILE"

# Common setup
./requirements/common.sh

echo 'Done.'
echo -e "\n$(tput bold)Please reboot your system$(tput sgr0) before performing your first auto setup."
