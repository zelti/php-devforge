# shellcheck shell=bash
# Keeping .env in step with .env.example.
#
# `forge update` does reconcile .env -- by re-running `./install.sh -y`, which
# also regenerates the certificates and reconfigures the system resolver, both
# with sudo. That is a lot of machine for "this release added a key", and it
# only covers people who update that way: a checkout moved with a plain
# `git pull` never calls it.
#
# One was. Its .env still read FORGE_VERSION=0.1.0 while forge printed 0.3.0,
# with no NGINX_FRONT_CONTROLLER -- added during the 0.1.0 series and unnoticed
# for two releases. It worked only because docker-compose.yml spells
# `${NGINX_FRONT_CONTROLLER:-auto}` at the point of use, and that fallback is
# the cost of having no migration: every new key needs one, at every use site,
# forever. So this runs from need_env -- every command, no sudo, nothing
# restarted, and silent unless it actually added something.
#
# .env.example is the authoritative list: install.sh builds .env by sed-ing this
# machine's answers into it. So there is no registry to keep up to date here --
# adding a key to the example is the whole registration, the same way a
# `profiles:` key is the whole registration of a service.
#
# What a comparison cannot derive is a rename (it would add the new key and
# orphan the old one, losing the value), a removal, or a value whose format
# changed. Those are what FORGE_VERSION is for, and the list of them stays short
# precisely because plain additions never enter it. There are none yet.
#
# Written for bash 3.2, which is what macOS ships: no associative arrays, so
# keys travel as newline-separated strings.

# What install.sh works out for this machine. .env.example carries a
# placeholder for each -- `PROJECTS_DIR=${HOME}/php-devforge` is a hole, not an
# answer -- so one of these missing means the file is broken rather than old,
# and saying so beats inventing a value.
#
# FORGE_VERSION is deliberately not in this list: a .env written before the
# stamp existed has none, and that is exactly the old file this is for.
ENV_ANSWER_KEYS='DEV_DOMAIN
PROJECTS_DIR
PHP_VERSION
DNS_PORT
PUID
PGID
IMAGE_MODE
COMPOSE_PROFILES'

# The keys a file declares, in the order it lists them.
env_keys() { # file
    sed -ne 's/^\([A-Z_][A-Z_0-9]*\)=.*/\1/p' "$1"
}

# A key's value, empty when absent. First match wins, the way a shell sourcing
# the file would take it.
env_value() { # file key
    sed -ne "s/^$2=//p" "$1" | head -1
}

env_has() { # file key
    grep -q "^$2=" "$1"
}

in_list() { # needle list
    printf '%s\n' "$2" | grep -qxF "$1"
}

# Which of the example's keys this .env does not have, in the example's order.
env_missing_keys() {
    local key
    for key in $(env_keys .env.example); do
        env_has .env "$key" || echo "$key"
    done
}

# Keys in .env that the example does not know: the user's own, which are kept.
env_extra_keys() {
    local key
    for key in $(env_keys .env); do
        env_has .env.example "$key" || echo "$key"
    done
}

# Rebuilt in the example's order and with its comments, carrying every value
# this .env already had. Stapling a new key to the end would work; this also
# brings back the comment that explains it, and the ordering, both of which
# drift over a couple of releases.
_env_rebuild() { # target-version -> the new file on stdout
    local line key extra
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            [A-Z_]*=*)
                key="${line%%=*}"
                if [ "$key" = FORGE_VERSION ]; then
                    printf 'FORGE_VERSION=%s\n' "$1"
                elif env_has .env "$key"; then
                    printf '%s=%s\n' "$key" "$(env_value .env "$key")"
                else
                    printf '%s\n' "$line"
                fi
                ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < .env.example

    extra="$(env_extra_keys)"
    [ -n "$extra" ] || return 0
    echo
    echo "# Not in .env.example: your own keys, kept as they were."
    for key in $extra; do
        printf '%s=%s\n' "$key" "$(env_value .env "$key")"
    done
}

migrate_env() {
    [ -f .env ] && [ -f .env.example ] || return 0

    local target stamp missing broken key rebuilt
    target="$(forge_version_number)"
    stamp="$(env_value .env FORGE_VERSION)"
    missing="$(env_missing_keys)"

    # The common case, and it must cost one file read: nothing to add and the
    # stamp already current.
    [ -z "$missing" ] && [ "$stamp" = "$target" ] && return 0

    broken=""
    for key in $missing; do
        in_list "$key" "$ENV_ANSWER_KEYS" && broken="$broken $key"
    done
    if [ -n "$broken" ]; then
        err "Your .env is missing values only the installer can work out:"
        for key in $broken; do echo "      $key" >&2; done
        echo "    These are answers, not defaults. Re-run the installer -- it" >&2
        echo "    offers your current values as the defaults:  ./install.sh" >&2
        exit 1
    fi

    # Built in memory and written through the existing file, not moved over it:
    # .env keeps its own permissions without a `chmod --reference` macOS does
    # not have, and a crash cannot leave a half-written .env or a stray temp
    # file next to it.
    rebuilt="$(_env_rebuild "$target")"
    cp .env .env.backup
    printf '%s\n' "$rebuilt" > .env

    [ -n "$missing" ] || return 0
    warn ".env was written by ${stamp:-a version before the stamp existed}; this is $target."
    echo "    Added, with the default from .env.example:"
    for key in $missing; do echo "      $key"; done
    echo "    Your own values are untouched. The previous file is .env.backup"
}
