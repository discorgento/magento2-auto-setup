#!/bin/bash

for ALIASES_FILE in $(dirname "$0")/*.sh; do
  # shellcheck disable=SC1090
  source "$ALIASES_FILE"
done
