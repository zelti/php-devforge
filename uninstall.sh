#!/bin/bash
#
# Undoes ./install.sh, in reverse order: the docker project, the forge symlink,
# the local DNS entry, the trusted CA, and the files the installer generated.
#
# Your code and your databases are only removed if you say so. Everything it
# will touch is printed before anything is touched -- --dry-run stops there.
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

ASSUME_YES=0; FORCE=0; DRY=0; KEEP_IMAGES=0; RM_VOLUMES=0; RM_PROJECTS=0
LEFTOVER=0   # a step that needed sudo and did not get it

usage() {
    cat <<EOF
PHP DevForge uninstaller

Usage: $0 [OPTIONS]

  -n, --dry-run         print what would be removed, change nothing
  -y, --yes             do not ask; keeps your databases and your code
      --volumes         also delete the database volumes
      --projects        also delete your projects folder
      --keep-images     leave the docker images on disk
      --force           take over containers another checkout started
  -h, --help            this help

Never removed: your own docker-compose.local.yml and custom/php.d/ files, and
the checkout itself -- the last line tells you how to delete that.
EOF
}

for arg in "$@"; do
    case "$arg" in
        -n|--dry-run)  DRY=1 ;;
        -y|--yes)      ASSUME_YES=1 ;;
        --volumes)     RM_VOLUMES=1 ;;
        --projects)    RM_PROJECTS=1 ;;
        --keep-images) KEEP_IMAGES=1 ;;
        --force)       FORCE=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) err "Unknown option: $arg"; echo; usage; exit 1 ;;
    esac
done

# ---------- what is on this machine ----------
# .env supplies the projects folder and the domain. Missing is fine: a second
# run, or a checkout that never installed, still has containers to clean up.
[ -f .env ] && { set -a +u; . ./.env; set +a -u; }

PROJECT="${COMPOSE_PROJECT_NAME:-php-devforge}"
PROJ_DIR="${PROJECTS_DIR:-}"
LINK="$HOME/.local/bin/forge"

# Found by label rather than by reading the compose files: a service dropped
# from docker-compose.yml, or a COMPOSE_FILE that no longer lists the override,
# would otherwise leave containers and volumes behind.
by_label() { # containers|volumes
    case "$1" in
        containers) docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
                        --format '{{.Names}}' 2>/dev/null | sort ;;
        volumes)    docker volume ls --filter "label=com.docker.compose.project=$PROJECT" \
                        --format '{{.Name}}' 2>/dev/null | sort ;;
    esac
}

# Images this project's services use, that exist on this machine. Every profile
# is read: a version or database you turned off still left its image behind.
project_images() {
    local img
    _CW_PROFILES='*'
    local base
    while read -r img; do
        [ -n "$img" ] || continue
        # compose prints "andyshinn/dnsmasq"; docker images calls it ":latest".
        base="${img##*/}"
        case "$base" in *:*) ;; *) img="${img}:latest" ;; esac
        docker image inspect "$img" >/dev/null 2>&1 && echo "$img"
    done <<EOF
$(compose_with_env config --images | sort -u)
EOF
    _CW_PROFILES=""
    return 0
}

# What `docker images` reports, added up. Not `image inspect --format {{.Size}}`:
# with the containerd image store that returns the compressed size, and 1.7 GB
# where Docker Desktop shows 7 GB is a number nobody can act on. numfmt is
# GNU-only, so the arithmetic is awk's -- macOS ships bash 3.2 and BSD tools.
images_size() { # image... -> human size
    docker images --format '{{.Repository}}:{{.Tag}}	{{.Size}}' 2>/dev/null \
    | awk -F'\t' -v want=" $(printf '%s ' "$@")" '
        function tobytes(s,   n, u) {
            n = s + 0; u = s; sub(/^[0-9.]+/, "", u)
            if (u ~ /^kB/) return n * 1000
            if (u ~ /^MB/) return n * 1000000
            if (u ~ /^GB/) return n * 1000000000
            return n
        }
        index(want, " " $1 " ") { total += tobytes($2) }
        END { split("B kB MB GB TB", unit, " "); s = 1
              while (total >= 1000 && s < 5) { total /= 1000; s++ }
              printf "%.1f %s\n", total, unit[s] }'
}

volume_size() { docker system df -v 2>/dev/null | awk -v n="$1" '$1 == n { print $3 }'; }

run() { # echo under --dry-run, run otherwise
    if [ "$DRY" -eq 1 ]; then echo "      would run: $*"; return 0; fi
    "$@"
}

