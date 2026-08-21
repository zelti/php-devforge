#!/bin/bash
#
# Sets up PHP DevForge on this machine: writes .env, creates the projects
# folder, and optionally generates certificates and configures local DNS.
#
# Safe to re-run: existing values in .env become the defaults.
#
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
title() { echo -e "\n${BLUE}$1${NC}"; }

ASSUME_YES=0; SKIP_CERT=0; SKIP_DNS=0
OPT_DOMAIN=""; OPT_DIR=""; OPT_PHP=""; OPT_DNS_PORT=""

usage() {
    cat <<EOF
PHP DevForge installer

Usage: $0 [OPTIONS]

  --domain=NAME         development domain (default: phpforge.dev)
  --projects-dir=PATH   where your projects live (default: ~/php-devforge)
  --php=83|84           default PHP version (default: 84)
  --dns-port=N          port for the local DNS (default: first free one)
  --skip-cert           do not generate certificates
  --skip-dns            do not touch the system DNS
  -y, --yes             accept every default, ask nothing
  -h, --help            this help

Re-running is safe: your current .env supplies the defaults.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --domain=*)       OPT_DOMAIN="${arg#*=}" ;;
        --projects-dir=*) OPT_DIR="${arg#*=}" ;;
        --php=*)          OPT_PHP="${arg#*=}" ;;
        --dns-port=*)     OPT_DNS_PORT="${arg#*=}" ;;
        --skip-cert)      SKIP_CERT=1 ;;
        --skip-dns)       SKIP_DNS=1 ;;
        -y|--yes)         ASSUME_YES=1 ;;
        -h|--help)        usage; exit 0 ;;
        *) err "Unknown option: $arg"; echo; usage; exit 1 ;;
    esac
done

if [ ! -t 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    err "No terminal to ask questions on. Use --yes (plus --skip-cert / --skip-dns)."
    exit 1
fi

# ---------- checks ----------
title "Checking requirements"

if ! command -v docker >/dev/null 2>&1; then
    err "Docker is not installed."; exit 1
fi
if ! docker info >/dev/null 2>&1; then
    err "Docker is installed but not running. Start it and try again."; exit 1
fi
info "Docker is running"

if ! docker compose version >/dev/null 2>&1; then
    err "'docker compose' (v2) not available. Update Docker."; exit 1
fi
info "docker compose v2 available"

port_busy() { ss -lntu 2>/dev/null | grep -qE "[:.]$1[[:space:]]"; }

for p in 80 443; do
    if port_busy "$p"; then
        warn "Port $p is in use. Apache will not start until it is free."
        ss -lntup 2>/dev/null | grep -E "[:.]$p[[:space:]]" | head -1 | sed 's/^/      /'
    else
        info "Port $p is free"
    fi
done

# ---------- current values as defaults ----------
[ -f .env ] && { set -a +u; . ./.env; set +a -u; }

DEF_DOMAIN="${DEV_DOMAIN:-phpforge.dev}"
DEF_DIR="${PROJECTS_DIR:-$HOME/php-devforge}"
DEF_PHP="${PHP_VERSION:-84}"
DEF_DNS_PORT="${DNS_PORT:-}"

ask() { # prompt, default -> answer on stdout
    local prompt="$1" default="$2" answer
    if [ "$ASSUME_YES" -eq 1 ]; then echo "$default"; return; fi
    read -r -p "$(echo -e "  ${prompt} [${default}]: ")" answer </dev/tty || answer=""
    echo "${answer:-$default}"
}

confirm() { # prompt -> 0 yes / 1 no
    local answer
    if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
    read -r -p "$(echo -e "  $1 [Y/n]: ")" answer </dev/tty || answer=""
    case "${answer:-y}" in [nN]*) return 1 ;; *) return 0 ;; esac
}

title "Settings"
DOMAIN="${OPT_DOMAIN:-$(ask "Development domain?" "$DEF_DOMAIN")}"
PROJ="${OPT_DIR:-$(ask "Where will your projects live?" "$DEF_DIR")}"
PHPV="${OPT_PHP:-$(ask "Default PHP version (83 or 84)?" "$DEF_PHP")}"

