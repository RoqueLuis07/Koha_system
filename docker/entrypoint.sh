#!/bin/bash
set -euo pipefail

# SERVICE selects which Koha app this container instance serves.
#   intranet -> staff client (default)
#   opac     -> public catalogue
SERVICE="${SERVICE:-intranet}"
PORT="${PORT:-8080}"

: "${DB_TYPE:=mysql}"
: "${DB_HOST:?DB_HOST must be set (Railway MySQL plugin: MYSQLHOST)}"
: "${DB_PORT:=3306}"
: "${DB_NAME:?DB_NAME must be set (Railway MySQL plugin: MYSQLDATABASE)}"
: "${DB_USER:?DB_USER must be set (Railway MySQL plugin: MYSQLUSER)}"
: "${DB_PASS:?DB_PASS must be set (Railway MySQL plugin: MYSQLPASSWORD)}"
: "${DB_USE_TLS:=0}"
: "${MEMCACHED_SERVERS:=}"
: "${MEMCACHED_NAMESPACE:=KOHA}"
: "${ELASTICSEARCH_SERVERS:=}"
: "${ELASTICSEARCH_INDEX:=${DB_NAME}}"
: "${ENABLE_PLUGINS:=0}"
: "${PLACK_WORKERS:=2}"
: "${TZ:=}"
: "${SMTP_HOST:=localhost}"
: "${SMTP_PORT:=25}"
: "${SMTP_TIMEOUT:=15}"
: "${SMTP_SSL_MODE:=disabled}"
: "${SMTP_USER_NAME:=}"
: "${SMTP_PASSWORD:=}"
: "${SMTP_DEBUG:=0}"

if [ -z "${ELASTICSEARCH_SERVERS}" ]; then
    echo "WARNING: ELASTICSEARCH_SERVERS is not set. Cataloguing/search will not work" \
         "until you point it at an Elasticsearch service and re-index." >&2
fi

# These secrets must stay stable across restarts/redeploys (they protect
# sessions, stored passwords and encrypted data). Generate them once and set
# them as fixed Railway variables instead of relying on the random fallback.
if [ -z "${API_SECRET_PASSPHRASE:-}" ]; then
    echo "WARNING: API_SECRET_PASSPHRASE not set, generating an ephemeral one." >&2
    API_SECRET_PASSPHRASE="$(head -c48 /dev/urandom | base64 | tr -d '\n')"
fi
export API_SECRET_PASSPHRASE

if [ -z "${ENCRYPTION_KEY:-}" ]; then
    echo "WARNING: ENCRYPTION_KEY not set, generating an ephemeral one." >&2
    ENCRYPTION_KEY="$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
export ENCRYPTION_KEY

if [ -z "${BCRYPT_SETTINGS:-}" ]; then
    echo "WARNING: BCRYPT_SETTINGS not set, generating an ephemeral one." >&2
    BCRYPT_SETTINGS="$(perl -MCrypt::Eksblowfish::Bcrypt=en_base64 -e \
        'print "\$2a\$08\$" . en_base64(join("", map { chr(int(rand(256))) } 1..16))')"
fi
export BCRYPT_SETTINGS

export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASS DB_USE_TLS \
    MEMCACHED_SERVERS MEMCACHED_NAMESPACE ELASTICSEARCH_SERVERS ELASTICSEARCH_INDEX \
    ENABLE_PLUGINS PLACK_WORKERS TZ \
    SMTP_HOST SMTP_PORT SMTP_TIMEOUT SMTP_SSL_MODE SMTP_USER_NAME SMTP_PASSWORD SMTP_DEBUG

KOHA_CONF_VARS='${DB_TYPE} ${DB_NAME} ${DB_HOST} ${DB_PORT} ${DB_USER} ${DB_PASS} ${DB_USE_TLS}'
KOHA_CONF_VARS+=' ${MEMCACHED_SERVERS} ${MEMCACHED_NAMESPACE} ${ELASTICSEARCH_SERVERS} ${ELASTICSEARCH_INDEX}'
KOHA_CONF_VARS+=' ${ENABLE_PLUGINS} ${PLACK_WORKERS} ${TZ} ${API_SECRET_PASSPHRASE} ${BCRYPT_SETTINGS} ${ENCRYPTION_KEY}'
KOHA_CONF_VARS+=' ${SMTP_HOST} ${SMTP_PORT} ${SMTP_TIMEOUT} ${SMTP_SSL_MODE} ${SMTP_USER_NAME} ${SMTP_PASSWORD} ${SMTP_DEBUG}'

envsubst "${KOHA_CONF_VARS}" < /etc/koha/koha-conf.xml.template > "${KOHA_CONF}"

echo "Waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
for i in $(seq 1 60); do
    if mysqladmin ping -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASS}" --silent 2>/dev/null; then
        echo "MySQL is up."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "MySQL did not become ready in time, starting anyway." >&2
    fi
    sleep 2
done

case "$SERVICE" in
    intranet)
        export KOHA_INTRANET_PORT="$PORT"
        export KOHA_OPAC_PORT="0"
        ;;
    opac)
        export KOHA_OPAC_PORT="$PORT"
        export KOHA_INTRANET_PORT="0"
        ;;
    *)
        echo "Unknown SERVICE '$SERVICE', expected 'intranet' or 'opac'." >&2
        exit 1
        ;;
esac

echo "Starting Koha ($SERVICE) on port $PORT"
cd /app
exec starman --workers "${PLACK_WORKERS}" --listen ":${PORT}" app.psgi
