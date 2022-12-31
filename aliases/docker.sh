#!/bin/bash

## Docker
d() {
  docker "$@"
}

dc() {
  docker-compose "$@"
}

d-stop-all() {
  [ -z "$(d ps -q)" ] && return 0

  echo -n 'Stopping running containers.. '
  # shellcheck disable=SC2046
  d stop $(d ps -q) &> /dev/null
  echo 'done.'
}

## Docker Magento
dm() {
  ! m2-is-store-root-folder && return 1

  cd ..
  "bin/$1" "${@:2}"
  cd - &> /dev/null || return
}
