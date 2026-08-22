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

ASSUME_YES=0; SKIP_CERT=0; SKIP_DNS=0; SKIP_LINK=0
OPT_DOMAIN=""; OPT_DIR=""; OPT_PHP=""; OPT_DNS_PORT=""; OPT_IMAGES=""; OPT_PROFILES=""

usage() {
    cat <<EOF
PHP DevForge installer

Usage: $0 [OPTIONS]

  --domain=NAME         development domain (default: phpforge.dev)
  --projects-dir=PATH   where your projects live (default: ~/php-devforge)
  --php=83|84           default PHP version (default: 84)
  --dns-port=N          port for the local DNS (default: first free one)
  --images=pull|build   use the published images, or build your own (default: pull)
  --profiles=a,b        databases and extras to enable, e.g. pg18,mariadb12,mail
  --skip-link           do not put `forge` on your PATH
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
        --images=*)       OPT_IMAGES="${arg#*=}" ;;
        --profiles=*)     OPT_PROFILES="${arg#*=}" ;;
        --skip-link)      SKIP_LINK=1 ;;
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

port_busy() { ss -lntu 2>/dev/null | grep -qE "[:.]${1}[[:space:]]"; }

for p in 80 443; do
    if port_busy "$p"; then
        warn "Port $p is in use. Apache will not start until it is free."
        ss -lntup 2>/dev/null | grep -E "[:.]${p}[[:space:]]" | head -1 | sed 's/^/      /'
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
case "${IMAGE_MODE:-missing}" in build) DEF_IMAGES="build" ;; *) DEF_IMAGES="pull" ;; esac

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
PHPV="${OPT_PHP:-$(ask "Default PHP version (83, 84 or 85)?" "$DEF_PHP")}"
echo "  Images: 'pull' downloads prebuilt ones (about a minute)."
echo "          'build' compiles them here (about 15 minutes the first time),"
echo "          which is what you want if you plan to edit docker-library/."
IMAGES="${OPT_IMAGES:-$(ask "Pull the images or build them?" "$DEF_IMAGES")}"

