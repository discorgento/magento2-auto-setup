#!/bin/bash

## Composer
c() {
  ! m2-check-infra && return 1
  m2-xdebug-tmp-disable-before
  m2-cache-watch-stop

  # Make sure to use the latest minor version of Composer 2.2 LTS
  if [ ! "$(m2-root bash -c '[ -e /.composer-updated.flag ] && echo 1')" ]; then
    c2-install
  fi

  m2-cli php -d memory_limit=-1 /usr/local/bin/composer "$@"

  m2-xdebug-tmp-disable-after
}

c-clone-package() {
  ! m2-is-store-root-folder && return 1

  local STORE_ROOT_DIR
  STORE_ROOT_DIR=$(pwd)
  local MODULES_DIR="${STORE_ROOT_DIR}/var/modules"
  local VENDOR_DIR="${STORE_ROOT_DIR}/vendor"
  local LOG_FILE="${STORE_ROOT_DIR}/var/log/composer-clone-package.txt"

  mkdir -p "$MODULES_DIR"

  for PACKAGE in "$@"; do
    echo '==================================================' &>> "$LOG_FILE"
    echo "$PACKAGE" &>> "$LOG_FILE"

    URL=$(jq -r ".packages[] | select(.name | strings | test(\"$PACKAGE\")) | .source.url" composer.lock)
    VENDOR=$(echo "$PACKAGE" | awk -F '/' '{print $1}')
    FOLDER=$(echo "$PACKAGE" | awk -F '/' '{print $2}')
    REPO_DIR="${VENDOR}_${FOLDER}"
    CLONED_DIR="$MODULES_DIR/$REPO_DIR"

    echo -n "Cloning the package ${_DG_BOLD}$PACKAGE${_DG_UNFORMAT}.. "
    git clone "$URL" "$CLONED_DIR" &>> "$LOG_FILE"
    echo -n 'linking.. '
    cd "${VENDOR_DIR}/${VENDOR}" || return
    trash-put "$FOLDER" &>> "$LOG_FILE"
    ln -sv "../../var/modules/$REPO_DIR" "$FOLDER" &>> "$LOG_FILE"
    cd - &>> "$LOG_FILE" || return
    echo 'done.'
  done
}

c-update-cloned-packages() {
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

c1-install() {
  m2-root bash -c 'composer self-update --1' &> var/docker/composer.log
}

c2-install() {
  echo -n "Updating to the latest ${_DG_BOLD}Composer 2.2 LTS${_DG_UNFORMAT} version.. "
  # shellcheck disable=SC2016
  m2-root bash -c 'curl -sS https://getcomposer.org/installer | php -- --2.2 && mv composer.phar $(which composer)' &> var/docker/composer.log
  m2-root bash -c 'touch /.composer-updated.flag'
  echo 'done.'
}
