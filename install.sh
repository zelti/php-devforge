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

# shellcheck source=lib/compose.sh
. ./lib/compose.sh
# shellcheck source=lib/menu.sh
. ./lib/menu.sh
# shellcheck source=lib/version.sh
. ./lib/version.sh

ASSUME_YES=0; SKIP_CERT=0; SKIP_DNS=0; SKIP_LINK=0; FORCE=0
OPT_DOMAIN=""; OPT_DIR=""; OPT_PHP=""; OPT_DNS_PORT=""; OPT_IMAGES=""; OPT_PROFILES=""

usage() {
    cat <<EOF
PHP DevForge installer

Usage: $0 [OPTIONS]

  --domain=NAME         development domain (default: phpforge.dev)
  --projects-dir=PATH   where your projects live (default: ~/php-devforge)
  --php=84[,83,...]     PHP versions to install; the first is the default
                        (default: 84 -- each version is about 2 GB)
  --dns-port=N          port for the local DNS (default: first free one)
  --images=pull|build   use the published images, or build your own (default: pull)
  --profiles=a,b        databases and extras to enable, e.g. pg18,mariadb12,mail
  --force               take over containers another checkout started
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
        --force)          FORCE=1 ;;
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

# ss is Linux-only; without the fallback macOS reports every port free.
port_busy() {
    if command -v ss >/dev/null 2>&1; then
        ss -lntu 2>/dev/null | grep -qE "[:.]${1}[[:space:]]"
    else
        lsof -nP -iUDP:"$1" -iTCP:"$1" >/dev/null 2>&1
    fi
}

# A port our own dnsmasq holds is not a conflict: re-running the installer with
# the stack up used to walk DNS_PORT forward (5354 busy -> 5355 free), and with
# --skip-dns the resolver kept pointing at the old one, so the domain stopped
# resolving with nothing said.
port_free_for_us() {
    ! port_busy "$1" || [ "$1" = "$(dnsmasq_port)" ]
}

for p in 80 443; do
    if port_busy "$p"; then
        warn "Port $p is in use. Apache will not start until it is free."
        ss -lntup 2>/dev/null | grep -E "[:.]${p}[[:space:]]" | head -1 | sed 's/^/      /'
    else
        info "Port $p is free"
    fi
done

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

# Every checkout claims the same compose project, so an install here reconfigures
# containers another directory started. Checked with the requirements, before
# anything is written.
OWNER="$(active_dir)"
if [ -n "$OWNER" ] && [ "$OWNER" != "$(pwd)" ]; then
    echo ""
    warn "Containers for this project are already running, started from:"
    echo "      $OWNER"
    echo "    Installing here will reconfigure them: same containers, same"
    echo "    databases, your code in both folders untouched."
    echo "    To leave them alone:  cd $OWNER"
    echo ""
    if [ "$FORCE" -eq 1 ]; then
        warn "Continuing (--force)"
    elif [ ! -t 0 ]; then
        err "No terminal to ask on. Re-run with --force to take over."
        exit 1
    elif ! confirm "Take them over?"; then
        err "Left alone."
        exit 1
    fi
fi

# ---------- current values as defaults ----------
[ -f .env ] && { set -a +u; . ./.env; set +a -u; }

DEF_DOMAIN="${DEV_DOMAIN:-phpforge.dev}"
DEF_DIR="${PROJECTS_DIR:-$HOME/php-devforge}"
DEF_PHP="${PHP_VERSION:-84}"
DEF_DNS_PORT="${DNS_PORT:-}"
case "${IMAGE_MODE:-missing}" in build) DEF_IMAGES="build" ;; *) DEF_IMAGES="pull" ;; esac

valid_profile() { printf '%s\n' "$ALL_PROFILES" | grep -qx "$1"; }

title "Settings"
DOMAIN="${OPT_DOMAIN:-$(ask "Development domain?" "$DEF_DOMAIN")}"
PROJ="${OPT_DIR:-$(ask "Where will your projects live?" "$DEF_DIR")}"
PHP_LIST="$(php_versions)" || {
    err "Could not read the PHP versions from the compose file."
    echo "  Check it by hand:  docker compose config --services" >&2
    exit 1
}

# Versions already installed, so re-running the installer preselects them. Each
# is a compose profile: php84 in COMPOSE_PROFILES means PHP 8.4 is installed.
DEF_PHPS="$(printf '%s\n' "${COMPOSE_PROFILES:-}" | tr ',' '\n' \
            | sed -n 's/^php\([0-9][0-9]\)$/\1/p' | paste -sd, - || true)"
[ -n "$DEF_PHPS" ] || DEF_PHPS="$DEF_PHP"

