#!/bin/bash
#
# One-line install:
#
#   curl -fsSL https://raw.githubusercontent.com/zelti/php-devforge/main/bootstrap.sh | bash
#
# This installs nothing itself. It clones the repository (or updates it, if
# already cloned here) and hands over to the installer everyone already has --
# the repository is the product, not this script.
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

REPO_URL="https://github.com/zelti/php-devforge.git"
DIR="${PHP_DEVFORGE_HOME:-$HOME/php-devforge-config}"

# --dir is ours; everything else is install.sh's (or forge update's) to parse,
# not ours to understand.
args=()
for arg in "$@"; do
    case "$arg" in
        --dir=*) DIR="${arg#*=}" ;;
        *) args+=("$arg") ;;
    esac
done
DIR="${DIR/#\~/$HOME}"

if [ "$(id -u)" -eq 0 ]; then
    err "Don't run this with sudo."
    echo "  If docker fails with a permission error, that's a docker-group problem," >&2
    echo "  not something this installer running as root would fix:" >&2
    echo "      sudo usermod -aG docker \$USER   # then log out and back in" >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    err "git is not installed."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    err "Docker is not installed."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    err "Docker is installed but not running. Start it and try again."
    exit 1
fi
info "Docker is running"

# A real terminal to hand back to install.sh's own prompts -- under
# `curl | bash`, stdin is the pipe, not the keyboard, so install.sh's own
# guard would otherwise refuse with a confusing "cannot open /dev/tty" instead
# of its actual "no terminal to ask questions on" message. Actually opening it
# is the only real test: the device can exist and pass -r/-w and still fail
# with "No such device or address" when the process has no controlling
# terminal at all, which is exactly the headless case this has to detect.
tty=()
if ( : </dev/tty ) 2>/dev/null; then tty=(/dev/tty); fi

if [ -e "$DIR" ]; then
    remote="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
    case "$remote" in
        *zelti/php-devforge*)
            info "Already cloned at $DIR -- updating instead"
            cd "$DIR"
            exec bin/forge update "${args[@]}"
            ;;
        *)
            err "$DIR already exists and is not this project."
            echo "  Pick another folder:  curl ... | bash -s -- --dir=PATH" >&2
            echo "  Or set PHP_DEVFORGE_HOME=PATH" >&2
            exit 1
            ;;
    esac
fi

info "Cloning into $DIR"
git clone "$REPO_URL" "$DIR"
cd "$DIR"

if [ "${#tty[@]}" -gt 0 ]; then
    exec ./install.sh "${args[@]}" <"${tty[0]}"
else
    exec ./install.sh "${args[@]}"
fi
