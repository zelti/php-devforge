# shellcheck shell=bash
# Reading the compose files. Sourced by install.sh and bin/forge, both of which
# cd to the repo root first, so the relative paths below hold.
#
# Nothing here enumerates services, versions or profiles: adding php86dev or a
# postgres 19 profile to the compose files is the only change any of it needs.

_COMPOSE_BASE_IMAGES=""
_COMPOSE_BASE_SERVICES=""

# Compose cannot parse the files with an empty PHP_VERSION: `depends_on:
# php${PHP_VERSION}dev` becomes `phpdev`, a service that does not exist, and the
# project is rejected. The installer asks its questions before .env is written,
# so fall back to .env.example. A real .env wins: a local override file may
# define more.
# COMPOSE_PROFILES is deliberately cleared: the diffs below compare a profile
# against the default set, and inheriting whatever .env already enables would
# put those services on both sides. `forge profile off pg18` would then report
# that pg18 starts nothing. Callers ask for a profile with --profile.
# _CW_PROFILES overrides that for the one caller that needs the opposite:
# php_versions() must list versions that are not installed.
_CW_PROFILES=""

compose_with_env() {
    local f out
    for f in .env .env.example; do
        [ -f "$f" ] || continue
        # shellcheck source=/dev/null
        out="$(set -a +u; . "./$f"; set +a -u
               export COMPOSE_PROFILES="$_CW_PROFILES"
               docker compose "$@" 2>/dev/null)"
        [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    done
    return 1
}

# `paste -d', '` alternates the two delimiters, so a third item joins with a
# space instead of a comma: 8.3,8.4 8.5.
commas() { paste -sd, - | sed 's/,/, /g'; }

all_profiles() { compose_with_env config --profiles | sort; }

# Every version the compose files define, installed or not: '*' enables all
# profiles for this read only. The installer offers these, and `forge php on`
# accepts them.
php_versions() {
    local out
    _CW_PROFILES='*'
    out="$(compose_with_env config --services)"
    _CW_PROFILES=""
    printf '%s\n' "$out" | sed -n 's/^php\([0-9][0-9]\)dev$/\1/p' | sort
}

# Fills the base sets once. Callers that loop should call this first: a command
# substitution inherits these, so the per-profile diffs below stop re-reading it.
compose_cache() {
    [ -n "$_COMPOSE_BASE_IMAGES" ]   || _COMPOSE_BASE_IMAGES="$(compose_with_env config --images | sort)"
    [ -n "$_COMPOSE_BASE_SERVICES" ] || _COMPOSE_BASE_SERVICES="$(compose_with_env config --services | sort)"
}

# What a profile adds on top of the default set, so the tooling describes itself.
_profile_extra() { # images|services, profile
    local what="$1" profile="$2" base
    compose_cache
    case "$what" in
        images)   base="$_COMPOSE_BASE_IMAGES" ;;
        services) base="$_COMPOSE_BASE_SERVICES" ;;
    esac
    comm -13 <(printf '%s\n' "$base") \
             <(compose_with_env --profile "$profile" config "--$what" | sort)
}

# pg18 -> postgres:18 ; search -> elasticsearch:8.14.2, kibana:8.14.2
# The registry and namespace are trimmed: the tag carries the version, which is
# the part worth reading, and a full ghcr.io/... path wrecks a table column.
profile_images() { _profile_extra images "$1" | sed 's|.*/||' | commas; }

# pg18 -> postgres18dev ; search -> es8143dev, kibana  (one per line)
profile_services() { _profile_extra services "$1"; }

# Which directory the running containers came from, or nothing when none are
# running. COMPOSE_PROJECT_NAME is a fixed literal, so every checkout claims the
# same project and containers started elsewhere look like ours; compose records
# the origin on each one.
#
# Goes through compose_with_env so the installer can call it too: without .env
# the project name would fall back to the directory name and find nothing.
active_dir() {
    local id
    id="$(compose_with_env ps -q 2>/dev/null | head -1)" || return 0
    [ -n "$id" ] || return 0
    docker inspect "$id" \
        --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null
}
