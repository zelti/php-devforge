# shellcheck shell=bash
# Arrow-key menus for the installer. Meant to be sourced, never run.
#
#   menu_one  <title> <default>         <item>...  -> the chosen value
#   menu_many <title> <preselected-csv> <item>...  -> chosen values, comma separated
#
# Items are "value<TAB>description". Drawing goes to /dev/tty and only the result
# reaches stdout, so callers can capture it with $(...) — the same split ask()
# already uses in install.sh.
#
# Written for bash 3.2, which is what macOS ships: no associative arrays, no
# mapfile, no ${var,,}, and integer read timeouts only.

_MENU_ITEMS=()
_MENU_SEL=()

# Callers fall back to a typed prompt when this says no.
menu_available() {
    if [ "${NO_MENU:-0}" = "1" ]; then return 1; fi
    if [ "${TERM:-dumb}" = "dumb" ]; then return 1; fi
    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then return 1; fi
    return 0
}

_menu_cursor() { printf '\033[?25%s' "$1" >/dev/tty; }

# One keypress -> one word. Escape sequences arrive as three bytes; the timeout
# is what tells a bare Escape apart from an arrow key.
_menu_key() {
    local k rest
    IFS= read -rsn1 k </dev/tty || return 1
    if [ "$k" = "$(printf '\033')" ]; then
        rest=""
        IFS= read -rsn2 -t 1 rest </dev/tty || true
        case "$rest" in
            '[A') echo up ;;
            '[B') echo down ;;
            *)    echo other ;;
        esac
        return 0
    fi
    case "$k" in
        '')    echo enter ;;
        ' ')   echo space ;;
        k|K)   echo up ;;
        j|J)   echo down ;;
        q|Q)   echo quit ;;
        [1-9]) echo "num:$k" ;;
        *)     echo other ;;
    esac
}

# Redraws in place: jump back over the previous frame, clearing each line.
_menu_render() {
    local drawn="$1" cur="$2" title="$3" hint="$4"
    local i n mark line value desc
    n=${#_MENU_ITEMS[@]}

    if [ "$drawn" -gt 0 ]; then printf '\033[%dA' "$drawn" >/dev/tty; fi

    printf '\033[2K\r  \033[1m%s\033[0m   \033[2m%s\033[0m\n' "$title" "$hint" >/dev/tty
    printf '\033[2K\r\n' >/dev/tty

    for ((i = 0; i < n; i++)); do
        value="${_MENU_ITEMS[$i]%%	*}"
        desc="${_MENU_ITEMS[$i]#*	}"
        if [ "$desc" = "${_MENU_ITEMS[$i]}" ]; then desc=""; fi

        if [ ${#_MENU_SEL[@]} -gt 0 ]; then
            if [ "${_MENU_SEL[$i]}" = "1" ]; then mark="[x]"; else mark="[ ]"; fi
        else
            if [ "$i" = "$cur" ]; then mark=" > "; else mark="   "; fi
        fi

        line="$(printf '%s %-12s %s' "$mark" "$value" "$desc")"
        if [ "$i" = "$cur" ]; then
            printf '\033[2K\r  \033[7m%s\033[0m\n' "$line" >/dev/tty
        else
            printf '\033[2K\r  %s\n' "$line" >/dev/tty
        fi
    done
}

# Shared key loop. $1 = multi (0/1); the caller has already filled _MENU_ITEMS.
_menu_loop() {
    local multi="$1" title="$2" start="$3"
    local n=${#_MENU_ITEMS[@]} cur="$start" drawn=0 key idx hint

    if [ "$multi" = "1" ]; then
        hint="up/down move . space toggles . enter confirms"
    else
        hint="up/down move . enter confirms"
    fi

    _menu_cursor l
    trap '_menu_cursor h; printf "\n" >/dev/tty; exit 130' INT
    while :; do
        _menu_render "$drawn" "$cur" "$title" "$hint"
        drawn=$((n + 2))
        key="$(_menu_key)" || key=enter
        case "$key" in
            up)    cur=$(((cur - 1 + n) % n)) ;;
            down)  cur=$(((cur + 1) % n)) ;;
            num:*) idx="${key#num:}"
                   if [ "$idx" -le "$n" ]; then cur=$((idx - 1)); fi ;;
            space) if [ "$multi" = "1" ]; then
                       if [ "${_MENU_SEL[$cur]}" = "1" ]; then
                           _MENU_SEL[$cur]=0
                       else
                           _MENU_SEL[$cur]=1
                       fi
                   fi ;;
            quit)  _menu_cursor h; printf '\n' >/dev/tty; exit 130 ;;
            enter) break ;;
        esac
    done
    trap - INT
    _menu_cursor h
    printf '\n' >/dev/tty
    echo "$cur"
}

menu_one() {
    local title="$1" default="$2"; shift 2
    local i start=0
    _MENU_ITEMS=("$@")
    _MENU_SEL=()

    for ((i = 0; i < ${#_MENU_ITEMS[@]}; i++)); do
        if [ "${_MENU_ITEMS[$i]%%	*}" = "$default" ]; then start=$i; fi
    done

    local cur; cur="$(_menu_loop 0 "$title" "$start")"
    echo "${_MENU_ITEMS[$cur]%%	*}"
}

menu_many() {
    local title="$1" pre="$2"; shift 2
    local i value
    _MENU_ITEMS=("$@")
    _MENU_SEL=()

    for ((i = 0; i < ${#_MENU_ITEMS[@]}; i++)); do
        value="${_MENU_ITEMS[$i]%%	*}"
        case ",$pre," in
            *",$value,"*) _MENU_SEL[$i]=1 ;;
            *)            _MENU_SEL[$i]=0 ;;
        esac
    done

    _menu_loop 1 "$title" 0 >/dev/null

    local out=""
    for ((i = 0; i < ${#_MENU_ITEMS[@]}; i++)); do
        if [ "${_MENU_SEL[$i]}" = "1" ]; then
            out="${out:+$out,}${_MENU_ITEMS[$i]%%	*}"
        fi
    done
    echo "$out"
}
