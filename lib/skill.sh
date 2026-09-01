# shellcheck shell=bash
# Hooking skills/php-devforge/SKILL.md into the AI agents installed on this
# machine. Sourced by bin/forge, install.sh and uninstall.sh, all of which cd to
# the repo root first and define info/warn/err.
#
# Two shapes, because agents load instructions differently:
#
#   skill  a symlink into the agent's skills folder. Loaded on demand, so it can
#          be the whole file, and `git pull` updates it.
#   block  a delimited section inside the agent's global instructions file,
#          which is in context for every session it opens. That one gets a short
#          summary and a path, not 190 lines.
#
# A target is only offered when its config directory already exists: a missing
# ~/.codex means that tool is not installed, and creating one leaves litter
# behind for a tool that will never read it.

SKILL_SRC="skills/php-devforge"
SKILL_START="<!-- php-devforge:start -->"
SKILL_END="<!-- php-devforge:end -->"

_skill_target() { # name kind path detect-dir
    [ -d "$4" ] && printf '%s\t%s\t%s\n' "$1" "$2" "$3"
    return 0
}

# name<TAB>kind<TAB>path for every agent found. Adding one is a line here.
skill_targets() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    _skill_target claude   skill "$HOME/.claude/skills/php-devforge" "$HOME/.claude"
    _skill_target codex    block "$HOME/.codex/AGENTS.md"            "$HOME/.codex"
    _skill_target gemini   block "$HOME/.gemini/GEMINI.md"           "$HOME/.gemini"
    _skill_target opencode block "$cfg/opencode/AGENTS.md"           "$cfg/opencode"
}

skill_path() { printf '%s/%s/SKILL.md\n' "$PWD" "$SKILL_SRC"; }

# The short form. Values come from .env so the paths are this machine's, and
# fall back to the defaults when it has not been written yet.
skill_summary() {
    local domain proj
    domain="$(sed -ne 's/^DEV_DOMAIN=//p' .env 2>/dev/null)"; domain="${domain:-phpforge.dev}"
    proj="$(sed -ne 's/^PROJECTS_DIR=//p' .env 2>/dev/null)"; proj="${proj:-$HOME/php-devforge}"
    cat <<EOF
## PHP DevForge (local PHP environment)

PHP projects under \`${proj/#$HOME/\~}\` are served by Docker at
\`https://<name>.${domain}\`. Run project commands through \`forge\` on the host,
never \`docker exec\`: it picks the container, translates the path (the projects
folder is mounted elsewhere inside) and uses a login shell (node and pnpm come
from nvm and are missing otherwise).

    forge run composer install                 # in the directory you are in
    forge run pnpm run build
    forge run -C projects/my-app php artisan migrate
    forge shell                                # interactive
    forge status                               # domain, versions, what runs
    forge logs                                 # where PHP errors go

Code is live: never restart after editing PHP or JS. From your code the
databases are \`postgres18dev:5432\` and \`mariadb12dev:3306\`, and SMTP is
\`mailpit:1025\`.

Full reference: $(skill_path)
EOF
}

# Our block, plus the single blank line we insert before it, removed. Exactly
# reversible, so turning the skill off restores the file byte for byte.
_skill_strip() { # file -> stdout
    awk -v s="$SKILL_START" -v e="$SKILL_END" '
        index($0, s) { blank = 0; drop = 1; stripped = 1; next }
        drop         { if (index($0, e)) drop = 0; next }
        {
            if (blank) print ""
            blank = ($0 == "")
            if (!blank) print
        }
        END { if (blank && !stripped) print "" }
    ' "$1"
}

_skill_block_write() { # file
    local file="$1" tmp
    tmp="$(mktemp)"
    if [ -f "$file" ]; then
        _skill_strip "$file" > "$tmp"
        [ -s "$tmp" ] && printf '\n' >> "$tmp"
    fi
    { printf '%s\n' "$SKILL_START"; skill_summary; printf '%s\n' "$SKILL_END"; } >> "$tmp"
    mv "$tmp" "$file"
}

_skill_block_remove() { # file
    local file="$1" tmp
    [ -f "$file" ] || return 0
    grep -qF "$SKILL_START" "$file" || return 0
    tmp="$(mktemp)"
    _skill_strip "$file" > "$tmp"
    # A file that held nothing but our block was ours to create, so it goes too.
    if [ -s "$tmp" ]; then mv "$tmp" "$file"; else rm -f "$tmp" "$file"; fi
}

# 0 when the target is hooked up, 1 when it is not.
skill_is_on() { # kind path
    case "$1" in
        skill) [ -L "$2" ] && [ "$(readlink -f "$2")" = "$(readlink -f "$SKILL_SRC")" ] ;;
        block) [ -f "$2" ] && grep -qF "$SKILL_START" "$2" ;;
    esac
}

skill_on() { # [name] -> 0 if anything was hooked up
    local want="${1:-}" name kind path did=0
    while IFS=$'\t' read -r name kind path; do
        [ -n "$name" ] || continue
        [ -z "$want" ] || [ "$want" = "$name" ] || continue
        if [ "$kind" = "skill" ] && [ -e "$path" ] && [ ! -L "$path" ]; then
            warn "$path exists and is not a link. Left alone."
            continue
        fi
        case "$kind" in
            skill) mkdir -p "$(dirname "$path")"; ln -sfn "$PWD/$SKILL_SRC" "$path" ;;
            block) _skill_block_write "$path" ;;
        esac
        info "$name: $path"
        did=1
    done <<EOF
$(skill_targets)
EOF
    [ "$did" -eq 1 ]
}

skill_off() { # [name]
    local want="${1:-}" name kind path
    while IFS=$'\t' read -r name kind path; do
        [ -n "$name" ] || continue
        [ -z "$want" ] || [ "$want" = "$name" ] || continue
        skill_is_on "$kind" "$path" || continue
        case "$kind" in
            skill) rm -f "$path" ;;
            block) _skill_block_remove "$path" ;;
        esac
        info "$name: removed from $path"
    done <<EOF
$(skill_targets)
EOF
    return 0
}
