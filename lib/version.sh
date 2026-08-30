# shellcheck shell=bash
# What version of PHP DevForge this checkout is. Sourced by bin/forge and
# install.sh, both of which cd to the repo root first.
#
# A plain file rather than JSON: everything here is shell, and reading one line
# should not need jq. The git sha is appended when there is one -- between two
# releases everybody is on the same number, and the commit is what differs.

forge_version() {
    local v sha
    v="$(cat VERSION 2>/dev/null || echo unknown)"
    sha="$(git describe --always --dirty 2>/dev/null || true)"
    [ -n "$sha" ] && v="$v ($sha)"
    printf '%s\n' "$v"
}