# Which version to preselect as the default, given what was picked. Re-running
# the installer must not move the default: it answers every plain host name, and
# "the lowest one you happen to have" is not a decision anybody made.
default_php() { # picked versions -> the one to offer
    local picked="$1"
    printf '%s\n' $picked | grep -qx "$DEF_PHP" && { echo "$DEF_PHP"; return; }
    echo "${picked%% *}"
}

opts=()
while read -r v; do
    [ -n "$v" ] || continue
    opts+=("${v}	PHP $(echo "$v" | sed 's/\(.\)\(.\)/\1.\2/')")
done <<EOF
$PHP_LIST
EOF

# --php=84,83 installs both and makes 8.4 the default, so --php=84 keeps
# meaning what it always meant.
if [ -n "$OPT_PHP" ]; then
    PHPS="${OPT_PHP//,/ }"
    PHPV="${PHPS%% *}"
elif [ "$ASSUME_YES" -eq 1 ] || ! menu_available; then
    echo "  Available: $(printf '%s\n' "$PHP_LIST" | sed 's/\(.\)\(.\)/\1.\2/' | paste -sd' ' -)"
    echo "  Each version is a separate image of about 2 GB. Add more later with"
    echo "  'forge php on 8.3'."
    PHPS="$(ask "Which PHP versions?" "${DEF_PHPS//,/ }")"
    PHPS="${PHPS//,/ }"
    PHPV="$(ask "Which one is the default?" "$(default_php "$PHPS")")"
else
    echo "  Each version is a separate image of about 2 GB."
    PHPS="$(menu_many "PHP versions" "$DEF_PHPS" "${opts[@]}")"
    PHPS="${PHPS//,/ }"
    if [ "$(printf '%s\n' $PHPS | grep -c .)" -gt 1 ]; then
        sel=()
        for v in $PHPS; do sel+=("${v}	PHP $(echo "$v" | sed 's/\(.\)\(.\)/\1.\2/')"); done
        PHPV="$(menu_one "Default version (answers host names with no --pNN)" \
                "$(default_php "$PHPS")" "${sel[@]}")"
    else
        PHPV="${PHPS%% *}"
    fi
fi

PHPV="${PHPV//./}"

if [ -n "$OPT_IMAGES" ]; then
    IMAGES="$OPT_IMAGES"
elif [ "$ASSUME_YES" -eq 1 ] || ! menu_available; then
    echo "  Images: 'pull' downloads prebuilt ones (about a minute)."
    echo "          'build' compiles them here (about 15 minutes the first time),"
    echo "          which is what you want if you plan to edit docker-library/."
    IMAGES="$(ask "Pull the images or build them?" "$DEF_IMAGES")"
else
    IMAGES="$(menu_one "Images" "$DEF_IMAGES" \
        "pull	download prebuilt images, about a minute" \
        "build	compile them here, ~15 min the first time - to edit docker-library/")"
fi

# compose does not understand ~, so store an absolute path
PROJ="${PROJ/#\~/$HOME}"
case "$PROJ" in /*) ;; *) PROJ="$PWD/$PROJ" ;; esac

PHP_PROFILES=""
for v in $PHPS; do
    v="${v//./}"
    printf '%s\n' "$PHP_LIST" | grep -qx "$v" || {
        err "Unknown PHP version: $v"
        echo "  available: $(printf '%s\n' "$PHP_LIST" | paste -sd' ' -)" >&2
        exit 1
    }
    PHP_PROFILES="${PHP_PROFILES:+$PHP_PROFILES,}php$v"
done
[ -n "$PHP_PROFILES" ] || { err "Pick at least one PHP version."; exit 1; }

# Nothing answers a host name without a --pNN suffix otherwise.
printf '%s\n' $PHPS | tr -d . | grep -qx "$PHPV" || {
    err "The default (${PHPV}) is not among the versions you picked: $PHPS"
    exit 1
}
case "$IMAGES" in
    pull)  IMAGE_MODE_V="missing" ;;
    build) IMAGE_MODE_V="build" ;;
    *) err "Images must be 'pull' or 'build' (got: $IMAGES)"; exit 1 ;;
esac

# ---------- free DNS port ----------
if [ -n "$OPT_DNS_PORT" ]; then
    DNSP="$OPT_DNS_PORT"
elif [ -n "$DEF_DNS_PORT" ] && port_free_for_us "$DEF_DNS_PORT"; then
    DNSP="$DEF_DNS_PORT"
else
    echo "  Looking for a free DNS port..."
    DNSP=""
    for c in 5354 5355 5356 15353 15354; do
        if port_free_for_us "$c"; then
            echo "    $c free"
            DNSP="$c"; break
        else
            echo "    $c busy"
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

ALL_PROFILES="$(all_profiles)" || {
    err "Could not read the compose profiles."
    echo "  Check it by hand:  docker compose config --profiles" >&2
    exit 1
}

DB_PROFILES="$(printf '%s\n' "$ALL_PROFILES" | grep -E '^(pg|mariadb)[0-9]+$' || true)"

# The PHP versions live on the same COMPOSE_PROFILES line but were asked about
# above, so they must not come back as a default here.
DEF_EXTRAS="$(printf '%s\n' "${COMPOSE_PROFILES:-}" | tr ',' '\n' \
              | grep -vE '^php[0-9][0-9]$' | grep -v '^$' | paste -sd, - || true)"

echo "  Nothing is started unless you pick it. You can change this later with"
echo "  'forge db on|off <name>' and 'forge mail on|off'."
echo ""

PROFILES=""
if [ -n "$OPT_PROFILES" ]; then
    # Nobody is watching a scripted install, so an unknown name is an error here
    # rather than a warning that scrolls past.
    for d in ${OPT_PROFILES//,/ }; do
        valid_profile "$d" || {
            err "Unknown profile '$d'"
            echo "  available: $(printf '%s\n' "$ALL_PROFILES" | paste -sd' ' -)" >&2
            exit 1
        }
    done
    PROFILES="$OPT_PROFILES"
elif [ "$ASSUME_YES" -eq 1 ] || ! menu_available; then
    echo "  Databases (type the names, space separated):"
    for engine in "PostgreSQL:^pg[0-9]+$" "MariaDB:^mariadb[0-9]+$"; do
        names="$(printf '%s\n' "$DB_PROFILES" | grep -E "${engine#*:}" | paste -sd' ' - || true)"
        [ -n "$names" ] && printf '    %-12s %s\n' "${engine%%:*}" "$names"
    done
    echo ""
    DBS="$(ask "Which databases? (space separated, or none)" "${DEF_EXTRAS:-none}")"
    case "$DBS" in none|"") DBS="" ;; esac
    for d in ${DBS//,/ }; do
        [ -z "$d" ] && continue
        if valid_profile "$d"; then
            PROFILES="${PROFILES:+$PROFILES,}$d"
        else
            warn "Unknown database '$d', skipped"
            echo "         available: $(printf '%s\n' "$DB_PROFILES" | paste -sd' ' -)"
        fi
    done
    if confirm "Catch outgoing mail at mail.${DOMAIN}?"; then
        PROFILES="${PROFILES:+$PROFILES,}mail"
    fi
else
    echo "  reading the compose file..."
    compose_cache

    opts=()
    while read -r d; do
        [ -n "$d" ] || continue
        opts+=("${d}	$(profile_images "$d")")
    done <<EOF
$DB_PROFILES
EOF
    if valid_profile mail; then
        opts+=("mail	$(profile_images mail)  ->  mail.${DOMAIN}")
    fi

    PROFILES="$(menu_many "Optional services" "$DEF_EXTRAS" "${opts[@]}")"
fi

# The PHP versions lead the line, then the extras. Deduplicated because the two
# questions can overlap -- answering "mail" to the databases prompt and yes to the
# mail catcher used to write it twice.
PROFILES_LINE="$(printf '%s\n' "${PHP_PROFILES}${PROFILES:+,$PROFILES}" \
                 | tr ',' '\n' | grep -v '^$' | awk '!seen[$0]++' | paste -sd, - || true)"

# ---------- write .env ----------
title "Writing configuration"
[ -f .env ] && cp .env ".env.backup" && warn "Previous .env saved as .env.backup"

sed -e "s|^FORGE_VERSION=.*|FORGE_VERSION=$(cat VERSION 2>/dev/null || echo unknown)|" \
    -e "s|^DEV_DOMAIN=.*|DEV_DOMAIN=${DOMAIN}|" \
    -e "s|^PROJECTS_DIR=.*|PROJECTS_DIR=${PROJ}|" \
    -e "s|^PHP_VERSION=.*|PHP_VERSION=${PHPV}|" \
    -e "s|^DNS_PORT=.*|DNS_PORT=${DNSP}|" \
    -e "s|^PUID=.*|PUID=${PUID_V}|" \
    -e "s|^PGID=.*|PGID=${PGID_V}|" \
    -e "s|^IMAGE_MODE=.*|IMAGE_MODE=${IMAGE_MODE_V}|" \
    -e "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${PROFILES_LINE}|" \
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
ensure_custom_dirs

# Rewritten while it is still ours, so the note follows upgrades -- installers
# before per-version folders left advice that no longer matches. Ours means the
# header below, or the opening line every earlier version was written with, for
# the copies already out there. Edit the file and it stops being rewritten.
NOTE=custom/php.d/README.md
if [ ! -f "$NOTE" ] \
   || head -1 "$NOTE" | grep -q '^<!-- written by install.sh' \
   || head -1 "$NOTE" | grep -q '^Any `\.ini` file here is loaded by every PHP container'; then
    cat > "$NOTE" <<'INIEOF'
<!-- written by install.sh; delete this line and it will stop being rewritten -->

# PHP settings, without rebuilding anything

Any `.ini` file here is loaded by **every** PHP container:

    ; custom/php.d/99-mine.ini
    memory_limit = 512M
    upload_max_filesize = 100M

For one version only, put it in that version's folder instead. It is read after
this one, so it wins:

    ; custom/8.3/php.d/99-mine.ini
    memory_limit = 1G

Both are scanned in addition to the image's own conf.d, so nothing is shadowed
-- the Xdebug toggle keeps working. Run `forge restart` afterwards: a plain
restart does not re-read them.

The version folders hold more than `php.d` if you need it; everything under
`custom/<version>/` is mounted at `/usr/local/etc/php/version` in that container.
INIEOF
fi

# ---------- projects folder ----------
mkdir -p "$PROJ/projects" "$PROJ/sites"
# The welcome page lives in your projects folder but is ours to keep current:
# rewritten while it carries the header assets/welcome/index.php starts with, or
# while it is still the three-line printf() the first version shipped. Edit it and
# both markers go, and so does the rewriting.
WELCOME="$PROJ/sites/welcome/index.php"
welcome_is_ours() {
    [ -f "$WELCOME" ] || return 0
    head -1 "$WELCOME" | grep -q 'written by install.sh' && return 0
    head -3 "$WELCOME" | grep -q 'printf("PHP DevForge is running' && return 0
    return 1
}
if welcome_is_ours; then
    mkdir -p "$PROJ/sites/welcome"
    # The page shows a path you can type, which only this side knows.
    sed -e "s|__PROJECTS_DIR__|${PROJ}|" \
        -e "s|__FORGE_VERSION__|$(forge_version)|" \
        assets/welcome/index.php > "$WELCOME"
    # Beside the page, so it works with no network.
    cp logo.png "$PROJ/sites/welcome/logo.png"
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

# Skipping the DNS step is normal on a re-run, and it is exactly when the
# resolver can end up pointed at a port this .env no longer uses. Saying nothing
# there is how a machine ends up with the domain not resolving and no clue why.
dns_mismatch() {
    local asked
    asked="$(sed -n 's/^DNS=.*:\([0-9][0-9]*\) *$/\1/p' \
             /etc/systemd/resolved.conf.d/50-php-devforge.conf 2>/dev/null | head -1)"
    [ -z "$asked" ] && asked="$(sed -n 's/^port  *\([0-9][0-9]*\).*/\1/p' \
                                "/etc/resolver/${DOMAIN}" 2>/dev/null | head -1)"
    [ -n "$asked" ] && [ "$asked" != "$DNSP" ] && { echo "$asked"; return 0; }
    return 1
}

