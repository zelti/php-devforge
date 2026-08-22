<p align="center">
  <img src="./logo.png" alt="PHP DevForge" width="300px" height="300px">
</p>

# PHP DevForge

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/zelti/php-devforge/actions/workflows/ci.yml/badge.svg)](https://github.com/zelti/php-devforge/actions/workflows/ci.yml)
![PHP](https://img.shields.io/badge/PHP-8.3%20%7C%208.4%20%7C%208.5-777BB4)
[![GitHub last commit](https://img.shields.io/github/last-commit/zelti/php-devforge)]()

**English** · [Español](README.es.md)

A local PHP environment where **the folder structure is the configuration**.

> Unlike tools built around per-project configuration, PHP DevForge derives domains
> straight from your folder structure. No config files, no init commands: create the
> folder and the site exists.

---

## ⚡ How it works

```
~/php-devforge/sites/
├── my-app        →  https://my-app--sites.phpforge.dev
├── shop          →  https://shop--sites.phpforge.dev
└── api/v2        →  https://v2--api--sites.phpforge.dev
```

The host name is the path, reversed and joined with `--`. Nothing to register,
nothing to restart. Add a folder, reload the browser.

**Any PHP version, per request:**

```
https://my-app--sites.phpforge.dev          # your default
https://my-app--sites--p83.phpforge.dev     # this request on PHP 8.3
https://my-app--sites--p85.phpforge.dev     # this request on PHP 8.5
```

Same code, three PHP versions, no restart and no switching. Useful for checking an
upgrade before committing to it.

Everything is served over **real HTTPS** with a locally trusted certificate.

## 🧭 How it compares

|  | PHP DevForge | [Herd](https://herd.laravel.com) | [DDEV](https://ddev.com) |
|---|---|---|---|
| Domain from folder name | ✅ | ✅ | ❌ per-project config |
| **Nested paths** (`v2--api--sites`) | ✅ any depth | ❌ one level | ❌ |
| **PHP version per request** (`--p85`) | ✅ from the URL | ❌ per site | ❌ per project |
| Linux | ✅ | ❌ macOS/Windows | ✅ |
| Runs in Docker | ✅ | ❌ native | ✅ |
| Local HTTPS | ✅ | ✅ | ✅ |
| `.htaccess` | ✅ Apache | ✅ | ✅ |

DDEV gives you a per-project, reproducible definition — better when each project
needs a different stack. Herd is the fastest native option on macOS. PHP DevForge is
for keeping many projects on one shared environment with no per-project setup.

## 📖 What you get

- **Apache + PHP-FPM 8.3, 8.4 and 8.5**, all running, chosen per request
- **Automatic HTTPS** with a locally trusted CA
- **Wildcard local DNS** that only touches your dev domain
- **Live editing** — files are mounted, nothing to sync
- **Files stay yours** — containers adopt your user id, so no `sudo` and no
  unremovable `node_modules`
- **Xdebug** on a toggle, **Composer**, **Node 24**, **pnpm**
- Optional **PostgreSQL**, **Elasticsearch** and **Kibana**

## 🚀 Quick start

```bash
git clone https://github.com/zelti/php-devforge.git
cd php-devforge
./install.sh            # asks a few questions, sets everything up
forge start
```

Then open **https://welcome--sites.phpforge.dev**.

## 🔧 Installation

### 📋 Prerequisites

- Docker and Docker Compose (also used to generate the SSL certificates)
- Git
- Bash shell (Linux/macOS)

### 🚀 Setup Steps

1. **Clone the repository:**
   ```bash
   git clone git@github.com:zelti/php-devforge.git
   cd php-devforge
   ```
    Clone it wherever you like: the scripts and aliases resolve their own location.

2. **Run the installer:**
   ```bash
   ./install.sh
   ```
   It asks for your domain, where your projects should live and the default PHP
   version, finds a free DNS port, detects your user id, writes `.env`, creates the
   projects folder, and offers to generate the certificates and configure local DNS.

   Safe to re-run: your current `.env` supplies the defaults. For unattended use:
   ```bash
   ./install.sh --yes --domain=mydomain.dev --projects-dir=~/code
   ./install.sh --help        # every option
   ```

   Nothing needs `sudo` except the DNS step, and only if you accept it.

3. **Use it from anywhere:**
   The installer links `forge` into `~/.local/bin`, so the command works from any
   directory and in any shell. `forge help` lists everything.

4. **Start the containers:**
    ```bash
    docker compose up -d
    ```
    Or `forge start`, which works from anywhere.

    Check it works: `https://welcome--sites.phpforge.dev`

## 💻 Usage

### ▶️ Starting and Stopping

```bash
forge start                  # start everything
forge stop
forge restart
forge status                 # what is running, and how it is configured

forge use 8.5                # set the default PHP version
forge shell 8.4              # open a shell in a container
forge logs 8.4               # follow its logs

forge images build|pull      # build locally, or use the published images
forge certs                  # regenerate the certificates
forge dns status             # inspect the local DNS

forge help
```

`forge` works from any directory, in any shell. The installer links it into
`~/.local/bin`. Version arguments accept `8.5` or `85`, and the available versions
come from `docker-compose.yml` — add a service and `forge use 8.6` just works.

### 🌐 Accessing Your Projects

1. **Create project structure:**
   Your projects live in the folder you chose during install (`PROJECTS_DIR` in
   `.env`, `~/php-devforge` by default). The installer creates it with:

   ```
   ~/php-devforge/
   ├── projects/          your actual code
   └── sites/             one symlink per project, for shorter URLs
       └── welcome/       a test page
   ```

   Inside the containers this is always `/home/php-devforge/public_html`, which is
   where Apache and PHP look. Only the host side is configurable.

   **Symlinks must point inside `PROJECTS_DIR`.** The containers only see that
   folder, so a link to anywhere else resolves to nothing and returns 404.

   No `chown` is needed. The PHP containers adopt your user id at startup
   (`PUID`/`PGID` in `.env`), so files they create belong to you and `node_modules`
   can be deleted without `sudo`.

2. **URL Structure:**
   Projects are accessible via automatically generated URLs:
   - `folder/project/public/index.php` → `https://public--project--folder.phpforge.dev`
   - The URL is constructed by reversing the folder path segments separated by `--`

3. **PHP Version Switching:**
   Append `--pNN` to the host to pick a version for that request only:
   - `https://my-app--sites.phpforge.dev` — the default from `.env`
   - `https://my-app--sites--p83.phpforge.dev` — PHP 8.3
   - `https://my-app--sites--p84.phpforge.dev` — PHP 8.4
   - `https://my-app--sites--p85.phpforge.dev` — PHP 8.5

   The backend is derived from the host name, so adding a PHP version needs no
   configuration change — only a service in `docker-compose.yml`.

### 🔄 Development Workflow

- Edit code in your IDE (files are volume-mounted for live updates)
- Changes appear immediately without restarting containers
- Use Xdebug for debugging (configure your IDE to listen on port **9003**, the Xdebug 3 default)
- Open a shell in a container with `forge shell 8.4`

## 🌐 Local DNS

The installer offers to set this up. It routes **only** your development domain to
the stack's dnsmasq; the rest of your DNS is untouched, so stopping the containers
never costs you internet access.

```bash
./setup-local-dns.sh            # apply
./setup-local-dns.sh --status   # show what is configured
./setup-local-dns.sh --test     # check resolution
./setup-local-dns.sh --remove   # undo: deletes one file
```

dnsmasq listens on `127.0.0.1:${DNS_PORT}` rather than port 53, which is usually
taken by systemd-resolved, Pi-hole or similar. The installer picks a free port and
writes it to `.env`; change it there if you need to.

Supported: Linux with systemd-resolved, and macOS via `/etc/resolver`. On anything
else the script prints instructions and **changes nothing**, rather than rewriting
your DNS in a way that could break when the containers are down.

## ✏️ Customising Without Breaking Upgrades

**Do not edit anything under `docker-library/`.** Those files change with every
release, so your edits will conflict on `git pull` — and a copy kept aside is
worse: it stops receiving fixes, silently. Use these instead. All three are
ignored by git.

**PHP settings — no rebuild.** Drop a file in `custom/php.d/`:

```ini
; custom/php.d/99-mine.ini
memory_limit = 512M
upload_max_filesize = 100M
```

```bash
docker compose up -d --force-recreate php84dev
```

It is scanned *in addition to* the image's own config, so nothing is shadowed and
the Xdebug toggle keeps working.

**Your own services** — `docker-compose.local.yml`, loaded automatically:

```yaml
services:
  redis:
    image: redis:7-alpine
    ports:
      - 127.0.0.1:6379:6379
```

The same file overrides anything in the shipped compose files: ports, volumes,
environment.

**Extra PHP extensions or system packages** — extend the image instead of copying
its Dockerfile, so you keep getting upstream fixes:

```dockerfile
# custom/php/Dockerfile
FROM ghcr.io/zelti/php-devforge/php:8.4-dev
RUN sudo pecl install mongodb && sudo docker-php-ext-enable mongodb
```

```yaml
# docker-compose.local.yml
services:
  php84dev:
    build:
      context: ./custom/php
```

## 📦 Pull or Build the Images

By default the environment uses prebuilt images from `ghcr.io`, so the first run
takes about a minute instead of the ~15 it takes to compile PHP extensions, PECL
and Node. The installer asks which you want, and you can change your mind at any
time with one line in `.env`:

```bash
IMAGE_MODE=missing   # use the published images (default)
IMAGE_MODE=build     # always build locally
IMAGE_MODE=always    # re-pull every time, to force the newest published image
```

Then `docker compose up -d`.

Pick `build` if you edit anything under `docker-library/`: your changes are picked
up automatically, and Docker's layer cache makes it cheap when nothing changed.
Either way `docker compose build` still builds on demand, and compose falls back
to building if an image cannot be pulled.

**Note:** settings baked in at build time — `NODE_VERSION`, for instance — only
apply when you build. A pulled image already has them fixed.

## 🗄️ Databases and Mail

Nothing starts unless you pick it. The installer asks; afterwards:

```bash
forge db list              # what exists, and what is on
forge db on pg18
forge db off mariadb12
forge mail on              # a mail catcher at mail.<domain>
```

| Name | Image | Port on your machine |
|---|---|---|
| `pg16` `pg17` `pg18` | postgres 16 / 17 / 18 | 5416 / 5417 / 5418 |
| `mariadb11` `mariadb12` | mariadb 11.8 LTS / 12 | 3311 / 3312 |
| `mail` | Mailpit | web UI at `https://mail.<domain>` |

The ports encode the version, so several can run at once — handy for testing a
migration against the version you will deploy to.

**From your code**, reach them by container name on the shared network:

```php
new PDO("pgsql:host=postgres18dev;port=5432;dbname=php-devforge", $user, $pass);
new PDO("mysql:host=mariadb12dev;port=3306;dbname=php-devforge", $user, $pass);
```

Credentials are `USER_DEV` / `PASSWD_DEV` from `.env`. The host ports above are for
your own tools — a GUI client, `psql`, a migration script.

**Mail**: point your framework's SMTP settings at `mailpit:1025`, no auth and no TLS.
Everything sent is captured and shown at `https://mail.<domain>`; nothing leaves
your machine.

## 🧩 Optional Services

Some services are not started by default. They carry a compose `profile`, so you
ask for them when you want them:

```bash
docker compose --profile search up -d      # Elasticsearch + Kibana
```

Profiles are a compose feature, so this one stays a `docker compose` command;
`forge start` covers the default set.

| Profile | Services | Notes |
|---|---|---|
| *(none)* | apachedev, php83dev, php84dev, php85dev, dnsmasq, postgres16dev | started by `forge start` |
| `search` | es8143dev, kibana | Kibana on `127.0.0.1:5601` |
| `tools` | mkcert | used by `install_cert.sh`; not a long-running service |
| `nginx` | nginxdev | **replaces** apachedev; see below |

### nginx instead of Apache

Apache is the default because it supports `.htaccess`, which nginx does not. If you
would rather run nginx, it is there — as an alternative, not an addition, since both
want ports 80 and 443:

```bash
docker compose stop apachedev
docker compose --profile nginx up -d nginxdev
```

It serves the same URLs, including nested paths and the `--pNN` version suffix.

It is **OpenResty**, not stock nginx: the document root and the PHP backend are
derived from the host name in Lua, which plain nginx cannot do. Swapping the base
image for `nginx:alpine` will not work.

They are real service definitions rather than commented-out YAML, so
`docker compose config` and CI keep checking them and they cannot quietly break.

## 🛠️ Supported PHP Extensions and Tools

### 📦 PHP Extensions
- **Core Extensions**: GD, Intl, Zip, PDO MySQL, PDO PostgreSQL, SOAP, XSL, BC Math, OPcache, Mbstring, Exif, PCNTL
- **PECL Extensions**: Imagick, Redis, APCu, Xdebug

### 🔨 Development Tools
- **Composer**: PHP dependency manager (pre-installed)
- **Node.js 24 LTS**: via NVM. The version is `NODE_VERSION` in `.env` (only applies when you build your own images)
- **pnpm**: installed alongside npm and preferred; typing `npm` points you at it
- **Git**: Version control
- **Xdebug**: PHP debugging extension
- **Cron**: Task scheduling support

### 🐳 Container Features
- **User Setup**: devuser with sudo privileges
- **Volume Sharing**: Live code editing
- **FPM Configuration**: Optimized for development
- **Error Display**: PHP errors shown in development mode

## 📁 Recommended Project Organization

Create a dedicated folder inside public_html that will contain a symbolic link for each project.
Each symbolic link should point to the project’s public folder (where index.php is located).

```
~/sites/
├── laravel-app   → symbolic link to Laravel’s /public folder
├── symfony-app   → symbolic link to Symfony’s /public folder
└── plain-php     → symbolic link to the folder containing 
```

This setup keeps your project URLs clean. For example:

Laravel app → `laravel-app--site.phpforge.dev`

Symfony app → `symfony-app--site.phpforge.dev`

Plain PHP app → `plain-php--site.phpforge.dev`

### Example: Creating a symbolic link
#### Example for a Laravel project
`ln -s /public_html/projects/laravel-app/public ~/sites/laravel-app`

#### Example for a Symfony project
`ln -s /public_html/projects/symfony-app/public ~/sites/symfony-app`

#### Example for a plain PHP project
`ln -s /public_html/projects/plain-php ~/sites/plain-php`

## 🐛 Troubleshooting

### ❓ Common Issues

- **DNS resolution not working**: Ensure you ran `./setup-local-dns.sh` and restarted your browser or system. You may need to flush DNS cache.
- **PHP version not switching**: check `PHP_VERSION` in `.env` (83, 84 or 85), or append `--p83`/`--p84`/`--p85` to the host. `forge status` prints the default.
- **`npm` prints a message about pnpm**: intentional. npm still runs; pnpm is preferred here.
- **An `.ini` in `custom/php.d/` seems ignored**: recreate the container, `docker compose up -d --force-recreate php84dev`. A restart alone does not re-read it.
- **SSL certificate not trusted**: Make sure you ran `./install_cert.sh` and restart your browser afterwards. Check the CA is present with `openssl verify -CAfile .caroot/rootCA.pem certificates/php-devforge.pem`. Firefox keeps its own trust store on Linux, so install `nss` (Arch) or `libnss3-tools` (Debian/Ubuntu) and re-run the script if Firefox still complains.
- **Containers not starting**: Check that Docker and Docker Compose are installed and running. Ensure ports 80 and 443 are not in use by other services.
- **Permission issues with public_html**: Check that `PUID`/`PGID` in `.env` match your own ids (`id -u`, `id -g`), then recreate the containers with `docker compose up -d --force-recreate`. The containers adopt those ids on startup, so files they write are owned by you.
- **Aliases not working**: Ensure you sourced `aliases.bash` or added it to your `~/.bashrc`.

For more help, check the logs with `docker compose logs` or create an issue on GitHub.

## 🤝 Contributing

We welcome contributions to improve PHP DevForge! Please follow these guidelines:

### ⚙️ Development Setup
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly with different PHP versions and configurations
5. Update documentation if needed

### 📏 Code Standards
- Follow Docker best practices
- Use clear, descriptive commit messages
- Test configurations on multiple platforms (Linux, macOS)
- Ensure backward compatibility

### 🧪 Testing
- Test SSL certificate generation
- Verify DNS resolution works
- Check PHP version switching
- Validate volume mounting and live editing
- Test with different project structures

### 📚 Documentation
- Update README for new features
- Document configuration options
- Provide examples for common use cases
- Keep installation instructions current

### 📤 Submitting Changes
1. Ensure all tests pass
2. Update CHANGELOG.md if applicable
3. Submit a pull request with detailed description
4. Address review feedback promptly

### 🐛 Reporting Issues
- Use GitHub issues for bug reports
- Include your OS, Docker version, and PHP version
- Provide steps to reproduce
- Attach relevant logs and configuration files

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 💬 Support

For questions or issues:
- Check the troubleshooting section in documentation
- Search existing GitHub issues
- Create a new issue with detailed information