# compose does not understand ~, so store an absolute path
PROJ="${PROJ/#\~/$HOME}"
case "$PROJ" in /*) ;; *) PROJ="$PWD/$PROJ" ;; esac

case "$PHPV" in 83|84|85) ;; *) err "PHP version must be 83, 84 or 85 (got: $PHPV)"; exit 1 ;; esac
case "$IMAGES" in
    pull)  IMAGE_MODE_V="missing" ;;
    build) IMAGE_MODE_V="build" ;;
    *) err "Images must be 'pull' or 'build' (got: $IMAGES)"; exit 1 ;;
esac

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

# ---------- databases and mail ----------
# Both are compose profiles, so this just builds COMPOSE_PROFILES.
title "Databases and mail"
echo "  Nothing is started unless you pick it. You can change this later with"
echo "  'forge db on|off <name>' and 'forge mail on|off'."
echo ""
echo "  Databases available: $(docker compose config --profiles 2>/dev/null | grep -E '^(pg|mariadb)' | tr '\n' ' ')"

PROFILES=""
if [ -n "$OPT_PROFILES" ]; then
    PROFILES="$OPT_PROFILES"
else
    DBS="$(ask "Which databases? (space separated, or none)" "${COMPOSE_PROFILES:-none}")"
    case "$DBS" in none|"") DBS="" ;; esac
    for d in $DBS; do
        d="${d//,/}"
        [ -z "$d" ] && continue
        if docker compose config --profiles 2>/dev/null | grep -qx "$d"; then
            PROFILES="${PROFILES:+$PROFILES,}$d"
        else
            warn "Unknown database '$d', skipped"
        fi
    done
    if confirm "Catch outgoing mail at mail.${DOMAIN}?"; then
        PROFILES="${PROFILES:+$PROFILES,}mail"
    fi
fi

# ---------- write .env ----------
title "Writing configuration"
[ -f .env ] && cp .env ".env.backup" && warn "Previous .env saved as .env.backup"

sed -e "s|^DEV_DOMAIN=.*|DEV_DOMAIN=${DOMAIN}|" \
    -e "s|^PROJECTS_DIR=.*|PROJECTS_DIR=${PROJ}|" \
    -e "s|^PHP_VERSION=.*|PHP_VERSION=${PHPV}|" \
    -e "s|^DNS_PORT=.*|DNS_PORT=${DNSP}|" \
    -e "s|^PUID=.*|PUID=${PUID_V}|" \
    -e "s|^PGID=.*|PGID=${PGID_V}|" \
    -e "s|^IMAGE_MODE=.*|IMAGE_MODE=${IMAGE_MODE_V}|" \
    -e "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${PROFILES}|" \
    .env.example > .env
info ".env written"

# ---------- customisation points ----------
# COMPOSE_FILE lists docker-compose.local.yml, and compose errors on a file that
# is not there, so it has to exist even when empty.
if [ ! -f docker-compose.local.yml ]; then
    cat > docker-compose.local.yml <<'LOCALEOF'
# Your own services and overrides. Ignored by git, so `git pull` never conflicts
# with what you put here.
#
# services:
#   redis:
#     image: redis:7-alpine
#     ports:
#       - 127.0.0.1:6379:6379
LOCALEOF
    info "docker-compose.local.yml created (yours, ignored by git)"
fi

# Listed only once the file exists, since compose errors on a missing one.
# Anchored to the setting: the comment above it in .env.example mentions the file too.
if ! grep -q '^COMPOSE_FILE=.*docker-compose\.local\.yml' .env 2>/dev/null; then
    sed -i 's|^COMPOSE_FILE=\(.*\)$|COMPOSE_FILE=\1:docker-compose.local.yml|' .env
fi

mkdir -p custom/php.d
if [ ! -f custom/php.d/README.md ]; then
    cat > custom/php.d/README.md <<'INIEOF'
Any `.ini` file here is loaded by every PHP container. No rebuild needed: edit,
then `docker compose up -d --force-recreate php84dev`.

    ; custom/php.d/99-mine.ini
    memory_limit = 512M
    upload_max_filesize = 100M

This is scanned in addition to the image's own conf.d, so it does not shadow
anything -- the Xdebug toggle keeps working.
INIEOF
fi

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
# ---------- forge on PATH ----------
# A symlink, not a copy, so `git pull` updates the command too.
title "The forge command"
if [ "$SKIP_LINK" -eq 1 ]; then
    warn "Skipped (--skip-link). Run it as $(pwd)/bin/forge"
else
    BIN_DIR="$HOME/.local/bin"
    LINK="$BIN_DIR/forge"
    if [ -e "$LINK" ] && [ "$(readlink -f "$LINK")" != "$(readlink -f bin/forge)" ]; then
        warn "$LINK exists and points somewhere else. Left alone."
        warn "Run this project's copy as $(pwd)/bin/forge"
    else
        mkdir -p "$BIN_DIR"
        ln -sfn "$(pwd)/bin/forge" "$LINK"
        info "forge linked into $BIN_DIR"
        case ":$PATH:" in
            *":$BIN_DIR:"*) info "$BIN_DIR is on your PATH: just type 'forge'" ;;
            *) warn "$BIN_DIR is not on your PATH yet. Add this to your shell profile:"
               echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
        esac
    fi
fi

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
# Shorten $HOME back to ~ so a long path does not bury the instructions.
SHORT_PROJ="${PROJ/#$HOME/\~}"
cat <<EOF
  Start it:      forge start
  Test page:     https://welcome--sites.${DOMAIN}
  Everything:    forge help

  Your projects live in ${SHORT_PROJ}

      cd ${SHORT_PROJ}
      ln -s ../projects/my-app/public sites/my-app
      -> https://my-app--sites.${DOMAIN}

  Symlinks must point inside that folder: the containers see nothing else.

  Images are set to '${IMAGES}'. Customise without touching docker-library/,
  so upgrades never conflict:
      custom/php.d/*.ini          PHP settings, no rebuild
      docker-compose.local.yml    your own services and overrides
EOF
