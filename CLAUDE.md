# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

PHP DevForge is **infrastructure, not an application**: a Docker Compose stack (Apache + PHP-FPM 8.3/8.4 + dnsmasq + Postgres) that serves any PHP project dropped into `/home/php-devforge/public_html` under an auto-generated wildcard HTTPS domain. There is no PHP application code, no test suite, and no build system here — only Dockerfiles, server config, Lua scripts, and shell installers.

Nothing hardcodes where the repo lives — `aliases.bash` resolves its own location dynamically via `BASH_SOURCE`, and `bin/forge` does the same via `$0`. `$HOME/php-devforge-config` is only `bootstrap.sh`'s *default* clone target for the one-line install (`--dir=`/`PHP_DEVFORGE_HOME` override it); a manual `git clone` can go anywhere.

## Commands

```bash
forge start                   # start
forge stop                    # stop
forge logs 8.4                # follow one version's logs
forge restart apachedev       # recreate one container
forge help                    # every command

docker compose build apachedev            # rebuild one image
docker compose config                     # validate compose + .env interpolation

./install_cert.sh             # install mkcert + generate wildcard cert into ./certificates
./setup-local-dns.sh          # point system resolver at 127.0.0.1 (dnsmasq)
./setup-local-dns.sh --show   # inspect current DNS config
./setup-local-dns.sh --restore ~/.dns-backup-<timestamp>   # undo DNS changes
```

`forge` is the interface; reach for `docker compose` only for the two things it
does not wrap. The `forge:start` / `forge:use:php84` aliases this file used to
teach **no longer exist** — they only worked in bash, and `bin/forge` replaced
them. `aliases.bash` survives as a one-line PATH helper for when `~/.local/bin`
is not on `PATH`, or for a second checkout; it defines no aliases.

Switching the default PHP version is `forge use 8.4`, which writes `PHP_VERSION`
in `.env` and recreates the containers. It has to live in `.env` rather than an ad
hoc export: it is read at compose-parse time (`depends_on: php${PHP_VERSION}dev`)
and again at runtime by the web server.

Inside a PHP container (`forge shell 8.4`, or `forge run <command>` for one-offs):

```bash
xdebug                    # toggle Xdebug for CLI + FPM
xdebug --force-activate   # or --force-deactivate
xdebug /path/script.php   # run one script with Xdebug on, then turn it back off
```

## Architecture: how a request becomes a docroot

This is the core mechanism and it spans three files.

1. **DNS** — `dnsmasq` resolves `*.${DEV_DOMAIN}` (default `phpforge.dev`) to `127.0.0.1`. `setup-local-dns.sh` inserts `127.0.0.1` as the system's first nameserver (NetworkManager → systemd-resolved → raw `resolv.conf`, in that order of preference).
2. **Docroot resolution** — `docker-library/httpd/config_files/resolve_docroot.lua` runs as `LuaHookTranslateName`. It strips the `--pNN` suffix and the base domain from the Host header, splits the remainder on `--` (or on `.`), **reverses the segments**, and joins with `/` under `/home/php-devforge/public_html`. So `public--site--laravel.phpforge.dev` → `/home/php-devforge/public_html/laravel/site/public`.
3. **PHP version routing** — `resolve_docroot.lua` (`set_php_handler`, a `LuaHookFixups`) picks `proxy:fcgi://phpNNdev:9000` from the `--pNN` suffix, falling back to `PHP_VERSION`. Each version is a compose profile (`php83`, `php84`, `php85`) listed in `COMPOSE_PROFILES`, so only the installed ones run; the same variable reaches Apache and nginx as `ENABLED_PROFILES`, and the Lua answers a request for a version that is not installed with a page instead of a bare 503. `COMPOSE_PROFILES` always contains the default version — `forge php off` refuses to remove it, and a `.env` with no `php*` entry is migrated by `forge`.

`docker-library/httpd/config_files/php-fpm.conf` is a legacy/unused fallback — the active handler selection lives in the two vhost files. Both vhosts are duplicates apart from the `SSLEngine` block; **changes to routing must be applied to both**.

An `nginx`/OpenResty alternative exists under `docker-library/nginx/` (same reversal logic, in `resolve_docroot.lua`'s `rewrite_by_lua_file` hook) as the `nginxdev` service, gated behind the `nginx` profile — it *replaces* `apachedev` rather than adding to it, since both want ports 80 and 443. It is equivalent to the Apache path, including the tunnel mechanism (`.tunnel/` lookup and `--php` pin): `site.conf.tpl` carries the same `default_server` catch-all `devlocal-common.conf` needed on the Apache side, for the same reason (an unmatched host otherwise falls to the first server block in the file, Mailpit's).

