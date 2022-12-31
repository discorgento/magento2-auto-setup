#!/bin/bash

## Docker Magento
dm() {
  ! m2-is-store-root-folder && return 1

  cd ..
  "bin/$1" "${@:2}"
  cd - &> /dev/null || return
}

dm-xdebug-tmp-disable-before() {
  HANDLE_XDEBUG="$(m2-xdebug-is-enabled)"
  [ "$HANDLE_XDEBUG" ] && m2-xdebug-disable
}

dm-xdebug-tmp-disable-after() {
  [ "$HANDLE_XDEBUG" ] && m2-xdebug-enable
  unset HANDLE_XDEBUG
}
