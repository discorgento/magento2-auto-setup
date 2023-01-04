#!/bin/bash

## Composer
m2-composer() {
  ! m2-check-infra && return 1
  m2-xdebug-tmp-disable-before
  m2-cache-watch-stop

  # Make sure to use the latest minor version of Composer 2.2 LTS
  if [ ! "$(m2-root bash -c '[ -e /.composer-updated.flag ] && echo 1')" ]; then
    echo -n "Updating to the latest ${_DG_BOLD}Composer 2.2 LTS${_DG_UNFORMAT} version.. "
    # shellcheck disable=SC2016
    m2-root bash -c 'curl -sS https://getcomposer.org/installer | php -- --2.2 && mv composer.phar $(which composer)' &> var/docker/composer.log
    m2-root bash -c 'touch /.composer-updated.flag'
    echo 'done.'
  fi

  dm composer "$@"

  m2-xdebug-tmp-disable-after
}
alias c="m2-composer"

m2-composer-clone-package() {
  ! m2-is-store-root-folder && return 1

  # Assure packages integrity
  for PACKAGE in "$@"; do rm -rf "vendor/$PACKAGE"; done
  c --no-ansi install --no-plugins &> /dev/null

  local STORE_ROOT_DIR
  STORE_ROOT_DIR=$(pwd)
  local MODULES_DIR="${STORE_ROOT_DIR}/var/modules"
  local VENDOR_DIR="${STORE_ROOT_DIR}/vendor"

  mkdir -p "$MODULES_DIR"

  for PACKAGE in "$@"; do
    URL=$(c --no-ansi show "$PACKAGE" | grep source | awk '{print $4}')
    VENDOR=$(echo "$PACKAGE" | awk -F '/' '{print $1}')
    FOLDER=$(echo "$PACKAGE" | awk -F '/' '{print $2}')
    REPO_DIR="${VENDOR}_${FOLDER}"
    CLONED_DIR="$MODULES_DIR/$REPO_DIR"

    echo -n "Cloning the package ${_DG_BOLD}$PACKAGE${_DG_UNFORMAT}.. "
    git clone "$URL" "$CLONED_DIR" &> /dev/null
    echo -n 'linking.. '
    cd "${VENDOR_DIR}/${VENDOR}" || return
    rm -rf "$FOLDER" &> /dev/null
    ln -sv "../../var/modules/$REPO_DIR" "$FOLDER" &> /dev/null
    cd - &> /dev/null || return
    echo 'done.'
  done
}
alias c-clone-package="m2-composer-clone-package"

m2-composer-update-cloned-packages() {
  ! m2-is-store-root-folder && return 1

  [ ! -d var/modules/ ] && echo 'No packages cloned yet.' && return 1

  for FOLDER in var/modules/*; do
    echo -n "Updating ${_DG_BOLD}$FOLDER${_DG_UNFORMAT}.. "
    cd "$FOLDER" || return
    git add . &> /dev/null
    git stash &> /dev/null
    git pull --rebase &> /dev/null
    git stash pop &> /dev/null
    cd - &> /dev/null || return
    echo 'done'
  done
}
alias c-update-cloned-packages="m2-composer-update-cloned-packages"
