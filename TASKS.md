# PHP DevForge — Task List

Working list of what is left to make the project install and run correctly on a
clean machine.

**How to use this file:** each task is a checkbox. Mark it done by putting an `x`
inside the brackets:

```markdown
- [ ] not done yet
- [x] done
```

Tasks marked **💬 DISCUSS FIRST** are not ready to implement — they need a design
decision before any code is written. Do not start those without agreeing on the
approach.

---

## ✅ Done

- [x] **Certificate setup rewritten to run mkcert in a container** — nothing is
      installed on the host any more. `mkcert_install/install_linux.sh` and
      `install_macos.sh` deleted (no more Go toolchain).
      New: `docker-library/mkcert/Dockerfile`, `mkcert` service in `docker-compose.yml`
      behind the `tools` profile.
- [x] **Certificate filename mismatch fixed** — everything now uses `php-devforge.*`.
      Previously `install_cert.sh` wrote `php-devbox.*` while Apache read
      `php-devforge.*`, so HTTPS could never start.
- [x] **The trusted CA is now the CA that signed the certificate** — the old
      `sudo mkcert -install` could trust a different CA than the one used to sign.
      Verified with `openssl verify -CAfile .caroot/rootCA.pem`.
- [x] **CA stored in `.caroot/`, outside the Apache mount** — the CA private key is
      no longer exposed to the web server.
- [x] **PHP containers trust the CA** — fixes `cURL error 60` when one local site
      calls another over HTTPS. `./.caroot:/caroot:ro` + install step in
      `docker-library/php/config_files/docker-php-entrypoint`.
- [x] **Apache self-heals when certificates are missing** — generates a temporary
      self-signed certificate instead of failing to start.
      New: `docker-library/httpd/config_files/docker-entrypoint.sh` + `<IfFile>` in
      `devlocal_https.conf`.
- [x] **Private keys no longer committed to git** — `certificates/` and `.caroot/`
      are gitignored, old `php-devbox.*` untracked.
- [x] **PHP images can be built at all** — `dockerfile:` in `docker-compose.yml`
      pointed at `./docker-library/php/8.3`, which resolves relative to the build
      context and so became `docker-library/php/docker-library/php/8.3`. Also `8.3`
      is a directory, not a file. Now `8.3/Dockerfile`.

---

## 🔴 Blockers

- [x] **19. PHP source code is served as plain text** ⚠️ **SECURITY** — FIXED
      Requesting a `.php` file **directly** returns its source instead of running it:

      ```
      https://sitio.phpforge.dev/            -> PHP 8.4.24 OK        (runs)
      https://sitio.phpforge.dev/index.php   -> <?php echo ...       (LEAKS SOURCE)
      https://sitio--p84.phpforge.dev/index.php -> PHP 8.4.24 OK     (runs)
      ```

      Any project with credentials in a PHP file exposes them to anything that can reach
      the vhost. Found while testing task 5.

      **Cause:** the vhosts pick the FPM backend with
      `<If "reqenv('PHP_VERSION') -eq 84">`. `PHP_VERSION` reaches the request through
      `PassEnv` (mod_env), which runs at the **fixups** phase — *after* `<If>` is
      evaluated. So `reqenv('PHP_VERSION')` is empty, no `SetHandler` is applied, and
      Apache serves the file as a static document.
      - `/` works because mod_dir internally redirects to `/index.php`, and that
        subrequest inherits a `subprocess_env` already filled in by fixups.
      - `--p83`/`--p84` work because `SetEnvIf` (mod_setenvif) runs at
        post-read-request, early enough for `<If>`.

      **Fix applied:** `reqenv('PHP_VERSION')` → `env('PHP_VERSION')` in both vhosts.
      Apache's `env` checks `subprocess_env` first and then the real process
      environment, where `PHP_VERSION` already lives via compose — so it resolves at
      `<If>` evaluation time regardless of when `PassEnv` runs. `SetEnvIf` still wins for
      `--p83`/`--p84` because `subprocess_env` is consulted first.
      Files: `devlocal.conf`, `devlocal_https.conf` (the same block is duplicated in
      both — see task 11).

      **Verified after the fix:**

      | Request | Before | After |
      |---|---|---|
      | `/` | ran | ran |
      | `/index.php` | **leaked source** | runs (200) |
      | `/secreto.php` (with a password inside) | **leaked source** | runs (200) |
      | `http://` on port 80 | **leaked source** | runs (200) |
      | `--p84/index.php` | ran | runs (200) |
      | `--p83/index.php` | ran | routes to php83dev (500 while that container is off — proves the handler is applied) |

      **Second half of the fix — no default handler existed.** Swapping `reqenv` for
      `env` was not enough. The config only *enumerated* versions:

      ```apache
      <If "env('PHP_VERSION') -eq 83"> ... </If>
      <If "env('PHP_VERSION') -eq 84"> ... </If>
      ```

      Any value outside that list — empty, `85`, a typo — matched nothing, so no handler
      was assigned and the source leaked again. Measured: with `PHP_VERSION=` and with
      `PHP_VERSION=85`, `/index.php` returned raw source.

      → A default `SetHandler "proxy:fcgi://php${PHP_VERSION}dev:9000"` now sits above
      the `<If>` blocks (Apache interpolates `${PHP_VERSION}` at startup, the same way the
      vhost already does with `${DEV_DOMAIN}`). The `<If>` blocks still override it for
      `--p83`/`--p84`.
      → The Apache entrypoint now **refuses to start** if `PHP_VERSION` is empty or unset,
      with a clear message, rather than starting in a state that serves source.

      The design now **fails closed**: no value of `PHP_VERSION` can result in a `.php`
      file being served as text.

      | `PHP_VERSION` | Result |
      |---|---|
      | `84` | runs PHP 8.4 |
      | `83` | routes to php83dev |
      | `85` (does not exist) | proxy error, no source |
      | empty | container refuses to start, clear message |
      | unset | container refuses to start, clear message |

      **Note:** this enumeration is also why adding PHP 8.5 means editing both vhosts —
      see tasks 11 and 18.

