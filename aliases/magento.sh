#!/bin/bash

## Functions
m2() {
  ! m2-check-infra && return 1
  mr2-check-install

  warden env exec -it -- php-fpm \
    php -d memory_limit=-1 \
    bin/n98-magerun2 --skip-root-check --skip-magento-compatibility-check \
    "$@"
}

m2-native() {
  ! m2-check-infra && return 1
  mr2-check-install

  warden env exec -it -- php-fpm \
    php -d memory_limit=-1 \
    bin/magento \
    "$@"
}

m2-is-store-root-folder() {
  ! m2-version 1> /dev/null && return 1
  return 0
}

m2-check-infra() {
  ! m2-is-store-root-folder && return 1
  [ ! -d var/log ] && mkdir -p var/log

  [ -z "$(warden svc ps -q)" ] && warden svc up
  [ -z "$(warden env ps -q)" ] && warden env up

  return 0
}

mr2-install() {
  curl https://files.magerun.net/n98-magerun2.phar --output bin/n98-magerun2 && chmod +x bin/n98-magerun2
}

mr2-check-install() {
  local MAGERUN2_PATH="bin/n98-magerun2"
  [ -e "$MAGERUN2_PATH" ] && return 0

  echo -n "Installing ${_DG_BOLD}Magerun2${_DG_UNFORMAT}.. "
  local SOURCE_URL="https://files.magerun.net/n98-magerun2.phar"
  m2-cli curl "$SOURCE_URL" --output "$MAGERUN2_PATH" && chmod +x "$MAGERUN2_PATH" &> var/log/_magerun2.log
  echo 'done.'
}

_m2-get-version-for() {
  local MAGENTO_PACKAGE
  MAGENTO_PACKAGE=$([ "$1" = "cloud" ] && echo "magento/magento-cloud-metapackage" || echo "magento/product-$1-edition")

  local VERSION
  VERSION=$(jq -r ".require.\"$MAGENTO_PACKAGE\"" composer.json 2> /dev/null)
  [ "$VERSION" != "null" ] && echo "$VERSION" || echo ''
}

m2-version() {
  jq -r '.packages[] | select( .name == "magento/product-community-edition" ) | .version' composer.lock
}

m2-biggest-tables() {
  m2 db:query "SELECT table_schema as 'Database', table_name AS 'Table', round(((data_length + index_length) / 1024 / 1024), 2) 'Size in MB' FROM information_schema.TABLES ORDER BY (data_length + index_length) DESC LIMIT 10;" | column -t
}

m2-cli() {
  ! m2-check-infra && return 1
  ([ -z "$1" ] && warden shell) || warden shell -c "$*"
}

m2-debug() {
  ! m2-check-infra && return 1
  ([ -z "$1" ] && warden debug) || warden debug -c "$*"
}

m2-root() {
  ! m2-check-infra && return 1
  warden env exec -u root php-fpm "${@:-bash}"
}

m2-start() {
  ! m2-is-store-root-folder && return 1

  local WARDEN_SERVICES
  WARDEN_SERVICES=$(warden svc ps -q)
  [ -z "$WARDEN_SERVICES" ] && warden svc up

  local WARDEN_PROJECT_CONTAINERS
  WARDEN_PROJECT_CONTAINERS=$(warden env ps -q)
  [ -z "$WARDEN_PROJECT_CONTAINERS" ] && warden env up --remove-orphans

  m2-clean-logs
  m2-cache-warmup
}

m2-restart() {
  warden env down --remove-orphans
  warden env up
}

m2-stop() {
  warden env down --remove-orphans
}

m2-setup-upgrade() {
  ! m2-check-infra && return 1
  m2-cache-watch-stop

  m2-native se:up

  m2-cache-warmup
}

m2-config-set() {
  m2 config:set -n --lock-env "$@"
}

m2-config-get() {
  m2 dev:con "\$di->get(\Magento\Framework\App\Config\ScopeConfigInterface::class)->getValue('$1');exit" # | awk '/=/,0'
}

m2-db-dump() {
  m2 db:dump -c gzip --strip="@stripped" -n
}

