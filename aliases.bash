# PHP DevForge shortcuts.
#
# Usage:  source /path/to/php-devforge/aliases.bash
# Or permanently, from your ~/.bashrc:
#         source /path/to/php-devforge/aliases.bash
#
# The project path is resolved from this file, so it works wherever you clone it.
PHP_DEVFORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PHP_DEVFORGE_DIR

# Commands run in a subshell ( ... ) so your terminal does not change directory.

# Start / stop the stack
alias forge:start='(cd "$PHP_DEVFORGE_DIR" && docker compose up -d)'
alias forge:stop='(cd "$PHP_DEVFORGE_DIR" && docker compose stop)'
alias forge:reload='(cd "$PHP_DEVFORGE_DIR" && docker compose up -d)'

# Show and switch the PHP version
alias forge:current='sed -ne "s/^PHP_VERSION=\([0-9]\)\([0-9]\)$/Current version: PHP \1.\2/p" "$PHP_DEVFORGE_DIR/.env"'
alias forge:use:php83='(cd "$PHP_DEVFORGE_DIR" && sed -i "s/^PHP_VERSION=.*/PHP_VERSION=83/" .env && docker compose up -d)'
alias forge:use:php84='(cd "$PHP_DEVFORGE_DIR" && sed -i "s/^PHP_VERSION=.*/PHP_VERSION=84/" .env && docker compose up -d)'
alias forge:use:php85='(cd "$PHP_DEVFORGE_DIR" && sed -i "s/^PHP_VERSION=.*/PHP_VERSION=85/" .env && docker compose up -d)'

# Enter the PHP container, keeping your current dir when inside public_html.
alias forge:exec:php83='docker exec -it -w "$(pwd | grep -q public_html && pwd || echo /home/php-devforge)" -u php-devforge php83dev bash'
alias forge:exec:php84='docker exec -it -w "$(pwd | grep -q public_html && pwd || echo /home/php-devforge)" -u php-devforge php84dev bash'
alias forge:exec:php85='docker exec -it -w "$(pwd | grep -q public_html && pwd || echo /home/php-devforge)" -u php-devforge php85dev bash'

# Logs
alias forge:logs:php83='docker logs -f php83dev'
alias forge:logs:php84='docker logs -f php84dev'
alias forge:logs:php85='docker logs -f php85dev'
