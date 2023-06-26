#!/bin/bash

## Functions
m2() {
  ! m2-check-infra && return 1
  mr2-check-install

  d exec -it -e XDEBUG_CONFIG='idekey=phpstorm' "$(dc ps -q phpfpm)" \
    php -d memory_limit=-1 \
    bin/magerun2 --skip-root-check --skip-magento-compatibility-check \
    "$@"
}

m2-native() {
  ! m2-check-infra && return 1
  mr2-check-install

  d exec -it -e XDEBUG_CONFIG='idekey=phpstorm' "$(dc ps -q phpfpm)" \
    php -d memory_limit=-1 \
    bin/magento "$@"
}

m2-is-store-root-folder() {
  ! m2-version 1> /dev/null && return 1
  return 0
}

m2-check-infra() {
  ! m2-is-store-root-folder && return 1
  ! dc ps --status=running -q phpfpm &> /dev/null && m2-start
  mkdir -p var/docker

  return 0
}

mr2-check-install() {
  [ -e bin/magerun2 ] && return 0

  echo -n "Installing ${_DG_BOLD}Magerun2${_DG_UNFORMAT}.. "
  m2-cli bash -c 'curl https://files.magerun.net/n98-magerun2.phar --output bin/magerun2 && chmod +x bin/magerun2' &> var/docker/magerun2.log
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
  declare -A TRY_VERSIONS_MAP
  TRY_VERSIONS_MAP=(
    [ee]="$(_m2-get-version-for enterprise)"
    [ce]="$(_m2-get-version-for community)"
    [cl]="$(_m2-get-version-for cloud)"
  )

  local VERSION
  for TRY_VERSION in "${TRY_VERSIONS_MAP[@]}"; do
    [ -n "$TRY_VERSION" ] && VERSION="$TRY_VERSION"
  done

  [ -z "$VERSION" ] && _dg-msg-error 'This command must be executed on the store root folder.' && return 1

  echo "${VERSION//[^0-9|\.|p|-]/}"
}

m2-bash() {
  m2-cli bash
}

m2-biggest-tables() {
  m2 db:query "SELECT table_schema as 'Database', table_name AS 'Table', round(((data_length + index_length) / 1024 / 1024), 2) 'Size in MB' FROM information_schema.TABLES ORDER BY (data_length + index_length) DESC LIMIT ${1:-10};"
}

m2-cli() {
  ! m2-check-infra && return 1
  dm cli "${@:-bash}"
}

m2-root() {
  ! m2-check-infra && return 1
  dm root "${@:-bash}"
}

m2-start() {
  ! m2-is-store-root-folder && return 1

  [ -d var/docker ] && trash-put var/docker
  mkdir -p var/docker

  d-stop-all
  dm start
  dc exec rabbitmq rabbitmqctl set_vm_memory_high_watermark absolute 3G

  m2-cache-warmup
}

m2-restart() {
  dm restart
}

m2-stop() {
  dm stop
}

m2-setup-upgrade() {
  ! m2-check-infra && return 1
  m2-xdebug-tmp-disable-before
  m2-cache-watch-stop

  m2 se:up

  m2-xdebug-tmp-disable-after
  m2-cache-warmup
}

m2-config-set() {
  m2 config:set -n --lock-env "$@"
}

m2-config-get() {
  m2 dev:con "\$di->create(\Magento\Framework\App\Config\ScopeConfigInterface::class)->getValue('$1');exit" | awk '/=/,0'
}

m2-db-console() {
  m2 db:co
}

m2-db-dump() {
  m2 db:dump -c gzip --strip="@stripped" -n
}