m2-db-import() { (
  set -e

  m2-db-import-raw "$@"

  printf "Starting post db import script in 3.."
  sleep 1
  printf " 2.."
  sleep 1
  printf " 1.."
  sleep 1
  printf "\n"

  m2-post-db-import
); }

m2-db-import-raw() { (
  set -e

  local DUMP_FILE_NAME
  DUMP_FILE_NAME=$(basename "$1")

  if [ ! -e "./$1" ]; then
    echo "File '$DUMP_FILE_NAME' not found. Make sure it is on the store root folder and try again."
    return 1
  fi

  ! m2-check-infra && return 1

  local DUMP_FILE_EXTENSION
  DUMP_FILE_EXTENSION="${DUMP_FILE_NAME##*.}"

  m2-sql-root 'DROP DATABASE IF EXISTS magento; CREATE DATABASE magento'

  setterm --cursor off
  case "$DUMP_FILE_EXTENSION" in
    sql) pv "$DUMP_FILE_NAME" | warden db import -f ;;
    gz) pv "$DUMP_FILE_NAME" | gunzip -c | warden db import -f ;;
    *) echo -e "Dump file type is not supported." && return 1 ;;
  esac
  setterm --cursor on

  echo 'DB import finished.'
); }

m2-db-console() {
  m2 db:co
}

m2-db-search-column() {
  m2 db:query "SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME FROM information_schema.columns WHERE column_name LIKE '%$1%'" | sed "s/\t/ /g" | column -t
}

m2-post-db-import() { (
  set -e

  m2-redis-flush
  m2-native mod:enable --all
  m2-developer-mode

  echo -n 'Cleaning up the database.. '
  m2 db:query "
    TRUNCATE adminnotification_inbox;

    DELETE FROM flag WHERE flag_code = 'system_config_snapshot';
    DELETE FROM ui_bookmark;

    DELETE FROM core_config_data WHERE
      path LIKE '%base_url' OR
      path LIKE 'admin/url/%custom' OR
      path LIKE 'c%placeholder%' OR
      path LIKE 'catalog/search/%' OR
      path LIKE 'dev/%' OR
      path LIKE 'system/full_page_cache/%' OR
      path LIKE 'web/cookie%' OR
      path LIKE 'web/secure/%' OR
      path LIKE 'web/url/catalog_media_url%' OR
      path LIKE 'web/unsecure/%';
  "
  m2-fix-missing-admin-role
  m2-sever-integrations
  echo 'done.'

  m2 se:up
  m2-cache-warmup
  m2-recreate-admin-user || :
  m2-grids-slim # needs to be after admin user creation

  echo -n 'Enabling all caches.. '
  m2 cache:enable
  echo 'done.'

  m2-clean-logs
  m2-custom-logs-enable

  echo -n "Reindexing pending stuff.. "
  m2 indexer:set-mode schedule
  m2-es-flush
  m2-reindex-pending
  echo 'done.'
); }

m2-install() { (
  set -e
  ! m2-check-infra && return 1

  m2-sql-root 'CREATE DATABASE IF NOT EXISTS magento'

  local FILES_TO_CLEANUP=("app/etc/config.php" "app/etc/env.php")
  for FILE_TO_CLEANUP in "${FILES_TO_CLEANUP[@]}"; do
    [ -e "$FILE_TO_CLEANUP" ] && trash-put "$FILE_TO_CLEANUP"
  done

  m2-native setup:install \
    --base-url="https://magento2.test/" \
    --backend-frontname="admin" \
    --db-host="db" \
    --db-name="magento" \
    --db-user="root" \
    --db-password="magento" \
    --admin-firstname="Dev" \
    --admin-lastname="Team" \
    --admin-email="dev@discorgento.com" \
    --admin-user="admin" \
    --admin-password="Admin123@" \
    --search-engine="elasticsearch7" \
    --elasticsearch-host="opensearch" \
    --elasticsearch-port="9200" \
    --use-rewrites="1" \
    "$@"

  # base url
  m2-native config:set --lock-env web/secure/base_url https://magento2.test/
  m2-native config:set --lock-env web/unsecure/base_url https://magento2.test/

  # opensearch
  m2 db:query 'DELETE FROM core_config_data WHERE path LIKE "catalog/search%"'
  m2 db:query 'DELETE FROM core_config_data WHERE path LIKE "%elastic%"'
  m2-native config:set --lock-env catalog/search/enable_eav_indexer 1
  m2-native config:set --lock-env catalog/search/engine elasticsearch7
  m2-native config:set --lock-env catalog/search/elasticsearch7_server_hostname opensearch
  m2-native config:set --lock-env catalog/search/elasticsearch7_server_port 9200

  # misc
  m2-native config:set --lock-env admin/security/use_form_key 0

  m2-post-db-import
); }

