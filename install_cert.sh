#!/bin/bash
#
# Generates the local certificates and trusts the CA on this machine.
# --remove undoes the trust half, and is what ./uninstall.sh calls.
#
# mkcert runs inside a container, so nothing is installed on the host.
# Only the trust step happens outside Docker: a container has its own trust
# store, so trusting the CA in there would achieve nothing.
#
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

# --- SETTINGS ---
CERT_DIR="certificates"
CAROOT_DIR=".caroot"
CERT_NAME="php-devforge.pem"
KEY_NAME="php-devforge.key"
CA_FILE="${CAROOT_DIR}/rootCA.pem"
NSS_NICKNAME="PHP DevForge local CA"
# -----------------

# Where this distribution keeps its CA anchors, as "dir<TAB>update-command".
# One detection for installing and removing, so the two cannot drift apart.
detect_anchor() {
    if [ -d /etc/ca-certificates/trust-source/anchors ]; then
        printf '%s\t%s\n' /etc/ca-certificates/trust-source/anchors update-ca-trust
    elif [ -d /etc/pki/ca-trust/source/anchors ]; then
        printf '%s\t%s\n' /etc/pki/ca-trust/source/anchors update-ca-trust
    elif [ -d /usr/local/share/ca-certificates ]; then
        # Debian / Ubuntu (the .crt extension is required here)
        printf '%s\t%s\n' /usr/local/share/ca-certificates update-ca-certificates
    fi
}