m2-db-import() { (
  set -e
  local DUMP_FILE_NAME
  DUMP_FILE_NAME=$(basename "$1")

  if [ ! -e "./$1" ]; then
    echo "File '$DUMP_FILE_NAME' not found. Make sure it is on the store root folder and try again."
    return 1
  fi

  ! m2-check-infra && return 1
  m2-xdebug-tmp-disable-before

  if [ ! "$(m2-cli bash -c 'which pv')" ]; then
    echo -n 'Enabling progress bar.. '
    m2-root bash -c 'apt update && apt-get install -y pv' &> var/docker/pv.log
    echo 'done.'
  fi

  local DB_NAME
  # shellcheck disable=SC2016
  DB_NAME=$(php -r '$env = include("app/etc/env.php");echo $env["db"]["connection"]["default"]["dbname"];')

  sed -i 's/MYSQL_USER=magento/MYSQL_USER=root/' ../env/db.env
  # shellcheck disable=SC1091
  source '../env/db.env'

  echo -n "Recreating ${_DG_BOLD}$DB_NAME${_DG_UNFORMAT} database.. "
  dm clinotty mysql -h"${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" <<< \
    "DROP DATABASE IF EXISTS $DB_NAME; CREATE DATABASE $DB_NAME;"
  echo 'done.'

  local DUMP_FILE_EXTENSION
  DUMP_FILE_EXTENSION="${DUMP_FILE_NAME##*.}"

  setterm --cursor off
  case "$DUMP_FILE_EXTENSION" in
    sql) pv "$DUMP_FILE_NAME" | dm mysql ;;
    gz) pv "$DUMP_FILE_NAME" | gunzip -c | dm mysql ;;
    *) echo -e "Dump file type is not supported." && return 1 ;;
  esac
  setterm --cursor on

  m2-post-db-import

  m2-xdebug-tmp-disable-after
); }

m2-post-db-import() { (
  set -e

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
      path LIKE 'smtp/%' OR
      path LIKE 'web/cookie%' OR
      path LIKE 'web/secure/%' OR
      path LIKE 'web/unsecure/%';
  "
  echo 'done.'

  m2 se:up
  m2-cache-warmup
  m2-recreate-admin-user
  m2-grids-slim || echo -n '' # needs to be after admin user creation
  m2-disable-2fa || echo -n ''

  echo -n 'Enabling all caches.. '
  m2 cache:enable &> var/docker/output.txt
  echo 'done.'

  echo -n 'Optimizing indexers.. '
  m2 indexer:set-mode schedule &> var/docker/output.txt
  echo 'done.'

  m2-clean-logs
  m2-custom-logs-enable

  echo -n "Reindexing ($(dg-text-bold optional), skip anytime with Ctrl+C).. "
  m2-reindex &> var/docker/reindex.log
  echo 'done.'
); }

m2-install() { (
  set -e
  ! m2-check-infra && return 1

  if ! grep -q "magento2.test" /etc/hosts; then
    echo 'Mapping the magento2.test to your /etc/hosts..'
    sudo tee -a /etc/hosts <<< "127.0.0.1	::1	magento2.test"
    echo 'mapped.'
  fi

  local DB_ENV_PATH=../env/db.env
  [ ! -e $DB_ENV_PATH ] && _dg-msg-error "Database env vars not found ($DB_ENV_PATH)" && exit
  # shellcheck disable=SC1090
  source "$DB_ENV_PATH"
  dm clinotty mysql -h"${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" <<< 'CREATE DATABASE IF NOT EXISTS magento'

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
    --elasticsearch-host="elasticsearch" \
    --elasticsearch-port="9200" \
    --elasticsearch-index-prefix="magento2" \
    --elasticsearch-timeout="15" \
    --use-rewrites="1" \
    "$@"

  m2-post-db-import
); }

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