## 🔴 Blockers — the stack does not start until these are fixed

- [x] **1. dnsmasq cannot bind port 53** — FIXED
      `docker-compose.yml` published `53:53/udp` (= `0.0.0.0:53`), colliding with
      `systemd-resolved`, which holds port 53 on `127.0.0.53`, `127.0.0.54` and
      `172.17.0.1`. Because `apachedev` has `depends_on: dnsmasq`, the whole stack
      stopped there.
      → Now listens on `127.0.0.1:${DNS_PORT:-5354}` and `DNS_PORT` is a setting in
      `.env`. Port 53 is avoided entirely: which port is free differs per machine
      (Ubuntu server often has 53 free, Pi-hole users do not, macOS has 5353 taken),
      so hardcoding any single port is wrong for a project other people install.
      Verified: dnsmasq starts, answers `*.phpforge.dev` → `127.0.0.1`, still forwards
      other domains, and the full chain dnsmasq → php84dev → apachedev now boots and
      serves PHP over HTTPS.
      **Note:** automatic port detection belongs to the installer — see task 7.

- [x] **2. The DNS script hijacks all name resolution on the host** — FIXED
      `setup-local-dns.sh` wrote `Domains=~.`, routing *every* DNS query on the machine
      through the dnsmasq container; stopping the stack meant losing DNS entirely.
      Three problems were found, not one:
      - **A** — `Domains=~.` (global). Now `Domains=~${DEV_DOMAIN}`, a routing domain,
        so only the dev domain goes to dnsmasq.
      - **B** — the script never read `.env`, so it could not know `DEV_DOMAIN`
        (nor the new `DNS_PORT`). It now reads it.
      - **C** — it tried **NetworkManager first**, which on this machine meant
        `nmcli ... ipv4.dns` (global again), bouncing the network connection to apply,
        and `ipv4.dns` cannot express a port. Order is now systemd-resolved first —
        when resolved is active, NetworkManager delegates DNS to it anyway.
      Unsupported systems are now left **untouched** with printed instructions, rather
      than having their DNS rewritten unsafely. Undo is one file:
      `./setup-local-dns.sh --remove`. The ~150 lines of backup/restore are gone,
      because nothing is broken any more. Script went from 376 to ~250 lines.
      Verified: `*.phpforge.dev` → `127.0.0.1` through the normal system resolver
      (wildcard works for any subdomain), **and with dnsmasq stopped github.com,
      wikipedia.org and debian.org all still resolve** — the whole point of the fix.
      Full end-to-end with real DNS (no `--resolve`): `PHP 8.4.24 OK`, `http_code=200`,
      `ssl_verify_result=0`.

---

## 🟠 Broken features

