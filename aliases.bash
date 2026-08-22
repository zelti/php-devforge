# Optional: adds `forge` to your PATH for this shell.
#
# The installer normally symlinks it into ~/.local/bin, so you rarely need this.
# Useful if that directory is not on your PATH, or to use a second checkout.
#
#   source /path/to/php-devforge/aliases.bash
#
# The old forge:start / forge:use:php84 aliases are gone. They only worked in
# bash; `forge` is a real command and works in zsh and fish too.
#
#   forge:start        ->  forge start
#   forge:use:php84    ->  forge use 8.4
#   forge:exec:php84   ->  forge shell 8.4
#   forge:logs:php84   ->  forge logs 8.4
#   forge:current      ->  forge status

PHP_DEVFORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PHP_DEVFORGE_DIR
export PATH="$PHP_DEVFORGE_DIR/bin:$PATH"
