# shellcheck shell=bash
# The two ways CI asks the stack for a page. Sourced by the steps that need
# them, from the repo root:
#
#     . .github/scripts/serve.sh
#
# One file rather than a copy per step: there were three, two of them identical
# byte for byte, and the diagnostics below would have had to be learned by each
# one separately.
#
# Never `curl ... | grep -q`: grep exits at the first match, curl is left
# writing to a closed pipe and dies of SIGPIPE, and under pipefail a match
# becomes a failure. It broke this workflow twice -- once on main, when the
# welcome page grew past a hundred bytes. Everything here goes through a file.

# One request; the body has to contain something. Fails the step when it does not.
serves() { # host prefix, expected text
    curl -fsS -k --max-time 10 --resolve "$1.phpforge.dev:443:127.0.0.1" \
        "https://$1.phpforge.dev/" > /tmp/page.txt
    grep -q "$2" /tmp/page.txt \
        || { echo "$1 does not contain: $2"; head -5 /tmp/page.txt; exit 1; }
}

# Retried, for the window a restart opens: "started" is not "ready" -- Apache
# answers on 443 before the PHP containers finish their entrypoint, and proxies
# into that window with a 503. 60 tries, not 30: a step that recreates every
# container once gave up at 44 seconds while its twin on the same commit passed.
#
# On exhaustion it has to say why. One run failed 60 times in 61 seconds -- every
# attempt failing instantly, which is a refused connection or a status code, never
# a timeout -- and the old helper sent curl's stderr to /dev/null, so all it could
# report was "no answer" beside a container reporting healthy. These three now
# read differently from each other:
#
#     curl said: curl: (7) Failed to connect to 127.0.0.1 port 443
#     last http status: 404
#     it answered 200 with an empty body
serve() { # host, path -> body on stdout, empty when it never answered
    local body err code="" why="" out=""
    body="$(mktemp)"; err="$(mktemp)"
    for _ in $(seq 1 60); do
        # No -f, which throws the status away along with the body; the status is
        # the evidence. Only a 2xx counts as an answer, exactly as -f had it --
        # an error page has a body too, and returning it would let `test -n`
        # pass on a 404.
        out=""
        code="$(curl -sSk --max-time 5 -o "$body" -w '%{http_code}' \
                --resolve "$1:443:127.0.0.1" "https://$1/$2" 2>"$err")" || true
        why="$(cat "$err")"
        case "$code" in
            2??) out="$(cat "$body")"; [ -n "$out" ] && break ;;
        esac
        sleep 1
    done
    if [ -z "$out" ]; then
        {
            echo "no answer from https://$1/$2 after 60 tries"
            echo "  last http status: ${code:-none}"
            [ -n "$why" ] && echo "  curl said: $why"
            case "$code" in
                2??) echo "  it answered $code with an empty body" ;;
                000|"") ;;
                *) echo "  what it served instead:"; head -3 "$body" | sed 's/^/    /' ;;
            esac
            echo "  listening on 443:"
            ss -lnt 2>/dev/null | grep ':443' || echo "    nothing"
            docker compose ps
            docker compose logs --tail=20 apachedev
        } >&2
    fi
    rm -f "$body" "$err"
    printf '%s' "$out"
}
