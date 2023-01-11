#!/bin/bash

# Output formatting
dg-text-bold() {
  echo "${_DG_BOLD}$*${_DG_UNFORMAT}"
}

dg-text-italic() {
  echo "${_DG_ITALIC}$*${_DG_UNFORMAT}"
}

dg-text-underline() {
  echo "${_DG_UNDERLINE}$*${_DG_UNFORMAT}"
}

dg-text-highlight() {
  echo "${_DG_HIGHLIGHT}$*${_DG_UNFORMAT}"
}

# File handling
dg-cp() {
  [ -z "$1" ] && echo "The ${_DG_BOLD}from${_DG_UNFORMAT} parameter is mandatory." && return 1
  [ -z "$2" ] && echo "The ${_DG_BOLD}to${_DG_UNFORMAT} parameter is mandatory." && return 1

  DEST=$([ -d "$2" ] && echo "${2%%/}/${1##*/}" || echo "$2")

  setterm --cursor off
  pv "$1" > "$DEST"
  setterm --cursor on
}

dg-gzip() {
  ! dg-is-valid-file "$1" && return 1

  setterm --cursor off
  FILE="$1" bash -c 'pv "$FILE" | gzip -k > "$FILE".gz'
  setterm --cursor on
}

dg-is-valid-file() {
  [ -z "$1" ] && echo "File name not specified." && return 1
  [ ! -e "$1" ] && echo "File not found." && return 1

  return 0
}