# "removed X" is a lie in a dry run, and the "would run" line above already
# said it. Every confirmation of something done goes through here.
say() { [ "$DRY" -eq 1 ] || info "$1"; }

confirm_no() { # prompt -> 0 yes / 1 no. Default no, and --yes keeps your data.
    local answer
    [ "$DRY" -eq 1 ] && return 1
    [ "$ASSUME_YES" -eq 1 ] && return 1
    [ -t 0 ] || return 1
    read -r -p "$(echo -e "  $1 [y/N]: ")" answer </dev/tty || answer=""
    case "${answer:-n}" in [yY]*) return 0 ;; *) return 1 ;; esac
}

confirm_go() {
    local answer
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || { err "No terminal to ask on. Use --yes."; exit 1; }
    read -r -p "$(echo -e "  $1 [y/N]: ")" answer </dev/tty || answer=""
    case "${answer:-n}" in [yY]*) return 0 ;; *) err "Nothing was changed."; exit 1 ;; esac
}

# ---------- what will happen ----------
title "PHP DevForge uninstall"

CONTAINERS="$(by_label containers)"
VOLUMES="$(by_label volumes)"
# shellcheck disable=SC2207  # the names cannot contain spaces
IMAGES=($(project_images))
IMG_SIZE="$(images_size "${IMAGES[@]+"${IMAGES[@]}"}")"

echo "  This will remove:"
if [ -n "$CONTAINERS" ]; then
    echo "    containers      $(printf '%s\n' "$CONTAINERS" | commas)"
else
    echo "    containers      none running or stopped"
fi
if [ "$KEEP_IMAGES" -eq 1 ]; then
    echo "    images          kept (--keep-images)"
elif [ "${#IMAGES[@]}" -gt 0 ]; then
    echo "    images          ${#IMAGES[@]}, $IMG_SIZE"
else
    echo "    images          none on this machine"
fi
[ -L "$LINK" ] && echo "    the command     $LINK"
[ -f .env ]    && echo "    generated files .env, certificates/, .caroot/"
echo "    system changes  the local DNS entry and the trusted CA   (asks for sudo)"

echo ""
echo "  Left alone unless you say otherwise:"
if [ -n "$VOLUMES" ]; then
    printf '%s\n' "$VOLUMES" | while read -r v; do
        [ -n "$v" ] || continue
        echo "    volume          $v  ($(volume_size "$v"))"
    done
else
    echo "    volumes         none"
fi
[ -n "$PROJ_DIR" ] && echo "    your code       $PROJ_DIR"
echo "    your own files  docker-compose.local.yml, custom/php.d/"
echo ""

# ---------- containers that belong to another checkout ----------
# Same rule as forge: this project name is shared by every clone, so the
# containers here may be someone else's. Removing them is not recoverable.
OWNER="$(active_dir)"
if [ -n "$OWNER" ] && [ "$OWNER" != "$PWD" ]; then
    warn "These containers were started from:"
    echo "      $OWNER"
    echo "    Uninstalling here removes them."
    echo "    To uninstall that one instead:  cd $OWNER && ./uninstall.sh"
    echo ""
    if [ "$FORCE" -eq 1 ]; then
        warn "Removing them anyway (--force)"
    elif [ "$DRY" -eq 1 ]; then
        warn "Would ask before removing them"
    elif [ ! -t 0 ]; then
        err "No terminal to ask on. Re-run with --force to remove them."
        exit 1
    elif ! confirm_no "Remove them?"; then
        err "Left alone."
        exit 1
    fi
fi

# ---------- the two questions ----------
if [ -n "$VOLUMES" ] && [ "$RM_VOLUMES" -eq 0 ]; then
    if confirm_no "Delete the database volumes too? Their data cannot be recovered"; then
        RM_VOLUMES=1
    fi
fi
if [ -n "$PROJ_DIR" ] && [ -d "$PROJ_DIR" ] && [ "$RM_PROJECTS" -eq 0 ]; then
    if confirm_no "Delete $PROJ_DIR and everything in it?"; then
        RM_PROJECTS=1
    fi
fi

if [ "$DRY" -ne 1 ]; then
    echo ""
    confirm_go "Go ahead?"
fi