m2-sample-data-install() {
  m2 sampledata:deploy
  m2 setup:upgrade
}

m2-sample-data-remove() {
  m2 sampledata:remove
}

m2-rebuild-indexes() {
  m2-es-flush
  m2 in:reset
  m2-reindex
}

m2-es-dump() { (
  set -e

  local DEFAULT_HOST='localhost:9200'
  local OUTPUT_TMP_DIR=.elasticdump.tmp
  local OUTPUT_FILE=elasticdump.zip

  [ -e "$OUTPUT_FILE" ] && rm $OUTPUT_FILE
  [ -d "$OUTPUT_TMP_DIR" ] && rm $OUTPUT_TMP_DIR
  mkdir -p $OUTPUT_TMP_DIR

  multielasticdump --direction=dump \
    --match='^.*$' \
    --input="http://${1:-$DEFAULT_HOST}" \
    --output=$OUTPUT_TMP_DIR

  zip -r $OUTPUT_FILE "$OUTPUT_TMP_DIR"/*.json
  rm $OUTPUT_TMP_DIR
); }

m2-grunt() {
  ! m2-check-infra && return 1
  m2-npx grunt "$@"
}

m2-sever-integrations() {
  m2 db:query '
    DELETE FROM core_config_data
    WHERE
      path LIKE "%/password"
      OR path LIKE "%_password"
      OR path LIKE "%/key"
      OR path LIKE "%_key"
      OR path LIKE "%api_key"
      OR path LIKE "%apikey"
      OR path LIKE "free/module/%"
      OR path LIKE "%/token"
      OR path LIKE "%_token"
      OR path LIKE "%/passcode"
      OR path LIKE "%_passcode"
      OR path LIKE "%secret"
      OR path LIKE "%/%/%key"
      OR path LIKE "smtp/%"
      OR path LIKE "system/gmailsmtpapp/%"
      OR path LIKE "system/smtp/%"
  '
}

m2-grids-slim() {
  m2 db:query "
    DELETE FROM ui_bookmark;

    # products grid
    UPDATE catalog_eav_attribute SET is_used_in_grid = 0 WHERE attribute_id IN (
      SELECT attribute_id FROM eav_attribute WHERE is_user_defined = 1
    );

    # customers grid
    UPDATE customer_eav_attribute SET is_used_in_grid = 0 WHERE attribute_id IN (
      SELECT attribute_id FROM eav_attribute WHERE is_user_defined = 1
    );
  "
}

m2-fix-missing-admin-role() {
  m2 db:query "
    DELETE FROM authorization_role;
    INSERT INTO authorization_role (role_id, parent_id, tree_level, sort_order, role_type, user_id, user_type, role_name) VALUES (1, 0, 1, 1, 'G', 0, '2', 'Administrators');
    INSERT INTO authorization_rule (rule_id, role_id, resource_id, privileges, permission) VALUES (1, 1, 'Magento_Backend::all', null, 'allow')
  "
}

m2-find-fixture() {
  find dev/tests/integration/testsuite vendor -wholename '*/_files/*.php' | fzf
}

m2-recreate-admin-user() {
  echo -n 'Making sure admin user exists.. '
  m2 adm:us:del admin -f || echo -n ''
  m2 adm:us:cr --admin-firstname=Local --admin-lastname=Dev --admin-email=dev@discorgento.com --admin-user=admin --admin-password=Admin123@ || echo -n ''
  echo 'done.'
}

m2-cache-warmup() {
  ! m2-check-infra && return 1
  (m2-config-get '' &) &> /dev/null
  local DOMAIN
  DOMAIN="$(grep TRAEFIK_DOMAIN .env | cut -d'=' -f2)"
  (curl -Lk "$DOMAIN" &) &> var/log/_cache-warmup.html
}

m2-cache-watch() {
  ! m2-check-infra && return 1

  m2-cache-watch-stop # kill running processes if any
  # shellcheck disable=SC2088
  m2-cli '~/.composer/vendor/bin/cache-clean.js -w'
}

m2-cache-watch-stop() {
  m2-cli pgrep -f cache-clean | xargs kill &> /dev/null
}

m2-clean-logs() {
  [ -d var/log ] && trash-put var/log
  mkdir -p var/log
}

m2-compile-assets() {
  trash-put pub/static/{adminhtml,frontend} var/view_preprocessed/pub/static &> /dev/null || :
  m2 ca:cl full_page
}

m2-custom-logs-enable() {
  local LOG_FILE_NAME='plugins-and-observers.log'

  # plugins
  local INTERCEPTOR_FILE_PATH='vendor/magento/framework/Interception/Interceptor.php'
  if ! grep -q 'function _dgCustomLog' $INTERCEPTOR_FILE_PATH; then sed -i "s/private \$pluginList;/private \$pluginList;\n\n    public static \$_lastToLog;\n\n    private function _dgCustomLog(\$pluginInstance, \$pluginMethod, \$method, \$capMethod)\n    {\n        if (str_contains(get_class(\$pluginInstance), 'Magento\\\\\\\\')) {\n            return;\n        }\n\n        \$logFile = fopen(BP . '\/var\/log\/$LOG_FILE_NAME', 'a+');\n        try {\n            \$toLog = get_class(\$pluginInstance) . '@' . \$pluginMethod;\n        } catch (\\\\Throwable \$e) {\n            try {\n                \$toLog = parent::class . '@' . \$method;\n            } catch (\\\\Throwable \$e) {\n            }\n        }\n\n        if (self::\$_lastToLog != \$toLog) {\n            \$pluginType = str_replace(\$capMethod, '', \$pluginMethod);\n            fwrite(\$logFile, getmypid() . \"\\t\" . microtime(true) . \"\\t\[P\]\[\$pluginType\]\\t\" . \$toLog . PHP_EOL);\n            self::\$_lastToLog = \$toLog;\n        }\n\n        fclose(\$logFile);\n    }/g" $INTERCEPTOR_FILE_PATH; fi
  if ! grep -q 'this->_dgCustomLog(' $INTERCEPTOR_FILE_PATH; then sed -i "/\$pluginMethod = /a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \$this->_dgCustomLog(\$pluginInstance, \$pluginMethod, \$method, \$capMethod);" $INTERCEPTOR_FILE_PATH; fi

  # observers
  local INVOKER_FILE_PATH='vendor/magento/framework/Event/Invoker/InvokerDefault.php'
  if ! grep -q "$LOG_FILE_NAME" $INVOKER_FILE_PATH; then sed -i "s/\$this->_callObserverMethod(\$object, \$observer);/if (!str_contains(get_class(\$object), 'Magento\\\\\\\\')) {\n            \$logFile = fopen(BP . '\/var\/log\/$LOG_FILE_NAME', 'a+');\n            fwrite(\$logFile, getmypid() . \"\\t\" . microtime(true) . \"\\t[O]\\t\\t\\t\" . get_class(\$object) . PHP_EOL);\n            fclose(\$logFile);\n        }\n\n        \$this->_callObserverMethod(\$object, \$observer);/g" $INVOKER_FILE_PATH; fi
}

m2-developer-mode() {
  m2-native de:mo:set developer
}

m2-production-mode() {
  m2-native de:mo:set --skip-compilation production
  m2-deploy
}

m2-deploy() { (
  set -e
  m2-compile-assets

  m2 se:di:co
  m2 se:st:deploy --jobs="$(nproc)"

  ! m2 app:co:status && m2 app:co:im
  ! m2 setup:db:status && m2 se:up --keep-generated

  echo 'm2-deploy done.'
); }

m2-console() {
  [ -z "$1" ] && m2 dev:con && return 0
  m2 dev:con "$*"
}

m2-cron-clean() {
  echo -n "Truncating $(dg-text-bold cron_schedule) table.. "
  m2 db:query 'TRUNCATE cron_schedule'
  echo 'done.'
}

m2-orders-delete-old() {
  local KEEP_ORDERS_SINCE_DATE
  KEEP_ORDERS_SINCE_DATE=$(date +%Y-%m-%d -d "6 months ago")

  m2-sql-mass-delete sales_order "created_at < '$KEEP_ORDERS_SINCE_DATE 00:00:00'"
  m2-sql-mass-delete sales_order_grid "created_at < '$KEEP_ORDERS_SINCE_DATE 00:00:00'"
  m2-sql-mass-delete sales_order_tax "order_id NOT IN (SELECT entity_id FROM sales_order)"

  echo -n 'Cleaning up residual stuff.. '

  echo -n 'grid.. '
  m2 db:query "DELETE FROM sales_order_grid WHERE entity_id NOT IN (SELECT entity_id FROM sales_order)"

  echo -n 'taxes..'
  m2 db:query "DELETE FROM sales_order_tax WHERE order_id NOT IN (SELECT entity_id FROM sales_order)"

  echo 'done.'

  echo -e '\nOld orders cleanup finished.'
}

m2-reindex() {
  m2 indexer:set-mode schedule
  m2 indexer:reset
  m2 indexer:reindex
}

m2-reindex-catalog() {
  m2 indexer:reindex catalog_product_price cataloginventory_stock catalog_category_product catalog_product_attribute
}

m2-reindex-pending() {
  m2 sy:cr:run indexer_reindex_all_invalid
  m2 sy:cr:run indexer_update_all_views
}

m2-sql() {
  ([ -z "$1" ] && warden db connect) ||
    warden env exec -it db bash -c "mysql -umagento -pmagento -Dmagento -e '$*'"
}

m2-sql-integration-tests-db() {
  ([ -z "$1" ] && warden env exec -it tmp-mysql bash -c 'mysql -uroot -pmagento -Dmagento_integration_tests') ||
    warden env exec -it tmp-mysql bash -c "mysql -uroot -pmagento -Dmagento_integration_tests -e '$*'"
}

m2-sql-root() {
  ([ -z "$1" ] && warden env exec -it db bash -c 'mysql -uroot -pmagento') ||
    warden env exec -it db bash -c "mysql -uroot -pmagento -e '$*'"
}

m2-sql-mass-delete() {
  [ -z "$1" ] && _dg-msg-error 'The table name is mandatory.' && return 1

  local WHERE
  WHERE=${2:-'1=1'}

  echo -n "Counting the records in table ${_DG_BOLD}$1${_DG_UNFORMAT}.. "
  local REMAINING
  REMAINING=$(m2 db:query "SELECT count(*) FROM $1 WHERE $WHERE" | grep -v 'count' -m 1 | grep -o '[0-9]*')
  echo "done. Total: $REMAINING"

  local BATCH_SIZE
  BATCH_SIZE=${3:-10000}

  local ITERATIONS
  ITERATIONS=$(bc -q <<< "$REMAINING / $BATCH_SIZE")

  local MOD_REST
  MOD_REST=$(bc -q <<< "$REMAINING % $BATCH_SIZE")
  [ "$MOD_REST" -gt 0 ] && ITERATIONS=$(bc -q <<< "$ITERATIONS + 1")

  [ "$ITERATIONS" -lt 1 ] && return 0

  for I in $(seq 1 "$ITERATIONS"); do
    echo -ne "\rDeleting page $I/$ITERATIONS.. "
    m2 db:query "DELETE FROM $1 WHERE $WHERE LIMIT $BATCH_SIZE"
    REMAINING=$REMAINING-$BATCH_SIZE
  done
  echo 'done.'
}

m2-sql-clean-file() {
  ! dg-is-valid-file "$1" && return 1

  echo -n "Cleaning the provided ${_DG_BOLD}$1${_DG_UNFORMAT} file.. "
  mkdir -p var/log

  # shellcheck disable=SC2016
  sed '
    s/\sDEFINER=`[^`]*`@`[^`]*`//g;
    /@@GLOBAL.GTID/,/\;/d;
    /^CREATE DATABASE/d;
    /^USE /d
  ' -i "$1" &> var/log/sql-clean.log

  echo 'done.'
}

m2-sql-watch() {
  m2-cli watch -x bin/n98-magerun2 db:query "SHOW FULL PROCESSLIST"
}

m2-test-unit() {
  # shellcheck disable=SC2016
  clear && m2-cli 'vendor/bin/phpunit -c "$(pwd)/dev/tests/unit/phpunit.xml"'
}

m2-test-unit-debug() {
  # shellcheck disable=SC2016
  clear && m2-debug 'vendor/bin/phpunit -c "$(pwd)/dev/tests/unit/phpunit.xml"'
}

m2-test-integration() {
  # shellcheck disable=SC2016
  clear && m2-cli 'vendor/bin/phpunit -c "$(pwd)/dev/tests/integration/phpunit.xml"'
}

m2-test-integration-debug() {
  # shellcheck disable=SC2016
  clear && m2-debug 'vendor/bin/phpunit -c "$(pwd)/dev/tests/integration/phpunit.xml"'
}

m2-test-integration-clean() {
  sed -i 's/TESTS_CLEANUP"\ value="disabled/TESTS_CLEANUP"\ value="enabled/g' dev/tests/integration/phpunit.xml
  rm -rf dev/tests/integration/tmp/* generated/* || :
  m2-test-integration
  sed -i 's/TESTS_CLEANUP"\ value="enabled/TESTS_CLEANUP"\ value="disabled/g' dev/tests/integration/phpunit.xml
}

m2-xdebug-is-enabled() {
  [ "$(dm xdebug status)" = 'Xdebug debug mode is enabled.' ] && echo 1
  return 0
}

m2-xdebug-enable() {
  [ "$(m2-xdebug-is-enabled)" ] && echo 'Already enabled.' && return 0

  echo -n 'Enabling xdebug.. '
  dm xdebug enable &> /dev/null
  echo 'done.'
}

m2-xdebug-disable() {
  [ ! "$(m2-xdebug-is-enabled)" ] && echo 'Already disabled.' && return 0

  echo -n 'Disabling xdebug.. '
  dm xdebug disable &> /dev/null
  echo 'done.'
}

m2-bearer() {
  # m2-disable-two-factor-authentication
  if [ -n "$1" ] && [ -n "$2" ] && [ -z "$3" ]; then
    echo -n "Password for user \"$2\": "
    read -rs ADMIN_PASSWORD
  else
    ADMIN_PASSWORD=$3
  fi

  [ -n "$ADMIN_PASSWORD" ] && echo '' # break line after password
  curl -kL -X POST \
    -H 'Content-Type: application/json' \
    --data-raw "{\"username\": \"${2:-admin}\", \"password\": \"${ADMIN_PASSWORD:-Admin123@}\"}" \
    "${1:-https://localhost/}/rest/V1/integration/admin/token"
  echo '' # prevent awkward % at the end of previous command
}

m2-generate-crypt-key() {
  echo "${PWD##*/}" | md5sum | awk "{print $1}"
}