title "Local DNS"
if [ "$SKIP_DNS" -eq 1 ]; then
    warn "Skipped (--skip-dns). Run ./setup-local-dns.sh later."
elif confirm "Point *.${DOMAIN} at this machine now? (asks for your password)"; then
    ./setup-local-dns.sh
else
    warn "Skipped. Run ./setup-local-dns.sh later."
fi

if OLD_PORT="$(dns_mismatch)"; then
    warn "Your system still resolves *.${DOMAIN} through port ${OLD_PORT}, and this"
    echo "         configuration uses ${DNSP}. The domain will not resolve until they match:"
    echo "             ./setup-local-dns.sh"
    echo "         Check any time with:  forge dns status"
fi

title "Done"
# Shorten $HOME back to ~ so a long path does not bury the instructions.
SHORT_PROJ="${PROJ/#$HOME/\~}"
cat <<EOF
  Start it:      forge start
  Test page:     https://welcome.${DOMAIN}
  Everything:    forge help

  PHP $(printf '%s\n' $PHPS | tr -d . | sed 's/\(.\)\(.\)/\1.\2/' | commas) installed, $(echo "$PHPV" | sed 's/\(.\)\(.\)/\1.\2/') by default.
  Reach another one by suffixing the host: my-app--sites--p83.${DOMAIN}
  Add or drop versions later:  forge php list

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
