# shellcheck shell=bash
# What version of PHP DevForge this checkout is. Sourced by bin/forge and
# install.sh, both of which cd to the repo root first.
#
# A plain file rather than JSON: everything here is shell, and reading one line
# should not need jq. The git sha is appended when there is one -- between two
# releases everybody is on the same number, and the commit is what differs.

# The number alone. What .env is stamped with, and what a migration compares
# against: the sha below is for a bug report, not for deciding anything.
forge_version_number() {
    cat VERSION 2>/dev/null || echo unknown
}

forge_version() {
    local v sha
    v="$(forge_version_number)"
    sha="$(git describe --always --dirty 2>/dev/null || true)"
    [ -n "$sha" ] && v="$v ($sha)"
    printf '%s\n' "$v"
}