## Container layout

- `docker-compose.yml` — `mkcert` (one-shot, `tools` profile), `dnsmasq`, `apachedev`, `nginxdev` (`nginx` profile — it *replaces* Apache, both want 80 and 443), and `php83dev`/`php84dev`/`php85dev`, one profile each. `docker-compose.override.yml` adds the optional services: `postgres16/17/18dev` (127.0.0.1:5416/5417/5418), `mariadb11/12dev` (3311/3312), `mailpit`, `cloudflared` (`tunnel` profile), `es8143dev` and `kibana`. The three files are joined via `COMPOSE_FILE` in `.env`, with `docker-compose.local.yml` last so your own overrides win.
- Code sharing: a named volume `dataphp-devforge` mounts at `/home/php-devforge` in every container, and `PROJECTS_DIR` from `.env` is bind-mounted over `/home/php-devforge/public_html`. Apache gets `/home/php-devforge` read-only but `public_html` read-write.
- The PHP user is `php-devforge`, **UID/GID 1000 in the image**, remapped at startup to `PUID`/`PGID` from `.env` (`usermod -o -u`) so host and container ownership line up. That is why **no `chown` is needed**: the README's old `sudo chown yourUser:www-data -R /home/php-devforge` was removed in `f7ead35` when this replaced it. The php-fpm **master runs as root** so it can drop its workers to `php-devforge` — `zz-docker.conf` sets that and is read after the upstream `www.conf`, which still says `www-data`. Workers never run as root.
- One Dockerfile serves every PHP version (`docker-library/php/Dockerfile`, `PHP_TAG` build arg). What the services share lives in `php-base.yml`, pulled in with `extends:` rather than a YAML anchor — an anchor merge replaces a service's `volumes` list, `extends` appends to it, which is what lets each version add its own `./custom/<version>` mount. `custom/php.d` applies to every version; `custom/<version>/php.d` is read after it and wins. `ensure_custom_dirs()` in `lib/compose.sh` creates those folders before compose can, since Docker would create a missing bind source as root.
- `docker-library/php/config_files/docker-php-entrypoint` replaces the upstream entrypoint: it remaps the user to `PUID`/`PGID`, injects the shared bashrc for both the dev user and root, force-activates Xdebug when `PHP_XDEBUG=yes`, installs `~/script/cron_php-devforge` as a **`php-devforge`** crontab (`crontab -u php-devforge`), starts cron, and ends in a plain `exec "$@"` as root — see the note above on why the master needs it.

## Where work is tracked

There is no `TASKS.md` (retired) and no issue-tracking convention in this repo
beyond git history and PR descriptions. Open questions, decisions, and
in-progress/`Needs discussion`/`Not doing` items live in a GitHub Project:
<https://github.com/users/zelti/projects/2> ("PHP DevForge Roadmap"), owned by
the repo owner's personal account, not a repo-linked project. Each item is a
draft issue (title + full write-up in the body, no separate Issue page) with a
`Status` of `Needs discussion`, `Todo`, `In Progress`, `Done`, or `Not doing`.
Read it with `gh project item-list 2 --owner zelti`; it needs the `project`
OAuth scope (`gh auth status` shows current scopes; `gh auth refresh -s
project` adds it if missing).

## Conventions

- Comments and script output in this repo are in Spanish; `README.md` and `DOCS.md` are in English, `README.es.md` and `DOCS.es.md` their translations. Edit a page and its translation together. Match the surrounding language when editing a file.
- Rebuilding a PHP image is expensive (compiles GD/intl/etc., PECL builds, clones nvm, installs Node 24). Prefer changes to mounted config over Dockerfile changes when both are possible.

## Where to look when something is off

The tracker is the GitHub Project linked below, not a list in this file. A list
here cannot be closed by a commit, so it only ever drifts: the five entries that
used to sit in this spot were all fixed long ago and still read as live warnings
— a wrong certificate name, a broken mkcert branch, a `forge:` alias that no
longer exists, an Xdebug port that had already moved from 9000 to 9003. Anyone
who trusted them went looking for bugs that were not there.

Check the tree first and the Project second; add a finding to the Project rather
than to this page.
