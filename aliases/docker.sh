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