# Every NSS store on this machine. Firefox and Chrome do not read the system
# one, so the CA has to be added -- and removed -- from each of these too.
nss_dbs() {
    [ -d "$HOME/.pki/nssdb" ] && echo "$HOME/.pki/nssdb"
    for profile in "$HOME"/.mozilla/firefox/*/; do
        [ -e "${profile}cert9.db" ] && echo "${profile%/}"
    done
    return 0
}

del_from_nss() {
    local db="$1"
    [ -d "$db" ] || return 0
    if certutil -D -n "$NSS_NICKNAME" -d "sql:$db" >/dev/null 2>&1; then
        echo "   ✅ removed from $db"
    fi
}

# Undoes step 3 and step 4 below. The certificates themselves are files in the
# checkout and are ./uninstall.sh's business, not this script's.
do_remove() {
    echo "🔏 Removing the PHP DevForge CA from this machine..."

    case "$(uname -s)" in
        Linux)
            local anchor dir update target
            anchor="$(detect_anchor)"
            if [ -z "$anchor" ]; then
                echo "   ⚠️  Could not detect this distribution's trust store; skipping."
            else
                dir="${anchor%%	*}"; update="${anchor##*	}"
                target="${dir}/php-devforge-ca.crt"
                if [ -f "$target" ]; then
                    # Checked before sudo: uninstalling on a machine that never
                    # trusted the CA should not ask for a password.
                    echo "   Removing $target (you will be asked for your password)..."
                    sudo rm -f "$target"
                    sudo "$update"
                    echo "   ✅ CA removed from the system store."
                else
                    echo "   Not in the system store. Nothing to do."
                fi
            fi
            ;;
        Darwin)
            if [ -s "$CA_FILE" ]; then
                local sha1
                sha1=$(openssl x509 -in "$CA_FILE" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
                if security find-certificate -a -Z /Library/Keychains/System.keychain 2>/dev/null \
                     | grep -qi "$sha1"; then
                    echo "   Removing it from the system keychain (you will be asked for your password)..."
                    sudo security delete-certificate -Z "$sha1" /Library/Keychains/System.keychain
                    echo "   ✅ CA removed from the system keychain."
                else
                    echo "   Not in the system keychain. Nothing to do."
                fi
            else
                echo "   ⚠️  $CA_FILE is gone, so the keychain entry cannot be identified."
                echo "      Remove it by hand in Keychain Access (search: mkcert)."
            fi
            ;;
        *) echo "   ⚠️  Unknown system; skipping the system store." ;;
    esac

    if command -v certutil >/dev/null 2>&1; then
        echo "🌐 Removing it from browsers (Firefox / Chrome)..."
        while read -r db; do
            [ -n "$db" ] && del_from_nss "$db"
        done <<EOF
$(nss_dbs)
EOF
    fi

    echo ""
    echo "✅ Done. Restart your browser for it to stop trusting the old CA."
}

case "${1:-}" in
    --remove) do_remove; exit 0 ;;
    -h|--help)
        echo "Usage: $0 [--remove]"
        echo "  no options   generate the certificates and trust the CA"
        echo "  --remove     stop trusting the CA (system store and browsers)"
        exit 0 ;;
    "") ;;
    *) echo "❌ Unknown option: $1"; exit 1 ;;
esac

echo "🔐 Setting up local certificates for PHP DevForge..."

# 1. Read DEV_DOMAIN from .env
if [ -f .env ]; then
    set -a +u
    . ./.env
    set +a -u
fi

if [ -z "${DEV_DOMAIN:-}" ]; then
    echo "❌ Error: could not read 'DEV_DOMAIN' from .env. Aborting."
    exit 1
fi

echo "   Development domain: $DEV_DOMAIN"

# 2. Generate the certificates inside the container.
#    The directories must exist first, or Docker creates them owned by root.
mkdir -p "$CERT_DIR" "$CAROOT_DIR"

#    If the stack was started before running this script, Docker already made
#    those folders root-owned and the mkcert container (running as your UID)
#    could not write to them. Fix the owner when needed.
for d in "$CERT_DIR" "$CAROOT_DIR"; do
    if [ ! -w "$d" ]; then
        echo "   $d is owned by root (Docker created it). Fixing ownership..."
        sudo chown -R "$(id -u):$(id -g)" "$d"
    fi
done

echo "📦 Generating certificates with mkcert (in a container)..."
docker compose run --rm --user "$(id -u):$(id -g)" mkcert

# Check we got what we expected. The names come from the 'mkcert' service in
# docker-compose.yml and must match what Apache reads in
# docker-library/httpd/config_files/devlocal_https.conf.
for f in "${CERT_DIR}/${CERT_NAME}" "${CERT_DIR}/${KEY_NAME}" "$CA_FILE"; do
    if [ ! -s "$f" ]; then
        echo "❌ Error: $f was not generated"
        echo "   Check that the 'mkcert' service in docker-compose.yml uses these names."
        exit 1
    fi
    echo "   ✅ $f"
done

# 3. Trust the CA in the system store.
#    Each distribution has its own anchor directory. If the file is already
#    installed and identical, sudo is not requested.
install_ca_linux() {
    local anchor_dir="$1" update_cmd="$2"
    local target="${anchor_dir}/php-devforge-ca.crt"

    if cmp -s "$CA_FILE" "$target" 2>/dev/null; then
        echo "   CA already in the system store. Nothing to do."
        return 0
    fi

    echo "   Installing the CA into $anchor_dir (you will be asked for your password)..."
    sudo install -m 644 "$CA_FILE" "$target"
    sudo "$update_cmd"
    echo "   ✅ CA trusted by the system."
}

echo "🔏 Trusting the certificate authority on this machine..."
case "$(uname -s)" in
    Linux)
        ANCHOR="$(detect_anchor)"
        if [ -n "$ANCHOR" ]; then
            install_ca_linux "${ANCHOR%%	*}" "${ANCHOR##*	}"
        else
            echo "   ⚠️  Could not detect this distribution's trust store."
            echo "      Install it manually: $CA_FILE"
        fi
        ;;
    Darwin)
        CA_SHA1=$(openssl x509 -in "$CA_FILE" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
        if security find-certificate -a -Z /Library/Keychains/System.keychain 2>/dev/null \
             | grep -qi "$CA_SHA1"; then
            echo "   CA already in the system keychain. Nothing to do."
        else
            echo "   Installing the CA into the system keychain (you will be asked for your password)..."
            sudo security add-trusted-cert -d -r trustRoot \
                -k /Library/Keychains/System.keychain "$CA_FILE"
            echo "   ✅ CA trusted by the system."
        fi
        ;;
    *)
        echo "   ⚠️  Unknown system. Install it manually: $CA_FILE"
        ;;
esac

# 4. NSS-based browsers (Firefox, Chrome on Linux) keep their own store and do
#    NOT read the system one. Added here when certutil is available, skipped
#    quietly otherwise.
add_to_nss() {
    local db="$1"
    [ -d "$db" ] || return 0
    certutil -D -n "$NSS_NICKNAME" -d "sql:$db" >/dev/null 2>&1 || true
    if certutil -A -n "$NSS_NICKNAME" -t "C,," -d "sql:$db" -i "$CA_FILE" >/dev/null 2>&1; then
        echo "   ✅ $db"
    fi
}

if command -v certutil >/dev/null 2>&1; then
    echo "🌐 Adding the CA to browsers (Firefox / Chrome)..."
    while read -r db; do
        [ -n "$db" ] && add_to_nss "$db"
    done <<EOF
$(nss_dbs)
EOF
else
    echo "🌐 certutil is not installed: skipping Firefox/Chrome."
    echo "   If you use Firefox, install 'nss' (Arch) or 'libnss3-tools' (Debian) and run again."
fi

echo ""
echo "🎉 Done. Restart your browser so it picks up the new CA."
echo "   Start the environment with: forge start"
