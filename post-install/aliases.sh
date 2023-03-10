#!/bin/bash -e

RELATIVE_DIR="$(dirname $0)"
ALIASES_DIR="$(realpath $RELATIVE_DIR/../aliases)"
SOURCE_INSTRUCTION="source $ALIASES_DIR/.autoload.sh"

SHELLS_RCS=(~/.bashrc ~/.zshrc)
for SHELL_RC in "${SHELLS_RCS[@]}"; do
  [ ! -e "$SHELL_RC" ] && continue
  grep -q "$SOURCE_INSTRUCTION" "$SHELL_RC" && continue

  echo -ne "\n# Discorgento Aliases\n$SOURCE_INSTRUCTION\n" >> "$SHELL_RC"
done
