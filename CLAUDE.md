# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

PHP DevForge is **infrastructure, not an application**: a Docker Compose stack (Apache + PHP-FPM 8.3/8.4 + dnsmasq + Postgres) that serves any PHP project dropped into `/home/php-devforge/public_html` under an auto-generated wildcard HTTPS domain. There is no PHP application code, no test suite, and no build system here — only Dockerfiles, server config, Lua scripts, and shell installers.

The repo is intended to be cloned to `$HOME/php-devforge-config` (the aliases in `aliases.bash` hardcode that path).

## Commands

```bash
docker compose up -d          # start (aliased: forge:start)
docker compose stop           # stop  (forge:stop)
docker compose logs -f php84dev
docker compose build apachedev            # rebuild one image
docker compose config                     # validate compose + .env interpolation

./install_cert.sh             # install mkcert + generate wildcard cert into ./certificates
./setup-local-dns.sh          # point system resolver at 127.0.0.1 (dnsmasq)
./setup-local-dns.sh --show   # inspect current DNS config
./setup-local-dns.sh --restore ~/.dns-backup-<timestamp>   # undo DNS changes

source aliases.bash           # forge:* helpers
```

Switching the default PHP version means editing `PHP_VERSION` in `.env` (83 or 84) and re-running `docker compose up -d` — that is exactly what `forge:use:php83` / `forge:use:php84` do. `PHP_VERSION` is consumed at compose-parse time (`depends_on: php${PHP_VERSION}dev`) and at runtime by Apache, so it must be changed in `.env`, not exported ad hoc.

Inside a PHP container (`forge:exec:php84` → `docker exec -u php-devforge php84dev bash`):

```bash
xdebug                    # toggle Xdebug for CLI + FPM
xdebug --force-activate   # or --force-deactivate
xdebug /path/script.php   # run one script with Xdebug on, then turn it back off
```

## Architecture: how a request becomes a docroot

This is the core mechanism and it spans three files.

1. **DNS** — `dnsmasq` resolves `*.${DEV_DOMAIN}` (default `phpforge.dev`) to `127.0.0.1`. `setup-local-dns.sh` inserts `127.0.0.1` as the system's first nameserver (NetworkManager → systemd-resolved → raw `resolv.conf`, in that order of preference).
2. **Docroot resolution** — `docker-library/httpd/config_files/resolve_docroot.lua` runs as `LuaHookTranslateName`. It strips the `--pNN` suffix and the base domain from the Host header, splits the remainder on `--` (or on `.`), **reverses the segments**, and joins with `/` under `/home/php-devforge/public_html`. So `public--site--laravel.phpforge.dev` → `/home/php-devforge/public_html/laravel/site/public`.
3. **PHP version routing** — `devlocal.conf` / `devlocal_https.conf` set `PHP_VERSION` from the env (via `PassEnv`), then override it per-request with `SetEnvIf Host ".*--p83.*"`. A `<FilesMatch \.php$>` block picks `proxy:fcgi://php83dev:9000` or `php84dev:9000` accordingly. Both PHP containers are always running; the hostname decides which one handles the request.

`docker-library/httpd/config_files/php-fpm.conf` is a legacy/unused fallback — the active handler selection lives in the two vhost files. Both vhosts are duplicates apart from the `SSLEngine` block; **changes to routing must be applied to both**.

An `nginx`/OpenResty alternative exists under `docker-library/nginx/` (same reversal idea, `map $host $php_backend`), but it is commented out in `docker-compose.yml` and its Lua uses a broken pattern (`[0-9]{2}` / `\\.`, which are not Lua patterns) plus a `gsub("--", "/")` that does *not* reverse segments — it is not equivalent to the Apache path and is effectively unmaintained.

## Container layout

- `docker-compose.yml` — dnsmasq, apachedev, php83dev, php84dev. `docker-compose.override.yml` adds `postgres16dev` (5439 on the host) and has commented Elasticsearch/Kibana. Both files are joined via `COMPOSE_FILE` in `.env`.
- Code sharing: a named volume `dataphp-devforge` mounts at `/home/php-devforge` in every container, and the **host** path `/home/php-devforge/public_html` is bind-mounted over it. Apache gets `/home/php-devforge` read-only but `public_html` read-write.
- The PHP user is `php-devforge` with **UID/GID 33** (`www-data`) so host and container permissions line up — hence the README's `chown $USER:www-data -R /home/php-devforge`. FPM itself runs as `www-data`.
- `docker-library/php/8.3/Dockerfile` and `8.4/Dockerfile` are byte-identical apart from the `FROM` and `PHP_VERSION` arg. **Any change to one belongs in the other.**
- `docker-library/php/config_files/docker-php-entrypoint` replaces the upstream entrypoint: it injects the custom bashrc, force-activates Xdebug when `PHP_XDEBUG=yes`, installs `~/script/cron_php-devforge` as a www-data crontab, starts cron, and `exec sudo "$@"` (the image runs as non-root `php-devforge`, so this is how php-fpm gets root).

## Conventions

- Comments and script output in this repo are in Spanish; the README is in English. Match the surrounding language when editing a file.
- Rebuilding a PHP image is expensive (compiles GD/intl/etc., PECL builds, clones nvm, installs Node 19). Prefer changes to mounted config over Dockerfile changes when both are possible.

## Known inconsistencies in the current tree

Verify before assuming any of these are intentional; several will bite on a fresh setup.

- **Compose cannot build the PHP images.** `dockerfile: ./docker-library/php/8.3` is resolved relative to the build context (`./docker-library/php`), so it points at a non-existent nested path — and `8.3` is a directory, not a file. The working value is `8.3/Dockerfile`.
- **Certificate filename mismatch.** `install_cert.sh` writes `certificates/php-devbox.{pem,key}`, but the Apache vhost reads `/etc/apache2/ssl/php-devforge.{pem,key}`. HTTPS will not start until the names agree (the nginx template also expects `php-devbox.*`).
- **`install_cert.sh` guards on the wrong path**: it tests `[ -f install_linux.sh ]` (repo root) before running `bash mkcert_install/install_linux.sh`, so the mkcert install branch always aborts.
- **`forge:current` reads `$HOME//configs-docker/.env`**, a stale path from a previous project name.
- **Xdebug's `client_port` is 9000**, the same port FPM listens on; `xdebug` reloads FPM with a hardcoded `kill -USR2 40` (assumes the master is PID 40).