m2-module-disable() {
  m2 mod:dis --clear-static-content "$@"
  m2-cache-warmup
}

m2-module-enable() {
  m2 mod:en --clear-static-content "$@"
  m2-cache-warmup
}

m2-es-flush() {
  m2-cli "curl -X DELETE 'http://elasticsearch:9200/_all' 2> /dev/null" ||
    m2-cli "curl -X DELETE 'http://opensearch:9200/_all'"
}

m2-es-version() {
  local ES_HOST
  ES_HOST="$(warden env ps | grep search | awk '{print $4}')"
  m2-cli curl -XGET "$ES_HOST:9200" 2> /dev/null | jq -r '.version.distribution + " " + .version.number'
}

m2-queue-start() {
  m2-cli 'bin/magento qu:co:li | xargs -P0 -n1 bin/magento qu:co:start --single-thread'
}

m2-npm() {
  m2-cli npm "$@"
}

m2-npx() {
  m2-cli npx --yes "$@"
}

m2-mysql-cli() {
  dm mysql
}

m2-redis-cli() {
  warden redis "$@"
}

m2-redis-flush() {
  m2-redis-cli FLUSHALL
}

m2-redis-version() {
  m2-redis-cli INFO server | grep redis_version | awk -F':' '{print $2}'
}

m2-sanitize-sku() {
  m2 dev:con --no-ansi "\$di->create(Magento\Catalog\Model\Product::class)->formatUrlKey('$*'); exit" | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | grep '=>' | sed -e 's/=> //' | cut -d'"' -f2
}