# compose does not understand ~, so store an absolute path
PROJ="${PROJ/#\~/$HOME}"
case "$PROJ" in /*) ;; *) PROJ="$PWD/$PROJ" ;; esac

case "$PHPV" in 83|84) ;; *) err "PHP version must be 83 or 84 (got: $PHPV)"; exit 1 ;; esac

# ---------- free DNS port ----------
if [ -n "$OPT_DNS_PORT" ]; then
    DNSP="$OPT_DNS_PORT"
elif [ -n "$DEF_DNS_PORT" ] && ! port_busy "$DEF_DNS_PORT"; then
    DNSP="$DEF_DNS_PORT"
else
    echo "  Looking for a free DNS port..."
    DNSP=""
    for c in 5354 5355 5356 15353 15354; do
        if port_busy "$c"; then
            echo "    $c busy"
        else
            echo "    $c free"
            DNSP="$c"; break
        fi
    done
    [ -z "$DNSP" ] && { err "No free port found. Pass --dns-port=N."; exit 1; }
fi
info "DNS port: $DNSP"

PUID_V="$(id -u)"; PGID_V="$(id -g)"
info "Your user: uid $PUID_V, gid $PGID_V"

# ---------- write .env ----------
title "Writing configuration"
[ -f .env ] && cp .env ".env.backup" && warn "Previous .env saved as .env.backup"

sed -e "s|^DEV_DOMAIN=.*|DEV_DOMAIN=${DOMAIN}|" \
    -e "s|^PROJECTS_DIR=.*|PROJECTS_DIR=${PROJ}|" \
    -e "s|^PHP_VERSION=.*|PHP_VERSION=${PHPV}|" \
    -e "s|^DNS_PORT=.*|DNS_PORT=${DNSP}|" \
    -e "s|^PUID=.*|PUID=${PUID_V}|" \
    -e "s|^PGID=.*|PGID=${PGID_V}|" \
    .env.example > .env
info ".env written"

# ---------- projects folder ----------
mkdir -p "$PROJ/projects" "$PROJ/sites"
if [ ! -e "$PROJ/sites/welcome/index.php" ]; then
    mkdir -p "$PROJ/sites/welcome"
    cat > "$PROJ/sites/welcome/index.php" <<'PHP'
<?php
printf("PHP DevForge is running.\n\nPHP %s\nHost %s\nFile %s\n",
    PHP_VERSION, $_SERVER['HTTP_HOST'] ?? 'cli', __FILE__);
PHP
fi
info "Projects folder: $PROJ"
echo "      projects/  your code"
echo "      sites/     symlinks to each project's public folder"
echo "      sites/welcome  a test page"

# ---------- optional steps ----------
title "Certificates"
if [ "$SKIP_CERT" -eq 1 ]; then
    warn "Skipped (--skip-cert). Run ./install_cert.sh when you want HTTPS."
elif confirm "Generate the HTTPS certificates now?"; then
    ./install_cert.sh
else
    warn "Skipped. Run ./install_cert.sh when you want HTTPS."
fi

title "Local DNS"
if [ "$SKIP_DNS" -eq 1 ]; then
    warn "Skipped (--skip-dns). Run ./setup-local-dns.sh later."
elif confirm "Point *.${DOMAIN} at this machine now? (asks for your password)"; then
    ./setup-local-dns.sh
else
    warn "Skipped. Run ./setup-local-dns.sh later."
fi

title "Done"
cat <<EOF
  Start it:      docker compose up -d
  Shortcuts:     source $(pwd)/aliases.bash
  Test page:     https://welcome--sites.${DOMAIN}

  Put your code in $PROJ/projects and link it from $PROJ/sites:
      ln -s ../projects/my-app/public $PROJ/sites/my-app
      -> https://my-app--sites.${DOMAIN}

  Symlinks must point inside $PROJ, or the containers cannot follow them.
EOF
