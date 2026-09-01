---
name: php-devforge
description: >-
  Use when working on a PHP project served by PHP DevForge — a local Docker
  environment that serves every project under one folder at https://<name>.<dev
  domain> (phpforge.dev by default) with PHP-FPM 8.3/8.4/8.5, Postgres, MariaDB
  and a mail catcher. Covers running composer, pnpm, npm and artisan inside the
  right container with `forge run`, working out a project's URL, database and
  SMTP settings, reading logs, and managing PHP versions, optional services,
  certificates and DNS.
---

# PHP DevForge

A Docker Compose stack that serves any PHP project dropped into one folder,
under an automatic wildcard HTTPS domain. There is no per-project configuration:
the URL determines the document root and the PHP version.

Everything below is driven by one command, `forge`, which runs **on the host**.

## Is this project served by PHP DevForge?

Any of these means yes:

```bash
forge status                  # prints the domain, the PHP versions and what runs
```

- `forge status` succeeds, and the project directory is under the `projects:`
  path it prints (`PROJECTS_DIR`).
- The project is reachable at a `*.phpforge.dev` URL (or whatever `domain:` says).

If `forge` is not on the PATH, the checkout is usually `~/php-devforge-config`;
run `~/php-devforge-config/bin/forge` instead.

## Running commands in the project

**Use `forge run`. Do not call `docker exec` by hand.**

```bash
forge run composer install          # in the directory you are in
forge run pnpm run build
forge run php artisan migrate
forge run -p 8.3 php -v             # a specific PHP version
forge run -C projects/my-app pnpm build    # from anywhere
```

It works out the container, translates the host directory to the path the
container sees, runs the command as the right user in a login shell, and returns
the command's own exit status.

Four things it gets right that a hand-written `docker exec` does not:

- **The path is different inside.** The projects folder is bind-mounted at a
  fixed `/home/php-devforge/public_html`, so passing the host path to
  `docker exec -w` fails with `chdir ... no such file or directory`.
- **The user is `php-devforge`**, not root. Running as root leaves files you
  then need `sudo` to delete.
- **`bash -lc` is required.** Node, npm and pnpm come from nvm and are only on
  the PATH of a login shell — `docker exec php85dev pnpm build` is
  `command not found`, which reads like a missing dependency.
- **No TTY unless there is one.** `forge run` adds `-t` only when stdout is a
  terminal, so captured output has no escape codes and no `-it` error.

For an interactive session instead: `forge shell` (or `forge shell 8.3`), which
keeps your current directory when you are inside a project.

## Which URL serves this project

Two ways to reach the same code:

| URL | Serves |
|---|---|
| `my-app.phpforge.dev` | `sites/my-app` |
| `v2--api.phpforge.dev` | `sites/api/v2` |
| `public--my-app--projects.phpforge.dev` | `projects/my-app/public` |

The host name is the path with its segments **reversed** and joined by `--`,
under the projects folder. `sites/` holds one symlink per project and is tried
first, which is why a published project gets a short name.

To publish one:

```bash
forge link ~/php-devforge/projects/my-app/public       # -> https://my-app.phpforge.dev
```

It names the site after the project directory when the folder is `public`, makes
the symlink relative so it also resolves inside the containers, and refuses a
folder outside the projects directory — the containers can see nothing else.

**Pick a PHP version per request** by suffixing the host: `my-app--p83.phpforge.dev`
runs the same code on 8.3. No configuration changes.

## Databases and mail

Nothing runs unless it is enabled. `forge db list` shows what exists and what is
on; `forge db on pg18` starts one.

| Service | From your code (container network) | From the host |
|---|---|---|
| `postgres16dev` / `17` / `18` | `postgres18dev:5432` | `127.0.0.1:5416` / `5417` / `5418` |
| `mariadb11dev` / `12` | `mariadb12dev:3306` | `127.0.0.1:3311` / `3312` |
| `mailpit` | `mailpit:1025`, no auth, no TLS | web UI at `https://mail.phpforge.dev` |

Credentials are `USER_DEV` and `PASSWD_DEV` in the checkout's `.env`
(`php-devforge` / `php-devforge01` unless changed), and the default database has
the same name as the user.

```php
new PDO("pgsql:host=postgres18dev;port=5432;dbname=php-devforge", $user, $pass);
```

Use the container name from PHP and the `127.0.0.1` port from host tools (`psql`,
a GUI client). The host ports encode the version so several can run at once.

## What is live and what needs a restart

- **Code is live.** The folder is bind-mounted; edits are served immediately.
  Never restart anything after changing PHP, JS or templates.
- **Needs `forge restart`:** the checkout's `.env`, files in `custom/php.d/` or
  `custom/<version>/php.d/`, and anything under `docker-library/`.
- **Needs nothing:** adding a project, adding a symlink in `sites/`. New host
  names resolve through a wildcard.

## Logs

```bash
forge logs                # everything, followed
forge logs 8.5            # one PHP version
forge logs apachedev      # one service
```

PHP warnings and fatals go to the container log, not to a file in the project.
A 500 with a blank page is almost always visible in `forge logs`.

## Managing the environment

```bash
forge start | stop | restart | status

forge php list                  # versions, and which are installed
forge php on 8.3                # install one (about 2 GB)
forge use 8.5                   # move the default version

forge profile list              # every optional service
forge db on pg18                # databases, same thing filtered
forge mail on                   # the mail catcher

forge images pull | build       # published images, or build locally
forge certs                     # regenerate the HTTPS certificates
forge dns status                # is the resolver pointed here?
```

These rewrite the checkout's `.env` and restart what is needed. **Prefer them to
editing `.env` by hand** — `COMPOSE_PROFILES` and `PHP_VERSION` have to agree,
and the commands enforce that (`forge php off` refuses to remove the default
version, `forge use` installs the version it switches to).

Ask before running anything that changes the machine outside Docker: `forge
install`, `forge uninstall`, `forge certs` and `forge dns setup` touch the system
resolver or the trusted certificate store and need `sudo`.

## Things that will bite

- **`sudo` is never needed for project files.** The PHP containers adopt the
  host user's uid/gid, so `node_modules` and `vendor` belong to you.
- **A symlink out of the projects folder resolves to nothing** inside the
  containers, and the site 404s.
- **Under nginx there is no `.htaccess`.** The stack reads the front-controller
  `RewriteRule` out of it and routes accordingly (`NGINX_FRONT_CONTROLLER=auto`,
  the default), so Laravel, Symfony and WordPress work — but deny rules, headers
  and redirects in that file are ignored. Apache honours the whole file.
- **A 403 on a directory** means there is no `index.php` where the URL points —
  usually a site linked to the project root instead of its `public/`.
- **A page saying a PHP version is not installed** is not an error in your code:
  run `forge php on <version>`.
- **Rebuilding a PHP image is expensive** (it compiles extensions and installs
  Node). Prefer `custom/php.d/*.ini`, which needs only a restart.

## Xdebug

Off by default. Inside a PHP container (`forge shell`):

```bash
xdebug                        # toggle for CLI and FPM
xdebug /path/to/script.php    # run one script with it on, then turn it back off
```