# ---------- docker ----------
title "Containers, network and images"
DOWN=(down --remove-orphans)
[ "$KEEP_IMAGES" -eq 1 ] || DOWN+=(--rmi all)
[ "$RM_VOLUMES" -eq 1 ]  && DOWN+=(--volumes)
# Every profile, or the services you never enabled keep their containers.
( export COMPOSE_PROFILES='*'; run docker compose "${DOWN[@]}" ) || \
    warn "docker compose down did not finish cleanly; sweeping by label"

# The sweep is what makes this complete regardless of what the compose files
# currently describe.
printf '%s\n' "$(by_label containers)" | while read -r c; do
    [ -n "$c" ] || continue
    run docker rm -f "$c" >/dev/null && say "removed container $c"
done
if [ "$RM_VOLUMES" -eq 1 ]; then
    printf '%s\n' "$(by_label volumes)" | while read -r v; do
        [ -n "$v" ] || continue
        run docker volume rm "$v" >/dev/null && say "removed volume $v"
    done
fi
docker network inspect "${PROJECT}_default" >/dev/null 2>&1 && \
    run docker network rm "${PROJECT}_default" >/dev/null || true
say "docker project ${PROJECT} cleaned up"

# ---------- the forge command ----------
title "The forge command"
if [ -L "$LINK" ]; then
    TARGET="$(readlink -f "$LINK" 2>/dev/null || true)"
    if [ "$TARGET" = "$PWD/bin/forge" ]; then
        run rm -f "$LINK"
        say "removed $LINK"
    else
        warn "$LINK points at $TARGET, not here. Left alone."
    fi
else
    say "not linked; nothing to remove"
fi

# ---------- system changes ----------
# Before the files below: macOS needs DEV_DOMAIN from .env to find its resolver
# file, and the keychain entry is identified by the CA in .caroot.
# Neither is fatal: both need sudo, and failing to get it should not abandon
# the uninstall halfway with nothing said about what is left.
title "Local DNS"
run ./setup-local-dns.sh --remove || {
    warn "Could not remove the DNS entry. Run it yourself in a terminal:"
    echo "      cd $PWD && ./setup-local-dns.sh --remove"
    LEFTOVER=1
}

title "Trusted certificate authority"
run ./install_cert.sh --remove || {
    warn "Could not remove the CA. Run it yourself in a terminal:"
    echo "      cd $PWD && ./install_cert.sh --remove"
    LEFTOVER=1
}

# ---------- generated files ----------
title "Files the installer generated"
for f in .env .env.backup; do
    [ -f "$f" ] && { run rm -f "$f"; say "removed $f"; }
done
if [ -d certificates ]; then
    # .gitkeep is tracked; the certificates themselves are not.
    run find certificates -mindepth 1 ! -name .gitkeep -delete
    say "emptied certificates/"
fi
[ -d .caroot ] && { run rm -rf .caroot; say "removed .caroot/"; }

# ---------- your data ----------
if [ "$RM_PROJECTS" -eq 1 ] && [ -n "$PROJ_DIR" ] && [ -d "$PROJ_DIR" ]; then
    title "Your projects folder"
    run rm -rf "$PROJ_DIR"
    say "removed $PROJ_DIR"
fi

# ---------- what is left ----------
CACHE="$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null \
         | awk -F'\t' '$1 == "Build Cache" { print $2 }')"

if [ "$DRY" -eq 1 ]; then
    title "Nothing was changed"
    echo "  Run it without --dry-run to do it."
    exit 0
fi

title "Done"
echo "  Still on this machine:"
[ "$RM_VOLUMES" -eq 0 ] && [ -n "$VOLUMES" ] && \
    echo "    your databases  $(printf '%s\n' "$VOLUMES" | commas)"
[ "$RM_PROJECTS" -eq 0 ] && [ -n "$PROJ_DIR" ] && [ -d "$PROJ_DIR" ] && \
    echo "    your code       $PROJ_DIR"
echo "    your own files  docker-compose.local.yml, custom/php.d/"
if [ -n "$CACHE" ]; then
    echo ""
    echo "  Docker's build cache holds ${CACHE}. It is shared with everything else"
    echo "  you build on this machine, so it is not mine to clear:"
    echo "      docker builder prune"
fi
echo ""
echo "  The checkout itself is yours to delete:"
echo "      rm -rf $PWD"

# The CA and the DNS entry are the two things that outlive the checkout, so
# leaving without saying they are still there would be the worst outcome.
if [ "$LEFTOVER" -eq 1 ]; then
    echo ""
    warn "Some system changes are still in place -- see the lines above."
    exit 1
fi
