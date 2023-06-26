#!/bin/bash

alias mc='magento-cloud'
alias mc-db-dump='mc db:dump -yz -r database'

mc-media-dump() {
  local MEDIA_DIR=pub/media
  local DEST_FILE=media.zip

  [ -e "$DEST_FILE" ] && trash-put "$DEST_FILE"
  [ -d "$MEDIA_DIR".bkp ] && mv "$MEDIA_DIR"{.bkp,}
  [ -d "$MEDIA_DIR" ] && mv "$MEDIA_DIR"{,.bkp}
  mkdir -p "$MEDIA_DIR"

  mc mount:download -y --exclude="catalog/product/cache" --exclude=".thumbswysiwyg" -m pub/media --target="$MEDIA_DIR" "$@"
  zip -r $DEST_FILE $MEDIA_DIR

  trash-put "$MEDIA_DIR"
  [ -d "$MEDIA_DIR".bkp ] && mv "$MEDIA_DIR"{.bkp,}

  echo '=================================================='
  echo -e "\nMagento Cloud media successfully downloaded to ${_DG_BOLD}./$DEST_FILE${_DG_UNFORMAT}"
}
