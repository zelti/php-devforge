#!/bin/bash
#
# Generates a temporary self-signed certificate when the real one is missing, so
# nginx still starts. The browser will warn, but the environment stays usable.
#
# nginx has no equivalent of Apache's <IfFile>, so the choice is made here and
# handed to the template as $SSL_CERT / $SSL_KEY.
#
# docker-library/httpd/config_files/docker-entrypoint.sh does the same job for
# Apache. The two are kept separate on purpose: sharing twelve lines of openssl
# would mean widening both build contexts to ./docker-library, which ships every
# other image's files as context and churns the cache on unrelated edits.
#
set -e

REAL_CERT="/etc/nginx/ssl/php-devforge.pem"
REAL_KEY="/etc/nginx/ssl/php-devforge.key"
FALLBACK_DIR="/etc/nginx/ssl-fallback"
DOMAIN="${DEV_DOMAIN:-localhost}"

if [ -s "$REAL_CERT" ]; then
    export SSL_CERT="$REAL_CERT"
    export SSL_KEY="$REAL_KEY"
else
    echo "⚠️  $REAL_CERT not found"
    echo "    Generating a temporary self-signed certificate for *.${DOMAIN}"
    echo "    Your browser will warn that it is not trusted."
    echo "    Run ./install_cert.sh on the host to get the real one."

    mkdir -p "$FALLBACK_DIR"
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -subj "/CN=${DOMAIN}" \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN}" \
        -keyout "${FALLBACK_DIR}/fallback.key" \
        -out "${FALLBACK_DIR}/fallback.pem" >/dev/null 2>&1
    chmod 600 "${FALLBACK_DIR}/fallback.key"

    export SSL_CERT="${FALLBACK_DIR}/fallback.pem"
    export SSL_KEY="${FALLBACK_DIR}/fallback.key"
fi

# The variable list is explicit so nginx's own $mail and $subdomains survive.
envsubst '$DEV_DOMAIN $PHP_VERSION $ENABLED_PROFILES $SSL_CERT $SSL_KEY' \
    < /etc/nginx/conf.d/site.conf.tpl > /etc/nginx/conf.d/site.conf
envsubst '$DEV_DOMAIN $PHP_VERSION $ENABLED_PROFILES $SSL_CERT $SSL_KEY' \
    < /etc/nginx/conf.d/common_server_config.conf.tpl > /etc/nginx/snippets/common_server_config.conf

exec "$@"
