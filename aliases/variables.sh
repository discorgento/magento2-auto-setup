#!/bin/bash
# shellcheck disable=SC2155

# Text Formating
export _DG_BOLD="$(tput bold)"
export _DG_HIGHLIGHT="$(tput rev)"
export _DG_ITALIC="$(tput sitm)"
export _DG_UNDERLINE="$(tput smul)"
export _DG_UNFORMAT="$(tput sgr0)"