m2-grids-slim() {
  m2 db:query "
    # Lean admin grids
    DELETE FROM ui_bookmark WHERE namespace IN ('customer_listing', 'product_listing', 'sales_order_grid');
    INSERT INTO ui_bookmark (user_id, namespace, identifier, current, title, config, created_at, updated_at)
    VALUES
      ((SELECT user_id FROM admin_user WHERE username='admin'),'customer_listing','current',0,NULL,'{\"current\":{\"search\":{\"value\":\"\"},\"filters\":{\"applied\":{\"placeholder\":true}},\"paging\":{\"pageSize\":20,\"current\":1,\"options\":{\"20\":{\"value\":20,\"label\":20},\"30\":{\"value\":30,\"label\":30},\"50\":{\"value\":50,\"label\":50},\"100\":{\"value\":100,\"label\":100},\"200\":{\"value\":200,\"label\":200}},\"value\":20},\"columns\":{\"entity_id\":{\"visible\":true,\"sorting\":\"desc\"},\"name\":{\"visible\":true,\"sorting\":false},\"email\":{\"visible\":true,\"sorting\":false},\"billing_telephone\":{\"visible\":true,\"sorting\":false},\"billing_postcode\":{\"visible\":true,\"sorting\":false},\"billing_region\":{\"visible\":false,\"sorting\":false},\"confirmation\":{\"visible\":false,\"sorting\":false},\"created_in\":{\"visible\":false,\"sorting\":false},\"billing_full\":{\"visible\":false,\"sorting\":false},\"shipping_full\":{\"visible\":false,\"sorting\":false},\"taxvat\":{\"visible\":true,\"sorting\":false},\"billing_street\":{\"visible\":false,\"sorting\":false},\"billing_city\":{\"visible\":false,\"sorting\":false},\"billing_fax\":{\"visible\":false,\"sorting\":false},\"billing_vat_id\":{\"visible\":false,\"sorting\":false},\"billing_company\":{\"visible\":false,\"sorting\":false},\"billing_firstname\":{\"visible\":false,\"sorting\":false},\"billing_lastname\":{\"visible\":false,\"sorting\":false},\"lock_expires\":{\"visible\":false,\"sorting\":false},\"mailchimp_sync\":{\"visible\":false,\"sorting\":false},\"address_reference\":{\"visible\":false,\"sorting\":false},\"actions\":{\"visible\":true,\"sorting\":false},\"ids\":{\"visible\":true,\"sorting\":false},\"group_id\":{\"visible\":true,\"sorting\":false},\"billing_country_id\":{\"visible\":false,\"sorting\":false},\"website_id\":{\"visible\":true,\"sorting\":false},\"gender\":{\"visible\":false,\"sorting\":false},\"created_at\":{\"visible\":false,\"sorting\":false},\"dob\":{\"visible\":false,\"sorting\":false}},\"displayMode\":\"grid\",\"positions\":{\"ids\":0,\"entity_id\":1,\"website_id\":2,\"name\":3,\"mailchimp_sync\":4,\"email\":5,\"taxvat\":6,\"group_id\":7,\"billing_telephone\":8,\"billing_postcode\":9,\"billing_country_id\":10,\"billing_region\":11,\"created_at\":12,\"confirmation\":13,\"created_in\":14,\"billing_full\":15,\"shipping_full\":16,\"dob\":17,\"gender\":18,\"billing_street\":19,\"billing_city\":20,\"billing_fax\":21,\"billing_vat_id\":22,\"billing_company\":23,\"billing_firstname\":24,\"billing_lastname\":25,\"lock_expires\":26,\"address_reference\":27,\"actions\":28}}}','2022-08-24 13:54:47.0','2022-08-26 14:19:09.0'),
      ((SELECT user_id FROM admin_user WHERE username='admin'),'product_listing','current',0,NULL,'{\"current\":{\"filters\":{\"applied\":{\"placeholder\":true}},\"paging\":{\"pageSize\":20,\"current\":1,\"options\":{\"20\":{\"value\":20,\"label\":20},\"30\":{\"value\":30,\"label\":30},\"50\":{\"value\":50,\"label\":50},\"100\":{\"value\":100,\"label\":100},\"200\":{\"value\":200,\"label\":200}},\"value\":20},\"search\":{\"value\":\"\"},\"columns\":{\"entity_id\":{\"visible\":true,\"sorting\":\"asc\"},\"name\":{\"visible\":true,\"sorting\":false},\"sku\":{\"visible\":true,\"sorting\":false},\"price\":{\"visible\":true,\"sorting\":false},\"websites\":{\"visible\":true,\"sorting\":false},\"qty\":{\"visible\":true,\"sorting\":false},\"mailchimp_sync\":{\"visible\":false,\"sorting\":false},\"short_description\":{\"visible\":false,\"sorting\":false},\"special_price\":{\"visible\":false,\"sorting\":false},\"cost\":{\"visible\":false,\"sorting\":false},\"weight\":{\"visible\":false,\"sorting\":false},\"meta_title\":{\"visible\":false,\"sorting\":false},\"meta_keyword\":{\"visible\":false,\"sorting\":false},\"meta_description\":{\"visible\":false,\"sorting\":false},\"url_key\":{\"visible\":false,\"sorting\":false},\"msrp\":{\"visible\":false,\"sorting\":false},\"days_pending_manufac\":{\"visible\":false,\"sorting\":false},\"actions\":{\"visible\":true,\"sorting\":false},\"ids\":{\"visible\":true,\"sorting\":false},\"type_id\":{\"visible\":false,\"sorting\":false},\"attribute_set_id\":{\"visible\":true,\"sorting\":false},\"visibility\":{\"visible\":true,\"sorting\":false},\"status\":{\"visible\":true,\"sorting\":false},\"manufacturer\":{\"visible\":false,\"sorting\":false},\"custom_design\":{\"visible\":false,\"sorting\":false},\"page_layout\":{\"visible\":false,\"sorting\":false},\"country_of_manufacture\":{\"visible\":false,\"sorting\":false},\"tax_class_id\":{\"visible\":false,\"sorting\":false},\"gift_message_available\":{\"visible\":false,\"sorting\":false},\"lancamento\":{\"visible\":false,\"sorting\":false},\"custom_layout\":{\"visible\":false,\"sorting\":false},\"prevenda\":{\"visible\":false,\"sorting\":false},\"desconto_progressivo\":{\"visible\":false,\"sorting\":false},\"o_preco_caiu\":{\"visible\":false,\"sorting\":false},\"liquida\":{\"visible\":false,\"sorting\":false},\"pre_venda_15_09\":{\"visible\":false,\"sorting\":false},\"pre_venda_19_09\":{\"visible\":false,\"sorting\":false},\"cor_riviera\":{\"visible\":false,\"sorting\":false},\"salable_quantity\":{\"visible\":false,\"sorting\":false},\"thumbnail\":{\"visible\":true,\"sorting\":false},\"special_from_date\":{\"visible\":false,\"sorting\":false},\"special_to_date\":{\"visible\":false,\"sorting\":false},\"news_from_date\":{\"visible\":false,\"sorting\":false},\"news_to_date\":{\"visible\":false,\"sorting\":false},\"custom_design_from\":{\"visible\":false,\"sorting\":false},\"custom_design_to\":{\"visible\":false,\"sorting\":false}},\"displayMode\":\"grid\",\"positions\":{\"ids\":0,\"entity_id\":1,\"thumbnail\":2,\"name\":3,\"type_id\":4,\"sku\":5,\"attribute_set_id\":6,\"price\":7,\"qty\":8,\"salable_quantity\":9,\"visibility\":10,\"status\":11,\"websites\":12,\"short_description\":13,\"special_price\":14,\"special_from_date\":15,\"special_to_date\":16,\"cost\":17,\"weight\":18,\"manufacturer\":19,\"meta_title\":20,\"meta_keyword\":21,\"meta_description\":22,\"news_from_date\":23,\"news_to_date\":24,\"url_key\":25,\"custom_design\":26,\"custom_design_from\":27,\"custom_design_to\":28,\"page_layout\":29,\"country_of_manufacture\":30,\"msrp\":31,\"tax_class_id\":32,\"gift_message_available\":33,\"days_pending_manufac\":34,\"lancamento\":35,\"custom_layout\":36,\"prevenda\":37,\"desconto_progressivo\":38,\"o_preco_caiu\":39,\"liquida\":40,\"pre_venda_15_09\":41,\"pre_venda_19_09\":42,\"cor_riviera\":43,\"actions\":44,\"mailchimp_sync\":45}}}','2022-08-26 14:20:13.0','2022-08-26 14:21:15.0'),
      ((SELECT user_id FROM admin_user WHERE username='admin'),'sales_order_grid','current',0,NULL,'{\"current\":{\"search\":{\"value\":\"\"},\"filters\":{\"applied\":{\"placeholder\":true}},\"paging\":{\"pageSize\":20,\"current\":1,\"options\":{\"20\":{\"value\":20,\"label\":20},\"30\":{\"value\":30,\"label\":30},\"50\":{\"value\":50,\"label\":50},\"100\":{\"value\":100,\"label\":100},\"200\":{\"value\":200,\"label\":200}},\"value\":20},\"columns\":{\"increment_id\":{\"visible\":true,\"sorting\":\"desc\"},\"store_id\":{\"visible\":true,\"sorting\":false},\"billing_name\":{\"visible\":true,\"sorting\":false},\"shipping_name\":{\"visible\":false,\"sorting\":false},\"base_grand_total\":{\"visible\":true,\"sorting\":false},\"grand_total\":{\"visible\":false,\"sorting\":false},\"billing_address\":{\"visible\":false,\"sorting\":false},\"shipping_address\":{\"visible\":false,\"sorting\":false},\"shipping_information\":{\"visible\":false,\"sorting\":false},\"customer_email\":{\"visible\":false,\"sorting\":false},\"subtotal\":{\"visible\":false,\"sorting\":false},\"shipping_and_handling\":{\"visible\":false,\"sorting\":false},\"customer_name\":{\"visible\":false,\"sorting\":false},\"total_refunded\":{\"visible\":false,\"sorting\":false},\"pickup_location_code\":{\"visible\":false,\"sorting\":false},\"transaction_source\":{\"visible\":false,\"sorting\":false},\"mailchimp_status\":{\"visible\":false,\"sorting\":false},\"mailchimp_sync\":{\"visible\":false,\"sorting\":false},\"allocated_sources\":{\"visible\":false,\"sorting\":false},\"actions\":{\"visible\":true,\"sorting\":false},\"ids\":{\"visible\":true,\"sorting\":false},\"created_at\":{\"visible\":true,\"sorting\":false},\"status\":{\"visible\":true,\"sorting\":false},\"customer_group\":{\"visible\":false,\"sorting\":false},\"payment_method\":{\"visible\":false,\"sorting\":false}},\"displayMode\":\"grid\",\"positions\":{\"ids\":0,\"increment_id\":1,\"store_id\":2,\"created_at\":3,\"billing_name\":4,\"shipping_name\":5,\"base_grand_total\":6,\"grand_total\":7,\"status\":8,\"billing_address\":9,\"shipping_address\":10,\"shipping_information\":11,\"customer_email\":12,\"customer_group\":13,\"subtotal\":14,\"shipping_and_handling\":15,\"customer_name\":16,\"payment_method\":17,\"total_refunded\":18,\"actions\":19,\"allocated_sources\":20,\"pickup_location_code\":21,\"transaction_source\":22,\"mailchimp_status\":23,\"mailchimp_sync\":24}}}','2022-08-26 14:20:26.0','2022-08-26 14:22:02.0');
  "
}