- [x] **3. `forge:current` never works** — FIXED
      It read `$HOME//configs-docker/.env`, a path left over from an older project name
      (with a double slash). The real cause was that the project path was **hardcoded in
      5 separate aliases** — someone renamed the project and missed one. Patching just
      that line would have let the same bug happen again.
      → `aliases.bash` now discovers its own location:
      `PHP_DEVFORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
      One source of truth, and the aliases now work **wherever you clone the project**,
      instead of requiring exactly `$HOME/php-devforge-config`.
      Two extra bugs found in the same file and fixed:
      - `forge:reload` ran `docker-compose up -d` **twice** (copy/paste leftover)
      - every alias did `cd ... && cd -`, which moved the user's terminal. They now run
        in a subshell `( ... )`, so your shell never changes directory.
      Verified from `/tmp`: path resolved correctly, `forge:current` prints
      `Versión actual: PHP 8.4`, and the terminal stays where it was.

- [x] **4. Xdebug port collides with PHP-FPM** — FIXED
      `xdebug.client_port` was 9000, the same port php-fpm listens on. Now 9003, the
      Xdebug 3 default. README updated (it told users to point their IDE at 9000).
      Also removed `xdebug.remote_handler`, a leftover Xdebug 2 setting that Xdebug 3
      ignores. Verified: `xdebug.client_port => 9003`.

- [x] **5. FPM reload uses a hardcoded PID** — FIXED
      `kill -USR2 40` assumed the FPM master is always PID 40. Measured in a running
      container: the master was **PID 1124**. So the signal never arrived and
      **enabling Xdebug never affected web requests** — only the CLI. Users had to
      restart the container without knowing why.
      → New `reload_fpm()` reads `/run/php/php-fpm.pid` (already configured in
      `zz-docker.conf`), falling back to scanning `/proc` for the master, since the
      image has no `ps`, `pgrep` or `pkill`.
      **Gotcha worth remembering:** `kill` exists only as a shell builtin here — there
      is no `/bin/kill` — so `sudo kill` fails with "command not found". The signal must
      go through `sudo sh -c "kill ..."`. That is why the original code used `sh -c`.
      Verified end to end: toggling Xdebug now changes the **web** state
      (`XDEBUG ACTIVO` ⇄ `xdebug apagado`) without restarting the container.

- [x] **6. macOS DNS handling is wrong twice** — FIXED (same rewrite as task 2)
      - It rewrote DNS on every network interface via `networksetup`. Now it writes the
        native per-domain file `/etc/resolver/${DEV_DOMAIN}` with `nameserver` + `port`.
      - `test_dns()` used `nslookup`, which **bypasses** `/etc/resolver` and so reported
        failure even when resolution worked. Now uses `dscacheutil -q host` on macOS and
        `getent hosts` on Linux — both go through the real system resolver.
      Not verifiable here (no macOS machine); the Linux half of the same code path is
      verified. Worth confirming on a Mac before release — see task 15 (CI could run
      this on a macOS runner).

---

## 💬 Needs discussion before implementing

### 7. Interactive installer — DONE

- [x] **Implemented as `install.sh`**

      Asks for domain, projects folder and default PHP version; finds a free DNS port;
      detects `PUID`/`PGID` with `id -u`/`id -g`; writes `.env`; creates the projects
      folder; and offers to run the certificate and DNS steps. Re-running is safe: the
      current `.env` supplies the defaults, and the old one is kept as `.env.backup`.
      Flags for unattended use: `--domain=`, `--projects-dir=`, `--php=`, `--dns-port=`,
      `--yes`, `--skip-cert`, `--skip-dns`. With no terminal it refuses to run rather
      than silently accepting defaults.

      **Config split:** `.env` is now generated and gitignored; `.env.example` is the
      tracked template. This also fixes `forge:use:php83` dirtying the git tree on every
      PHP version switch, and stops personal values (domain, uid, paths) being committed.
      Anyone with an existing clone will see `.env` drop out of version control; their
      local file is untouched.

      **Projects folder:** `PROJECTS_DIR` on the host, `~/php-devforge` by default,
      mounted at the fixed `/home/php-devforge/public_html` inside the containers — so
      Apache, the Lua resolver and PHP need no changes. Only 2 lines in compose. The
      installer creates `projects/` for code and `sites/` for symlinks, plus a
      `sites/welcome` test page. No `sudo` at any point, thanks to task 8.

      **Bug found while testing — hyphens in project names were broken.** The Lua split
      the host with `[^%-%-]+`, which is "not a hyphen", not "split on `--`". So:

      | Host | Resolved to | |
      |---|---|---|
      | `mi-app--sites` | `sites/app/mi` | wrong |
      | `laravel-app--sites` | `sites/app/laravel` | wrong |
      | `miapp--sites` | `sites/miapp` | fine |

      **All three examples in the README** (`laravel-app`, `symfony-app`, `plain-php`)
      were broken, and had been all along. Fixed by replacing `--` with a sentinel that
      cannot occur in a hostname before splitting. Verified: `mi-app--sites`,
      `laravel-app--sites`, `a--b--c` and `mi-app--sites--p83` all resolve correctly.

      **README updated:** installer flow, the new folder layout, the warning that
      symlinks must point inside `PROJECTS_DIR`, and the clone path is no longer forced
      (aliases resolve their own location since task 3).

<details>
<summary>Original open questions (kept for the record)</summary>

Goal: replace the manual README steps with `./install.sh`, which asks for the
settings and does the setup.

Rough idea (**not agreed yet**):

```
Development domain?              [phpforge.dev]
Where will your projects live?   [~/sites]
Default PHP version?             [8.4]
Generate SSL certificates now?   [Y/n]
Configure local DNS now?         [Y/n]
```

Good news on scope: the projects folder appears in 10 places, but only **2 are the
host side** (`docker-compose.yml:12,58`). Everything else is the path *inside* the
container and does not need to change:

```yaml
- ${PROJECTS_DIR}:/home/php-devforge/public_html
  └── configurable ──┘└── leave as is ──┘
