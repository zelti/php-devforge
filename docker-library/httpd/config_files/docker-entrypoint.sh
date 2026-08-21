#!/bin/bash
#
# Generates a temporary self-signed certificate when the real one is missing, so
# Apache still starts. The browser will warn, but the environment stays usable.
#
# ./certificates is mounted read-only, so the fallback is written inside the container.
#
set -e

# Without PHP_VERSION no PHP handler is set and Apache would serve .php as text.
# Fail loudly instead.
if [ -z "${PHP_VERSION:-}" ]; then
    echo "ERROR: PHP_VERSION is empty." >&2
    echo "       Check PHP_VERSION in .env (for example: PHP_VERSION=84)." >&2
    exit 1
fi

REAL_CERT="/etc/apache2/ssl/php-devforge.pem"
FALLBACK_DIR="/etc/apache2/ssl-fallback"
DOMAIN="${DEV_DOMAIN:-localhost}"

if [ ! -s "$REAL_CERT" ]; then
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
fi

exec "$@"