m2-recreate-admin-user() {
  echo -n 'Making sure admin user exists.. '
  m2 adm:us:del admin -f &> var/docker/output.txt || echo -n ''
  m2 adm:us:cr --admin-firstname=Admin --admin-lastname=Magento --admin-email=dev@mycompany.com --admin-user=admin --admin-password=Admin123@ &> var/docker/output.txt
  echo 'done.'
}

m2-cache-warmup() {
  ! m2-check-infra && return 1
  (m2-config-get '' &) &> /dev/null
  (curl -Lk localhost &) &> var/docker/cache-warmup.html
}

m2-cache-watch() {
  ! m2-check-infra && return 1

  m2-cache-watch-stop # kill running processes if any
  dm cache-clean --watch
}

m2-cache-watch-stop() {
  m2-cli bash -c 'pgrep -f cache-clean | xargs kill' &> /dev/null
}

m2-clean-logs() {
  mkdir -p var/log
  m2-root chown -Rc 1000:1000 var/log
  truncate -s 0 var/log/*.log &> /dev/null
}

m2-compile-assets() {
  trash-put pub/static/{adminhtml,frontend} var/view_preprocessed/pub/static &> /dev/null
  m2 ca:cl full_page
  m2-cache-warmup
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
  m2 de:mo:set developer
}

m2-production-mode() {
  m2 de:mo:set --skip-compilation production
  m2-deploy
}

m2-deploy() {
  m2-compile-assets
  m2 se:up
  m2 se:di:co
  m2 se:st:deploy
}

m2-console() {
  [ -z "$1" ] && m2 dev:con && return 0
  m2 dev:con "$*"
}

m2-cron-clean() {
  echo -n "Truncating $(dg-text-bold cron_schedule) table.. "
  m2 db:query 'TRUNCATE cron_schedule'
  echo 'done.'
}

m2-disable-2fa() {
  m2 mod:dis Magento_AdminAdobeImsTwoFactorAuth 1> /dev/null
  m2 mod:dis Magento_TwoFactorAuth
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
  m2 indexer:reindex catalog_{category_product,product_category,product_price} cataloginventory_stock
}

m2-reindex-invalid() {
  m2 sy:cr:run indexer_reindex_all_invalid
}

m2-sql-mass-delete() {
  [ -z "$1" ] && _dg_msg_error 'The table name is mandatory.' && return 1
  [ -z "$2" ] && _dg_msg_error 'The where clause is mandatory.' && return 1

  echo -n "Counting the records in table ${_DG_BOLD}$1${_DG_UNFORMAT}.. "
  local REMAINING
  REMAINING=$(m2 db:query "SELECT count(*) FROM $1 WHERE $2" | grep -v 'count' -m 1 | grep -o '[0-9]*')
  echo "done. Total: $REMAINING"

  local BATCH_SIZE
  BATCH_SIZE=10000

  local ITERATIONS
  ITERATIONS=$(bc -q <<< "$REMAINING / $BATCH_SIZE")

  local MOD_REST
  MOD_REST=$(bc -q <<< "$REMAINING % $BATCH_SIZE")
  [ "$MOD_REST" -gt 0 ] && ITERATIONS=$(bc -q <<< "$ITERATIONS + 1")

  [ "$ITERATIONS" -lt 1 ] && return 0

  for I in $(seq 1 "$ITERATIONS"); do
    echo -ne "\rDeleting page $I/$ITERATIONS.. "
    m2 db:query "DELETE FROM $1 WHERE $2 LIMIT $BATCH_SIZE"
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
  m2-cli watch -x bin/magerun2 db:query 'SHOW FULL PROCESSLIST'
}

m2-unit-test() {
  docker exec -it \
    -e XDEBUG_CONFIG='idekey=phpstorm' \
    "$(dc ps -q phpfpm)" \
    ./vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist \
    "$@"
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

m2-get-bearer() {
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

m2-nvm-install() {
  echo -n 'Installing yarn.. '
  m2-root bash -c 'npm i --global yarn &> var/docker/nvm-install.log'
  echo 'done.'

  echo -n 'Installing nvm.. '
  m2-cli bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash'
  echo 'done.'

  # shellcheck disable=SC2016
  m2-cli bash -c 'echo "\
#!/bin/bash
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\" # This loads nvm
" > ~/.bashrc'
}

m2-nvm-use() {
  m2-cli bash -ic "nvm install $1 && nvm use $1"
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
  dc exec -it redis redis-cli "$@"
}

m2-redis-flush() {
  m2-redis-cli FLUSHALL
  m2-cache-warmup
}

m2-sanitize-sku() {
  m2 dev:con --no-ansi "\$di->create(Magento\Catalog\Model\Product::class)->formatUrlKey('$*'); exit" | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | grep '=>' | sed -e 's/=> //' | cut -d'"' -f2
}

m2-sanitize-url-path() {
  m2-sanitize-sku "$@"
}

m2-test-class() {
  m2 dev:con --no-ansi "\$di->create(${1}::class) ? 'Valid.' : 'INVALID!!'; exit" | grep '=>'
}

m2-xdebug-tmp-disable-before() {
  M2_HANDLE_XDEBUG="$(m2-xdebug-is-enabled)"
  [ "$M2_HANDLE_XDEBUG" ] && m2-xdebug-disable
  return 0
}

m2-xdebug-tmp-disable-after() {
  [ "$M2_HANDLE_XDEBUG" ] && m2-xdebug-enable
  unset M2_HANDLE_XDEBUG
}

# Aliases
alias m2-apply-catalog-rules='m2 sys:cr:run catalogrule_apply_all'
alias m2-cloud-patches-apply="m2-cli ./vendor/bin/ece-patches apply"
alias m2-cloud-patches-list="vendor/bin/ece-patches status"
alias m2-cloud-redeploy="m2-cli bash -c 'cloud-deploy && magento-command de:mo:set developer && cloud-post-deploy'"
alias m2-delete-disabled-products="m2 db:query 'DELETE cpe FROM catalog_product_entity cpe JOIN catalog_product_entity_int cpei ON cpei.entity_id = cpe.entity_id AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = \"status\" AND entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = \"catalog_product\")) WHERE cpei.value = 2'"
alias m2-disable-captchas="m2-config-set customer/captcha/enable 0 && m2-config-set admin/captcha/enable 0"
alias m2-es-flush="curl -X DELETE 'http://localhost:9200/_all'"
alias m2-fix-missing-admin-role="m2 db:query \"INSERT INTO authorization_role (role_id, parent_id, tree_level, sort_order, role_type, user_id, user_type, role_name) VALUES (1, 0, 1, 1, 'G', 0, '2', 'Administrators'); INSERT INTO authorization_rule (rule_id, role_id, resource_id, privileges, permission) VALUES (1, 1, 'Magento_Backend::all', null, 'allow')\""
alias m2-generate-db-whitelist="m2 setup:db-declaration:generate-whitelist --module-name"
alias m2-generate-xml-autocomplete="m2 dev:urn-catalog:generate xsd_catalog_raw.xml"
alias m2-list-plugins="m2 dev:di:info"
alias m2-media-dump='zip -r media.zip pub/media --exclude "*pub/media/catalog/product/cache*"'
alias m2-pagebuilder-wizard="cd app/code; pbmodules; cd - > /dev/null"
alias m2-payment-checkmo-disable="m2-config-set payment/checkmo/active 0"
alias m2-payment-checkmo-enable="m2-config-set payment/checkmo/active 1"
alias m2-queue-clean="m2 db:query 'DELETE FROM queue_message; DELETE FROM queue_message_status; DELETE FROM queue_lock; DELETE FROM queue_poison_pill; DELETE FROM magento_bulk; DELETE FROM magento_acknowledged_bulk'"
alias m2-queue-fix="m2-module-disable Magento_WebapiAsync"
alias m2-queue-list="m2 qu:co:list"
alias m2-queue-start="m2 qu:co:start --single-thread"
alias m2-queue-stop="dc restart rabbitmq"
alias m2-reset-grids="m2 db:query 'delete from ui_bookmark'"
alias m2-setup-eslint="m2-cli bash -c 'if [ ! -e package.json ] && [ -e package.json.sample ]; then cp package.json{.sample,}; fi; npm install --save-dev eslint eslint-{config-standard,plugin-{import,node,promise,n}}' && echo '{\"extends\":\"standard\",\"rules\":{\"indent\":[\"error\",4]},\"env\":{\"amd\":true,\"browser\":true,\"jquery\":true},\"globals\":{\"Chart\":\"readonly\"},\"ignorePatterns\":[\"**/vendor/magento/*.js\"]}' > .eslintrc"
alias m2-setup-stylelint="m2-cli bash -c 'if [ ! -e package.json ] && [ -e package.json.sample ]; then cp package.json{.sample,}; fi; npm install --save-dev stylelint{,-order}'"
alias m2-shipping-flatrate-disable="m2-config-set carriers/flatrate/active 0"
alias m2-shipping-flatrate-enable="m2-config-set carriers/flatrate/active 1"
alias m2-shipping-freeshipping-disable="m2-config-set carriers/freeshipping/active 0"
alias m2-shipping-freeshipping-enable="m2-config-set carriers/freeshipping/active 1"
alias m2-shipping-shipperhq-disable="m2-config-set carriers/shqserver/active 0"
alias m2-shipping-shipperhq-enable="m2-config-set carriers/shqserver/active 1"
alias m2-multi-store-mode="m2-config-set general/single_store_mode/enabled 0 && m2-config-set web/url/use_store 1"
alias m2-single-store-mode="m2-config-set general/single_store_mode/enabled 1 && m2-config-set web/url/use_store 0"
