#!/bin/bash

ALIASES_DIR=$(dirname "${BASH_SOURCE:-$0}")
for ALIASES_FILE in "$ALIASES_DIR"/*.sh; do
  # shellcheck disable=SC1090
  source "$ALIASES_FILE"
done
