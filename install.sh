#!/bin/bash -e

[ "$(whoami)" = 'root' ] && echo '⚠️ This script CANNOT be executed as root. Try again with your own user.' && exit 1
[ "$(id -u)" -ne 1000 ] && echo -e "🙅‍♂️ Currently we only support users with UID 1000 (the one created when you installed your system).\n$(tput bold)@see$(tput sgr0) $(tput smul)https://github.com/discorgento/magento2-auto-setup/issues/3$(tput sgr0)" && exit 1
[ "$OSTYPE" != 'linux-gnu' ] && echo 'Only Linux systems are supported currently. 🐧' && exit 1

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
DEPENDENCIES_INSTALLER="$INSTALL_DIR"/requirements/"$PACKAGE_MANAGER".sh
[ ! -e "$DEPENDENCIES_INSTALLER" ] && echo '⚠️ Unsupported distro.' && exit 1

# Install required packages
echo -n 'Installing basic needed system deps.. '
sudo -v
./"$DEPENDENCIES_INSTALLER" &>> "$LOG_FILE"

# Post installation
for POST_INSTALL_SCRIPT in "$INSTALL_DIR"/post-install/*; do
  ./"$POST_INSTALL_SCRIPT" &>> "$LOG_FILE"
done

echo 'done.'
echo "$(tput bold)Please reboot your system$(tput sgr0) before performing your first auto setup."