```

**Open questions to settle first:**

- Interactive prompts only, or also flags (`--domain=`, `--projects-dir=`) so it can
  run unattended / in CI?
- Should it be safe to re-run? Update an existing `.env` or refuse to overwrite?
- Should `.env` become a generated file (gitignored) with a tracked `.env.example`?
  This would also fix the fact that `forge:use:php83` rewrites a **tracked** file,
  dirtying the git tree on every PHP version switch.
- Should the installer run `install_cert.sh` and `setup-local-dns.sh`, or only write
  configuration and print the commands?
- What default projects folder? `~/sites`? `~/php-devforge/public_html`?
- Should it check prerequisites (Docker running, ports 80/443 free) and fail early
  with a clear message?
- **Agreed already:** the installer must **detect a free DNS port automatically and
  suggest it**, then write it to `.env` as `DNS_PORT` (the user can still change it by
  hand afterwards). The setting already exists; only the detection is missing:

  ```
  Buscando un puerto libre para DNS...
    5354  ocupado
    5355  libre  ✓
  Puerto DNS a usar? [5355]
  ```

  The same idea applies to ports 80 and 443.

</details>
- `aliases.bash` hardcodes `$HOME/php-devforge-config`. Should the installer generate
  the aliases file with the real path, or should the aliases derive it themselves?

### 8. Container user / file ownership — DONE

- [x] **Implemented: the container adopts the host uid at startup (PUID/PGID)**

      Measured first, rather than reasoned about. The host user is uid 1000, the
      container ran as uid 33 (`www-data`), and:
      - a normal user-owned folder was **read-only** to the container
      - `chgrp 33` on your own folder fails without root — which is *why* the README
        demanded `sudo chown`, not laziness
      - `--user 1000:1000` at runtime **killed the container**: uid 1000 had no passwd
        entry, so `$HOME` was empty and the entrypoint failed writing `/.bashrc`
      - `pnpm install` in a plain user folder produced nothing at all

      Publishing prebuilt images was wanted (task 16), so baking the host uid at build
      time was ruled out. Chosen instead: keep the image generic and adjust the uid when
      the container starts.

      **What changed**
      - Dockerfile: the dev user gets **its own group** and defaults to uid/gid 1000
        (the usual first Linux user, so most hosts need no adjustment at all). The
        `sed` rewriting `www-data`'s home in `/etc/passwd` was dropped as vestigial.
      - `USER php-devforge` removed. The container starts as root, which is how the
        official `php:fpm` image works: a root master dropping workers to an
        unprivileged user. That `USER` line was what forced the old `exec sudo` hack.
      - `zz-docker.conf`: workers run as `php-devforge`.
      - The entrypoint adjusts uid/gid, fixes ownership, and no longer needs `sudo`.

      **Two traps found while testing, both from the user asking the right questions**
      - `usermod -u` does **not** chown files outside the home dir, and nvm lives in
        `/usr/local/nvm`. Without an explicit chown, `nvm install` and global npm/pnpm
        packages break — the container would start fine and fail later, confusingly.
      - The ownership fix must run on **every start**, not only when the uid changes. A
        named volume keeps the ownership it was created with: the existing
        `dataphp-devforge` volume was still `www-data 700`, so workers could not
        traverse `/home/php-devforge` and every page returned `File not found`.
        `$HOMEDIR` also needs mode 755, because Apache is a different uid and still has
        to traverse it.
      - The recursive chown deliberately **excludes `public_html`** — that is the
        mounted host folder, and a `chown -R` there would rewrite the ownership of the
        user's real projects.

      **Verified**: containers start; workers run as uid 1000 while the master stays
      root; a file written by PHP over the web is owned by `yostinv` and deletable
      without sudo; `pnpm install` leaves `node_modules` owned by you; `nvm install 22`
      works (v22.23.2); `sudo` still works inside (the sudoers rule is by name, not
      uid); all three host forms serve over HTTPS; it works from a wiped volume; and
      with `PUID=1501` the user, `NVM_DIR` and created files all land on 1501.

      README updated: the `sudo chown yourUser:www-data` step is gone.

      **Unblocks task 7** — the installer can now create the projects folder with no
      sudo at all.

<details>
<summary>Options considered (kept for the record)</summary>

The problem this needs to solve: today the README tells users to run
`sudo chown yourUser:www-data -R /home/php-devforge`. That is confusing for people
installing the project, and it exists only because of how the container user is set up.

Current situation:

- Both PHP Dockerfiles create `php-devforge` with **hardcoded UID/GID 33**
  (`useradd -g 33 -o -u 33`), i.e. `www-data`
- php-fpm itself runs as `www-data` (`zz-docker.conf`)
- Apache also runs as `www-data`
- So host files must be group-owned by GID 33 and group-writable for the containers
  to write to them

Options (**none chosen yet**):

| Option | Idea | Trade-off |
|---|---|---|
| A | Keep UID 33; installer sets group + `setgid` on the projects folder | Small change, but users still have to understand the permission model |
| B | Build images with the host's UID/GID as build args | Ownership just matches, nothing to explain — but images become machine-specific and cannot be shared or published prebuilt |
| C | Keep the image generic, set `user:` at runtime in compose | Flexible, no rebuild — but files baked into the image are owned by the build-time user, which can break writes to paths inside the image |

**Open questions:**

- Do we ever want to publish prebuilt images (GHCR) to save users the ~15 minute
  build? If yes, option B is ruled out.
- Does anything need to run as real `www-data` specifically, or is that incidental?
- macOS handling is different (Docker Desktop maps ownership automatically) — should
  the two platforms behave differently, or pick one approach that works for both?

</details>

**Still open:** none of this was tested on macOS. Docker Desktop maps ownership on its
own there, so PUID/PGID should be harmless, but it is unverified — see task 15 (CI).

---

## 🟡 Quality and maintenance

- [x] **9. Node 19 is end-of-life** — FIXED
      Node 19 was never LTS and lost support in June 2023, three years without security
      patches. Checked nodejs.org rather than guessing: Node 24 (Krypton) is the current
      LTS, last release 2026-08-03. Node 20 is now out of support too.
      → `NODE_VERSION=24`, and it is now exposed in `.env` and passed through
      `docker-compose.yml` as a build arg, the same way `PHP_VERSION` is — so changing it
      no longer means editing the Dockerfile.
      → **pnpm added** (`npm install -g pnpm@${PNPM_VERSION}`, default `latest`). npm ships
      inside Node and cannot be removed, so `config_files/bashrc` defines an `npm` shell
      function that prints `→ this project prefers pnpm: pnpm <args>` to stderr and then
      runs the real npm. It nudges without breaking anything, and only in interactive
      shells, so scripts and tooling are unaffected.
      Verified: `node v24.19.0`, `npm v11.17.0`, `pnpm v11.22.0`, nudge shows on use.

      **Still worth doing:** the Dockerfile clones nvm from its main branch and checks out
      the latest tag, so builds are not reproducible — an nvm change could break the image
      without anything here changing. Pinning the nvm version would fix it.

- [x] **10. The two PHP Dockerfiles are byte-identical** — FIXED
      97 lines each, differing in exactly two lines: the `FROM` and an
      `ARG PHP_VERSION` that **was never used anywhere in the file**. So the only real
      difference was the base image.
      → One `docker-library/php/Dockerfile` with `ARG PHP_VERSION` declared before `FROM`,
      and the version supplied per service from `docker-compose.yml` (`build.args`).
      194 lines → 97. Both `8.3/` and `8.4/` deleted.
      Verified by building both from scratch: `php83dev` → PHP 8.3.33,
      `php84dev` → PHP 8.4.24, and both sites still serve over HTTPS.

      **Adding PHP 8.5 is now one service block in compose** — no new Dockerfile, and no
      vhost change either, since routing became dynamic in task 20.

      **Build arg named `PHP_TAG`, not `PHP_VERSION`.** The user spotted that `.env` holds
      `PHP_VERSION=84` while the image tag needs `8.4`, and asked how that resolved — a
      fair question, because `php:84-fpm` does not exist. It worked only because compose
      hardcodes `"8.4"` in `build.args`, independently of `.env`. Three things carried the
      same name:

      | Name | Value | Meaning | Where |
      |---|---|---|---|
      | `PHP_VERSION` | `84` | default version for sites | `.env`, apachedev |
      | `PHP_TAG` | `8.3` / `8.4` | base image tag | build args |
      | `PHP_VERSION` | `8.4.24` | real PHP version | inside the container, **set by the official php image** |

      The third one is not ours and cannot be renamed, so the build arg became `PHP_TAG`.
      `.env` keeps `PHP_VERSION=84`: changing it to `8.4` would mean touching the Lua, the
      `depends_on` entries and the container names, and the short form already matches the
      URL convention (`--p84`).

- [x] **11. The two Apache vhosts are near-identical** — FIXED
      A diff showed they differed in exactly two things: the port, and the TLS block.
      Everything else — 37 lines — was duplicated, so every routing change had to be
      made twice and could silently drift.
      → Shared body extracted to `/etc/apache2/snippets/devlocal-common.conf`, included
      from both. 93 lines → 56, and `devlocal.conf` is now three lines.

      Two things removed while extracting:
      - `Define DEFAULT_DOCUMENT_ROOT`, replaced with the literal path. Defining the same
        variable from two includes would warn, and the indirection bought nothing for a
        value used once.
      - The `<IfModule mod_lua.c>` / `<IfModule !mod_lua.c>` pair. It was already dead:
        `LuaHookFixups` sits outside any guard (deliberately, task 20), so Apache cannot
        start without mod_lua anyway. The snippet now says so explicitly instead of
        pretending there is a fallback.

      Verified on both vhosts: `configtest` passes, the port 80 vhost picks up
      `ServerName` from the include, and HTTPS **and** plain HTTP serve the welcome page,
      a hyphenated project, `--p83` version selection, and no source leak.

- [ ] **12. The nginx variant is broken and unmaintained** — its Lua uses `[0-9]{2}`
      and `\\.`, which are not valid Lua patterns, and its `gsub("--", "/")` does not
      reverse the path segments the way the Apache version does. It is commented out
      in compose, so nobody notices.
      → Either fix it to match Apache's behaviour, or delete it.

- [x] **13. Replace commented-out services with compose `profiles:`** — DONE
      Elasticsearch and Kibana were ~32 lines of commented YAML. Commented means invisible
      to everything: `docker compose config` never reads it, CI never checks it, and it
      rots unnoticed — which is precisely what happened to the nginx block.
      → Both are now real services behind `profiles: ["search"]`. `docker compose up -d`
      still starts exactly the same set; `docker compose --profile search up -d` adds them.

      Fixed while uncommenting: Kibana's `SERVER_NAME` was `kibana.dev.local`, a domain
      from an older naming scheme, now `kibana.${DEV_DOMAIN}`. Added the missing
      `container_name`, `hostname` and `depends_on`, and restored the `dataes8143dev`
      volume, which was commented out as well.

      **CI now validates every profile** and asserts that none of them leak into the
      default set — so an optional service can neither break silently nor start
      unexpectedly.

      **Not converted:** the commented nginx block in `docker-compose.yml`. That is task
      12, which needs a decision first: fixing it or deleting it. Turning a broken service
      into an easily-enabled profile would make it *more* likely to bite someone.

      Left alone deliberately: `postgres16dev` still starts by default. Moving it behind a
      profile would silently stop starting for people who rely on it — worth doing, but as
      its own decision rather than smuggled into this one.

- [x] **14. `php-fpm.conf` is dead config** — PARTLY. Deleting it would have broken
      token authentication.
      Only 11 of its 26 lines were dead: the `<IfDefine php83>` / `<IfDefine php84>`
      blocks, which never fire because Apache starts with `-D FOREGROUND` and nothing
      else. Those are gone. The rest is load-bearing:
      - `SetEnvIfNoCase ^Authorization$ ... HTTP_AUTHORIZATION=$1` — Apache does **not**
        forward the Authorization header to FastCGI on its own. Proven by removing the
        line and rebuilding: `$_SERVER['HTTP_AUTHORIZATION']` went from
        `Bearer mi-token-secreto` to absent. Without it every Bearer token, JWT and
        Laravel Sanctum request arrives unauthenticated, with nothing else looking wrong.
      - The `<FilesMatch "^\.ph...">` deny, which stops hidden files like `.php` being
        served. Verified: returns 403.
      Also modernised `Order Deny,Allow` / `Deny from all` to `Require all denied`
      (the old syntax needs `mod_access_compat`), and dropped the `<IfModule !mod_php7.c>`
      wrapper, meaningless in an fpm-based image.
      **Both live behaviours are now covered by CI**, since either could regress silently.

- [x] **15. No automated checks** — DONE (first pass)
      `.github/workflows/ci.yml`. Free and unlimited: the repository is public.
      Two jobs:
      - **lint** — `shellcheck --severity=warning` over every script, `hadolint` over the
        Dockerfile at `error` threshold. Running it locally first found a real bug in
        `install.sh` (SC1087: `"$p["` parsed as an array expansion) plus SC2155 in the
        `xdebug` helper; both fixed.
      - **install** — on a clean Ubuntu runner: `./install.sh --yes --skip-dns`, build,
        `up -d`, then assertions. `--skip-dns` leaves the runner's resolver alone;
        `curl --resolve` is used instead. Certificates are **not** skipped, so real TLS
        against the system trust store is exercised.

      Each check maps to a bug this session uncovered, so they cannot come back quietly:

      | Check | Guards against |
      |---|---|
      | welcome page over HTTPS | the stack not starting at all |
      | hyphenated project name | `mi-app--sites` resolving to `sites/app/mi` |
      | `--p83` suffix | version routing regressions |
      | `.php` never returns `<?php` | the source-code leak (HTTPS **and** plain HTTP) |
      | file written by PHP is owned by the host uid | the permission model breaking |

      **The first run failed, and that was the point.** 403 on every page. The named
      volume is shared; `useradd -m` creates the home directory mode 700, so the volume
      was born 700 and Apache — a different uid — could not traverse it. The entrypoint
      chmods it to 755, but it did so *after* a recursive chown of `/usr/local/nvm`
      (tens of thousands of files), and Apache starts in parallel. Invisible locally,
      because PUID there matches the image default so neither step runs. Fixed in the
      image (home is 755 from the start), in the entrypoint (cheap fix first), and in
      the workflow itself, which waited for "container running" — a state that says
      nothing about readiness — instead of polling for a real response.

      **DNS is covered too.** `setup-local-dns.sh` was the last untested piece and the
      one with the widest blast radius: it edits the system resolver, so a bug there
      breaks the user's machine, not just this project. The checks run *after* the
      `--resolve` ones, so a failure points squarely at the DNS work:
      it configures for real; the domain and an arbitrary subdomain resolve through the
      system resolver; `github.com` and `debian.org` still resolve; **they still resolve
      with dnsmasq stopped** (the `Domains=~.` regression, now guarded); pages are served
      without `--resolve`, the path a browser actually takes; and `--remove` leaves DNS
      working. Confirmed along the way that GitHub's Ubuntu runners do run
      systemd-resolved, so the Linux branch is exercised end to end.

      **Annotations are at zero.** The run was green while GitHub still painted six red
      annotations from hadolint findings below the failure threshold — which trains you
      to ignore the panel. Three were fixed (DL4006 pipefail, SC2046, DL3003); three are
      ignored in `.hadolint.yaml`, each with its reason. `actions/checkout` moved to v5.
      The diagnostics step now runs only on failure.

      **Follow-ups:** builds take ~15 min with no layer cache — worth adding, or better,
      pulling published images once task 16 exists. macOS is not covered: GitHub's macOS
      runners have no Docker daemon, so the `/etc/resolver` branch and the PUID/PGID
      behaviour there stay unverified.

- [x] **16. Publish prebuilt images to GHCR** — DONE (pending first publish)
      A fresh install compiled GD, intl and PECL, cloned nvm and installed Node: about
      15 minutes. Images are now published to `ghcr.io/zelti/php-devforge/*`.
      Chosen over Docker Hub after checking the docs: public packages on GHCR are free
      with **no storage, bandwidth or pull limits**, and Actions supplies `GITHUB_TOKEN`
      so there are no secrets to manage. Docker Hub throttles anonymous pulls to about
      100 per 6 hours **per IP** — one shared office or CI address exhausts it for
      everybody, with a `toomanyrequests` error that looks like the project is broken.
      - `.github/workflows/publish.yml`, triggered on pushes to `main` that touch
        `docker-library/**`, plus `workflow_dispatch`. Multi-arch: `linux/amd64` and
        `linux/arm64`, so Apple Silicon pulls a native image instead of building.
      - Every service keeps its `build:` section. Verified that compose **falls back to
        building** when a pull is not possible, so a fresh clone still works before
        anything has been published, and `docker compose build` still rebuilds locally.

      **Not done yet:** the first publish. New GHCR packages are created **private**;
      they must be switched to public once, by hand, in the package settings, or pulls
      fail with a confusing error.

      **Known wart:** the publish matrix lists each PHP version, so adding one means
      editing compose *and* that workflow. Worth generating from compose later.

      **Caught after the fact:** publishing images quietly broke `NODE_VERSION` in `.env`.
      It is a *build* arg, so a pulled image already has Node fixed and the setting does
      nothing for anyone who does not build locally — it used to work only because
      everybody built. The comment in `.env.example` now says so plainly, and the publish
      workflow reads `NODE_VERSION` from `.env.example` so the published default cannot
      drift from what the file documents.

      The same applies to anything else baked at build time: it is configurable for people
      who build, fixed for people who pull. Worth remembering before adding another
      build arg to `.env`.

- [x] **23. PHP 8.5 does not build** — FIXED
      Adding the service was exactly what the refactoring promised: 13 lines in
      `docker-compose.yml`, no new Dockerfile, no vhost change. The image itself fails.

      `docker-php-ext-install` dies with `cp: cannot stat 'modules/*'`. Each extension
      was tested individually against `php:8.5-fpm`, and **opcache is the only one that
      fails** — gd, intl, zip, pdo_mysql, pdo_pgsql, soap, xsl, bcmath, mbstring, exif
      and pcntl all build. It looks like opcache is no longer produced as a shared
      module in 8.5.

      **Confirmed against the official PHP 8.5 UPGRADING notes**, not just measured:
      *"The Opcache extension is now always built into the PHP binary and is always
      loaded"* and *"the build does not produce opcache.so ... anymore"*.

      **Fix:** the Dockerfile asks the base image for its own version, so one file still
      serves every version — duplicating it would have undone task 10:

      ```dockerfile
      && set -- gd intl zip pdo_mysql pdo_pgsql soap xsl bcmath mbstring exif pcntl \
      && if [ "$(php -r 'echo PHP_VERSION_ID;')" -lt 80500 ]; then set -- "$@" opcache; fi \
      && docker-php-ext-install -j"$(nproc)" "$@"
      ```

      `set --` rather than a string variable, so nothing depends on word splitting and
      hadolint stays clean without a new exception. Verified that Docker strips a `#`
      comment placed inside a line continuation, so the explanation can sit next to the
      condition.

      The changelog also warns that `zend_extension=opcache.so` now emits a warning —
      something the empirical test would not have revealed. Checked: no `.ini` in this
      project loads it that way.

      Verified: 8.3.33, 8.4.24 and 8.5.9 all build, all report opcache loaded, and
      `--p83` / `--p84` / `--p85` route correctly **with no configuration change** —
      adding 8.5 was 13 lines in compose, exactly what tasks 10 and 20 were for.
      CI now builds all three versions and asserts both the routing and opcache.

- [x] **17. `aliases.bash` uses `docker-compose` (v1)** — FIXED
      Now uses `docker compose` (v2), matching the scripts. v1 is end-of-life and absent
      on many systems. Done as part of task 3, since it was the same small file.
      The last `docker-compose` mention in `README.md` is gone too, so the project is
      fully on v2.

- [ ] **18. Replace the aliases with a real `forge` command** 💬 DISCUSS FIRST
      Idea from the user: instead of shell aliases, ship a single executable so you can
      run `forge start`, `forge stop`, `forge use 8.3`, `forge logs 8.4`.

      Why it is better than aliases:
      - Aliases only work in **bash**. zsh handles `forge:start` awkwardly and **fish
        cannot use them at all** — so today the project silently excludes those users.
      - No need to `source` anything from `~/.bashrc`.
      - Can have `--help`, validate arguments, and give real error messages.
      - Tab completion becomes possible.
      - Adding a PHP version stops meaning "write two more aliases".

      **Open questions:**
      - Command shape: `forge use 8.3` / `forge exec 8.4`, or keep the old
        `forge:use:php83` names for people already used to them?
      - Where does it get installed — `~/.local/bin`, `/usr/local/bin`, a symlink created
        by the installer (task 7), or just run `./forge` from the project?
      - Delete `aliases.bash`, or keep it a while so existing users are not broken?
      - Should the PHP versions be discovered from `docker-library/php/*/` instead of
        being hardcoded, so a new version needs no code change?
      - Plain bash script, or something else? (bash keeps it dependency-free)

- [x] **20. PHP backend selection is now dynamic** — DONE
      The vhosts enumerated every PHP version (`SetEnvIf` per version + an `<If>` per
      version, duplicated across both vhosts). Adding PHP 8.5 meant editing four places.
      → `resolve_docroot.lua` gained `set_php_handler`, run from `LuaHookFixups`. It
      already parsed the host for the docroot, so it now also derives the backend:
      `--pNN` wins, otherwise `PHP_VERSION` from `.env`. Each vhost is one line.
      **Adding a PHP version is now just building the image — no config change.**

      Tried first and rejected: `SetHandler "expr=..."`, which would be the natural
      Apache way. It does not work for `proxy:` targets — not even with a fixed address;
      Apache treats the whole string as a literal handler name. Verified on 2.4.68.

      Security: the version comes from the Host header, so the Lua captures **exactly two
      digits** and refuses anything else with a 500. A crafted host cannot inject into the
      FastCGI address.

      Verified: no suffix → PHP 8.4.24 (default), `--p84` → 8.4.24, `--p83` → **8.3.33**,
      `--p99` → proxy error with no source leak, and the same over plain HTTP on port 80.
      Empty/unset `PHP_VERSION` still stops the container from starting.

- [x] **21. All comments and script output translated to English** — DONE
      The scripts mixed Spanish and English. Everything user-facing and every comment is
      now English, matching the README, so the project is usable by people who do not
      read Spanish. Touched: `install_cert.sh`, `setup-local-dns.sh`, `aliases.bash`,
      `.env`, `docker-compose.yml`, both vhosts, the Apache and PHP entrypoints, the
      `xdebug` helper, `docker-php-ext-xdebug.ini`, and `docker-library/mkcert/Dockerfile`.
      Comments were also shortened — the reasoning behind each fix lives in this file, not
      in the source.
      **Not touched:** the Spanish comments that were already in the original PHP and
      Apache Dockerfiles (`# Instalar dependencias del sistema`, etc.). Converting those is
      unrelated churn; worth doing in one pass if the project goes public.

- [ ] **22. Multi-language messages (i18n)** 💬 DISCUSS FIRST — *deferred, not for now*
      Idea from the user: let the scripts speak the user's language instead of only
      English. Deliberately postponed until the current task list is finished.

      **Open questions:**
      - How is the language chosen — `$LANG` from the system, a `LANGUAGE=` setting in
        `.env`, or a `--lang` flag?
      - Where do the strings live? Plain bash has no gettext by default; options are a
        `lang/es.sh` file of variables per language, or depending on `gettext`
        (an extra dependency).
      - Which languages to start with — Spanish and English only?
      - Does this cover only the shell scripts, or the README too (`README.es.md`)?
      - Fallback: any missing string must fall back to English rather than print a
        variable name.