m2-sanitize-url-path() {
  m2 dev:con --no-ansi "\$di->get(Magento\Framework\Filter\FilterManager::class)->translitUrl('$*'); exit" | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | grep '= ' | sed -e 's/=> //' | cut -d'"' -f2
}

m2-class-is-valid() {
  m2 dev:con --no-ansi "\$di->create(${1}::class) ? 'Valid.' : 'INVALID!!'; exit" | grep '=>'
}

# Aliases
alias m2-apply-catalog-rules='m2 sys:cr:run catalogrule_apply_all'
alias m2-cloud-patches-apply="m2-cli ./vendor/bin/ece-patches apply"
alias m2-cloud-patches-list="vendor/bin/ece-patches status"
alias m2-cloud-redeploy="m2-cli cloud-deploy && magento-command de:mo:set developer && cloud-post-deploy"
alias m2-delete-disabled-products="m2 db:query 'DELETE cpe FROM catalog_product_entity cpe JOIN catalog_product_entity_int cpei ON cpei.entity_id = cpe.entity_id AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = \"status\" AND entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = \"catalog_product\")) WHERE cpei.value = 2'"
alias m2-disable-captchas="m2-config-set customer/captcha/enable 0 && m2-config-set admin/captcha/enable 0"
alias m2-generate-db-whitelist="m2 setup:db-declaration:generate-whitelist --module-name"
alias m2-generate-xml-autocomplete="m2 dev:urn-catalog:generate xsd_catalog_raw.xml"
alias m2-list-plugins="m2 dev:di:info"
alias m2-media-dump='zip -r media.zip pub/media --exclude "*pub/media/catalog/product/cache*"'
alias m2-pagebuilder-wizard="cd app/code; pbmodules; cd - > /dev/null"
alias m2-payment-checkmo-disable="m2-config-set payment/checkmo/active 0"
alias m2-payment-checkmo-enable="m2-config-set payment/checkmo/active 1"
alias m2-queue-clean="m2 db:query 'DELETE FROM queue_message; DELETE FROM queue_message_status; DELETE FROM queue_lock; DELETE FROM queue_poison_pill; DELETE FROM magento_bulk; DELETE FROM magento_acknowledged_bulk'"
alias m2-queue-fix="m2-module-disable Magento_WebapiAsync"
alias m2-reset-grids="m2 db:query 'delete from ui_bookmark'"
alias m2-setup-npm="[[ ! -e package.json && -e package.json.sample ]] && cp package.json{.sample,}"
alias m2-setup-eslint="m2-setup-npm; m2-cli npm install --save-dev eslint eslint-{config-standard,plugin-{import,node,promise,n}} && echo '{\"extends\":\"standard\",\"rules\":{\"indent\":[\"error\",4]},\"env\":{\"amd\":true,\"browser\":true,\"jquery\":true},\"globals\":{\"Chart\":\"readonly\"},\"ignorePatterns\":[\"**/vendor/magento/*.js\"]}' > .eslintrc"
alias m2-setup-stylelint="m2-setup-npm; m2-cli npm install --save-dev stylelint{,-order}"
alias m2-shipping-flatrate-disable="m2-config-set carriers/flatrate/active 0"
alias m2-shipping-flatrate-enable="m2-config-set carriers/flatrate/active 1"
alias m2-shipping-freeshipping-disable="m2-config-set carriers/freeshipping/active 0"
alias m2-shipping-freeshipping-enable="m2-config-set carriers/freeshipping/active 1"
alias m2-shipping-shipperhq-disable="m2-config-set carriers/shqserver/active 0"
alias m2-shipping-shipperhq-enable="m2-config-set carriers/shqserver/active 1"
alias m2-multi-store-mode="m2-config-set general/single_store_mode/enabled 0 && m2-config-set web/url/use_store 1"
alias m2-single-store-mode="m2-config-set general/single_store_mode/enabled 1 && m2-config-set web/url/use_store 0"
