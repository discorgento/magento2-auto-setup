#!/bin/bash

alias mc='magento-cloud'

mc-db-console() {
  mc ssh "$@" 'var/n98-magerun2 db:console'
}

mc-db-dump() {
  mc db:dump -r database -zf "$(git branch --show-current)".sql.gz
}

mc-biggest-tables() {
  mc db:sql -r database "SELECT table_schema as 'Database', table_name AS 'Table', round(((data_length + index_length) / 1024 / 1024), 2) 'Size in MB' FROM information_schema.TABLES ORDER BY (data_length + index_length) DESC LIMIT 10;"
}

mc-cron-disable() {
  mc ssh "$@" 'vendor/bin/ece-tools cron:disable'
}

mc-cron-enable() {
  mc ssh "$@" 'vendor/bin/ece-tools cron:enable'
}

mc-maintenance-enable() {
  mc ssh "$@" 'bin/magento maintenance:enable'
}

mc-maintenance-disable() {
  mc ssh "$@" 'bin/magento maintenance:disable'
}
