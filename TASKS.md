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

- [x] **12. The nginx variant is broken and unmaintained** — FIXED
      Decision: repair it. FrankenPHP stays a separate task.
      It had **eight** defects, not one, and being commented out is exactly why none of
      them surfaced:

      | Where | Defect |
      |---|---|
      | Lua | `[0-9]{2}` — `{2}` is not a Lua quantifier |
      | Lua | `\\.` — Lua escapes with `%.` |
      | Lua | `%-p` matches one hyphen; the suffix is `--pNN` |
      | Lua | the domain was unescaped, so `.` matched any character |
      | Lua | `gsub("--", "/")` — `-` is a Lua quantifier; needs `%-%-` |
      | Lua | **no reversal at all** — the core behaviour was missing |
      | `site.conf.tpl` | `default "php${PHP_VERSION}"` lacked the `dev` suffix, pointing at a host that does not exist |
      | `site.conf.tpl` | versions enumerated, so 8.5 was absent |

      Rewritten to mirror the Apache resolver, which is tested. The backend is derived in
      Lua too, so the enumerated `map` is gone and adding a version needs no change here.

      **A phase-ordering bug appeared while testing**, worth remembering:
      `set $backend "$php_backend:9000"` inside the location captured the placeholder,
      because `set` runs in the rewrite phase *before* `rewrite_by_lua_file`. Using
      `fastcgi_pass $php_backend:9000` directly defers it to the content phase.

      Fails closed by design: the placeholder is an unroutable name, so if the Lua ever
      fails to run a `.php` returns 502 instead of being served as a static file — the
      way Apache once leaked source.

      Now a real service behind `profiles: ["nginx"]`, **not commented out**, so
      `docker compose config` and CI keep checking it. It replaces Apache rather than
      joining it: both want ports 80 and 443.

      Verified end to end: welcome page, nested paths (`v2--api--sites`), hyphenated
      names (`laravel-app--sites`), `--p83`/`--p84`/`--p85`, no source leak including
      `--p99`, hidden `.php` returns 403, and `Authorization` reaches PHP. CI builds it,
      swaps Apache out, runs the same assertions, and swaps back.

      **Naming:** called nginx, documented as OpenResty. It is a distribution of nginx so
      the name is not wrong, and it is what people search for — but the docs say plainly
      that stock nginx cannot do this, so nobody swaps the base image and wonders why it
      breaks.

- [ ] **28. FrankenPHP as an optional profile** — deferred, discussed
      Considered while deciding what to do about nginx. It is not another web server but a
      different execution model: PHP embedded in a Caddy-based server, with an optional
      worker mode keeping the app in memory between requests.
      **The catch is the one that made nginx get abandoned in the first place:** no
      `.htaccess`. Caddy has no Lua either, so the host-to-path reversal would need regex
      per depth.
      Sensible as an opt-in `profiles: ["frankenphp"]` for worker-mode performance on
      modern frameworks — never as the default.

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

- [x] **18. Replace the aliases with a real `forge` command** — DONE
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
      - **Agreed already:** it should expose the image mode, e.g. `forge images build`
        / `forge images pull`, so switching does not mean editing `.env` by hand. The
        setting exists (`IMAGE_MODE`, honoured by `pull_policy` on every buildable
        service) and the installer asks for it; only the command is missing.

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

- [x] **24. Customising without conflicting on upgrade** — DONE
      Once people start editing `docker-library/` to add an extension or change a PHP
      setting, `git pull` conflicts. The idea of copying the Dockerfiles to an
      untracked directory was considered and rejected: it trades a loud problem for a
      silent one. A copy made a month ago would still carry the source-code leak, the
      volume permission race and the 8.5 opcache break, with nothing to signal it.

      Three extension points instead, all gitignored, so `docker-library/` never needs
      touching:
      - `custom/php.d/*.ini` — mounted and added to `PHP_INI_SCAN_DIR` *alongside* the
        image's own `conf.d`, not replacing it, so the Xdebug toggle keeps working.
        **No rebuild.** Verified: `memory_limit` went 128M → 777M on a plain restart,
        and `xdebug --force-activate` still loaded on port 9003 afterwards.
      - `docker-compose.local.yml` — appended to `COMPOSE_FILE`, so it loads
        automatically. Verified by adding a Redis service that answered `PONG`.
        Compose **errors on a file listed but missing**, so the installer creates it.

        **CI caught a bootstrap bug here**, and it would have hit real users: the file
        was listed in `.env.example`, but it is gitignored, so a fresh checkout that
        copied `.env.example` to `.env` could not run `docker compose config` at all.
        Now `.env.example` omits it and the installer appends it right after creating
        the file. The first attempt at that fix was itself wrong — the guard grepped for
        the filename anywhere in `.env` and matched the explanatory comment, so the
        append never ran. Anchored to `^COMPOSE_FILE=` instead.
      - The `FROM ghcr.io/.../php:8.4-dev` pattern for extra extensions, documented in
        the README: a few lines that keep inheriting upstream fixes.

- [x] **25. Two extensions were being compiled for nothing** — DONE
      Asked while reviewing customisation: which extensions does the base image already
      ship? Checking turned up two we were recompiling on every build of every version:
      - **`mbstring`** — built into the binary. `php -i` shows `'--enable-mbstring'` in
        the configure command, and `ReflectionExtension` reports the extension version as
        PHP's own, which only happens when it is compiled in.
      - **`opcache`** — the base image already enables it: `docker-php-ext-opcache.ini`
        sits in `conf.d` for 8.3 and 8.4, and 8.5 has it in the binary.

      `docker-php-ext-enable` noticed both were already loaded, warned, and skipped
      writing the ini — so the compile time and the leftover `.so` bought nothing. Three
      versions, now also built for two architectures with arm64 under emulation.

      **This replaces yesterday's fix rather than adding to it.** Task 23 dodged the 8.5
      failure with a version conditional; the real cause was asking for an extension the
      image already had. The conditional is gone:

      ```dockerfile
      && set -- gd intl zip pdo_mysql pdo_pgsql soap xsl bcmath exif pcntl
      ```

      Verified by building 8.5 from scratch: every extension still loaded, opcache
      present, `mb_strlen("ñandú")` = 5. CI now asserts both across all three versions,
      so if a future base image stops shipping them we find out instead of a user.

- [x] **26. README did not match what the project does** — DONE
      Asked directly: is the README up to date? It was not, and parts were **wrong**
      rather than merely missing — worse, because a reader trusts them:
      - "Node.js 19" — replaced yesterday by 24
      - "83 for 8.3, 84 for 8.4" — 8.5 exists now
      - version switching documented only `--p83` / `--p84`
      Undocumented: pnpm, `DNS_PORT`, `setup-local-dns.sh --status/--remove`, and the
      local DNS behaviour of touching only the dev domain.

      Also a real gap in the code, not just the docs: **`aliases.bash` had no 8.5
      shortcuts**. `forge:use:php85`, `forge:exec:php85` and `forge:logs:php85` added and
      tested against a running container.

      New README sections for local DNS and troubleshooting entries for the things that
      look like bugs but are not: the pnpm nudge, and a `custom/php.d` ini needing
      `--force-recreate` rather than a plain restart.

- [x] **27. README redesign, and a Spanish one** — DONE
      The README opened with a paragraph of description and buried the one thing that
      makes the project different. It now leads with the folder-to-URL mapping, shown
      rather than explained, then per-request PHP versions, then a comparison table.

      **A claim was checked before publishing it.** The requested line — *"unlike tools
      built around per-project configuration, PHP DevForge derives domains straight from
      your folder structure"* — is accurate against DDEV, which needs `ddev config` in
      every project. It is **not** accurate against Laravel Herd: its documentation says
      *"You can access every site in a parked path via `<directory-name>.test`"*, so Herd
      derives domains from folders too. Publishing it unqualified would have looked
      uninformed to exactly the audience being addressed.

      The line stayed, and the comparison table carries what is actually unique:
      nested paths at any depth (`v2--api--sites`, where Herd does one level), the PHP
      version chosen per request from the URL, and Linux support. The table also says
      plainly what the others do better, which is more persuasive than pretending
      otherwise.

      `README.es.md` added, written as its own document rather than a literal
      translation, with language switcher links in both. Verified: no broken internal
      anchors, every external link resolves.

      **Note for task 22 (i18n):** this is documentation only. The scripts still speak
      English.

**Task 18 — how it was resolved**

`bin/forge`, with subcommands rather than the old `forge:use:php85` names. The
aliases only worked in bash: zsh handled the colons awkwardly and fish not at all, so
the project silently excluded those users while the README told everyone to use them.

- **Versions are discovered, not listed.** `forge` reads the PHP services out of
  `docker compose config`, so adding `php86dev` makes `forge use 8.6` work with no
  change to the binary. `8.5` and `85` are both accepted; anything else is refused
  with the available list, rather than passed through to docker.
- **`forge install`** now fronts the installer, and `certs` and `dns` front their
  scripts, so there is one entry point instead of five. `install.sh` stays at the repo
  root because that is what a first-time reader looks for.
- **The installer symlinks it into `~/.local/bin`** — a symlink, not a copy, so
  `git pull` updates the command. It checks whether that directory is on `PATH` and
  prints the line to add if not, and refuses to clobber an existing unrelated `forge`.
- **`aliases.bash` became a PATH shim** and documents the old-to-new mapping, since
  the subcommand-only option was chosen over keeping both.

**On the language.** Rust was considered — the honest answer was no, for now. The
command is a wrapper around `docker compose` and `sed` on `.env`; in Rust it would be
`Command::new("docker")` throughout, so the type safety and performance barely apply,
while distribution would mean four platform binaries and a release pipeline. This same
session *removed* a Go toolchain from `install_cert.sh` for the same reason. Worth
revisiting if `forge` ever grows real logic — parsing and validating config, holding
state, a TUI — where `clap` would earn its keep.

Verified from `/tmp`, outside the checkout: `forge use 8.5` changed `.env` **and the
site served PHP 8.5.9**; `forge use 84` switched back. CI exercises the command
directly rather than only its README examples.

- [x] **29. Databases you choose, and a mail catcher** — DONE
      PostgreSQL 16 was the only database, it always started, and it was two majors
      behind. Meanwhile `pdo_mysql` was compiled into every PHP image with **no MySQL
      service to talk to** — a bigger inconsistency than the always-on question.

      Measured before deciding whether to make it optional: Postgres idles at **17 MB**,
      not the 100+ assumed. That is too little to justify breaking startup for people who
      rely on it — so the answer was not "hide it behind a profile" but "offer more, start
      none".

      Five databases now, each behind its own profile, **none running by default**:
      postgres 16/17/18 on ports 5416/5417/5418, mariadb 11.8 LTS and 12 on 3311/3312.
      Ports encode the version so several can run at once. Selected during install, or
      with `forge db list|on|off`, which edits `COMPOSE_PROFILES` in `.env` — verified
      that compose honours that variable from `.env`, including comma-separated values.

      **Mail catcher** (Mailpit) behind the `mail` profile, served at `mail.<domain>`
      so there is no port to remember. `forge mail on|off`.

      Mailpit over MailDev on the numbers: **52 MB against 340 MB**, since MailDev
      carries a Node runtime. Both are actively maintained — MailDev was updated two
      days before this was written, so it is not a maintained-vs-abandoned choice.
      MailHog, despite more stars, has not moved since February 2024. Mailpit's API is
      also what CI uses to read the inbox back.

      **The URL says `mail`, not the tool's name.** The service was first called
      `maildev` while running Mailpit, which would have sent anyone reading `docker ps`
      to the wrong documentation. Now the container is `mailpit` and the URL is neutral,
      so swapping the tool later does not invalidate a bookmarked address.

      Three things that only surfaced by running it:
      - **PostgreSQL 18 changed its mount point.** 16 and 17 take
        `/var/lib/postgresql/data`; 18 wants `/var/lib/postgresql` and refuses to start
        otherwise. It would have shipped broken.
      - **Apache picks the first vhost that matches, in load order — not the most
        specific.** `maildev.conf` lost to `devlocal_https.conf`'s
        `ServerAlias *.${DEV_DOMAIN}`, so the Lua looked for a folder called `maildev`
        and returned 404. Renamed to `010-maildev.conf` to load first. nginx does not
        have this problem: it prefers an exact `server_name` over a regex regardless of
        order.
      - **`set -e` plus `grep` bit again** in `forge db list`: with no
        `COMPOSE_PROFILES` line yet, the grep found nothing, exited 1, and killed the
        command silently. Same trap as the installer's `.env` guard.

      Verified: PHP connects to both databases **by container name over the shared
      network**, mail sent from PHP over SMTP appears in the inbox, and the UI answers at
      `https://maildev.phpforge.dev`. CI covers all of it.

- [x] **30. Short URLs via a sites/ shortcut** — DONE
      Asked whether a single hyphen would make URLs prettier than `--`. It would, and it
      would also make them ambiguous: `my-app-sites` has **three** readings
      (`sites/my-app`, `app-sites/my`, `sites/app/my`) with no way to choose. That is
      the bug fixed in task 7, reintroduced by design. Dots read best but break the
      wildcard certificate — mkcert says so itself: *"X.509 wildcards only go one level
      deep"*. So `--` is not an aesthetic choice; it is what keeps every site on one DNS
      label so a single certificate covers them all.

      The length came from the path, not the separator: `sites/` appeared in every URL.
      Now `sites/` is a **shortcut tried first**, with the full path as the fallback, so
      both work:

      | URL | Serves |
      |---|---|
      | `my-app.<domain>` | `sites/my-app` |
      | `v2--api.<domain>` | `sites/api/v2` |
      | `public--my-app--projects.<domain>` | `projects/my-app/public` |

      Implemented in both resolvers with an `is_dir` helper — opening a directory
      succeeds but reading it fails, which distinguishes them without extra libraries and
      works through symlinks.

      **`forge link <folder> [name]`** publishes a project. Three things it gets right
      that are easy to botch by hand:
      - **Relative links.** The first version made them absolute: correct on the host,
        pointing at nothing inside the containers, which mount the tree elsewhere.
      - **The name.** `basename` gives `public` for every framework, so it falls back to
        the project directory above it.
      - **Refuses folders outside `PROJECTS_DIR`**, which the containers cannot see.

      Considered and rejected: putting `sites/` inside the container's volume to keep the
      host folder tidy. It lives at a root-only path, so `ls` and `rm` would stop working,
      and `docker compose down -v` — a routine command — would silently delete every
      published link while leaving the projects behind.

- [x] **31. CI passed on the branch and failed on main** — FIXED
      Merging turned the same commits red. The step was "databases and mail are
      reachable from PHP", failing with `SQLSTATE[HY000] [2002] Connection refused`.

      The wait loop asked `mariadb-admin ping`, which answers on the **local socket**
      seconds before the server accepts TCP connections and before the init scripts have
      created the user. Measured locally with a fresh volume: ping reported ready at
      **11s**, PHP could actually connect at **17s** — a six-second window where the
      check lied. The branch runs landed outside it; the main run, sharing the runner
      with the image publish, landed inside.

      Now the loop waits for a real PDO connection with the real credentials. There is no
      intermediate signal left to be wrong about.

      **Third time this session with the same shape of mistake**, so it is worth naming:
      | Checked | Should have checked |
      |---|---|
      | "container running" | that a request answers |
      | uid was changed | that the permissions actually work |
      | `mariadb-admin ping` | that a connection succeeds |

      A green branch and a red main is also a reminder that branch CI is not proof:
      timing differs, and the merge runs alongside the publish workflow.

---

## 🧪 Found in the first clean install (2026-08-23)

First run of `./install.sh` from a fresh clone on a wiped machine — no images, no
build cache, no `.env`, no CA. The stack came up and worked. Everything below is
about the parts around it: what the installer asks, what it says at the end, and
what the README explains first.

- [x] **32. The installer asks for the database names but never shows them** — FIXED
      The prompt prints an empty list, so you have to guess:

      ```
      Databases available:
      Which databases? (space separated, or none) [none]:
      ```

      `install.sh:164` runs `docker compose config --profiles`, which needs `.env`
      for variable interpolation. The databases section deliberately runs *before*
      `.env` is written (task 27 moved it there to fix an unbound variable), so the
      command exits 1 and prints nothing. Reproduced:

      | | |
      |---|---|
      | without `.env` | exit 1, no output |
      | with a minimal `.env` | `mail mariadb11 mariadb12 nginx pg16 pg17 pg18 search tools` |

      The `2>/dev/null` hides the failure, so it degrades to a silent empty list
      rather than an error.

      **Worse than reported.** The same command validated the answer, so with an
      empty list every name failed `grep -qx`. Typing the correct name did not help:

      ```
      'pg18'      -> [!] Unknown database, skipped
      'mariadb12' -> [!] Unknown database, skipped
      'basura'    -> [!] Unknown database, skipped
      ```

      The question could not be answered correctly by anyone.

      Fixed by reading the list through an env file that already has values —
      a real `.env` on re-runs, `.env.example` otherwise — and stopping the install
      when that fails instead of offering nothing. Two more things surfaced on the
      way:

      - `--profiles` was never validated at all, so `--profiles=nope` wrote a dead
        profile into `.env`. Now a hard error: nobody is watching a scripted install.
      - The typed answer stripped commas *inside* each word (`d="${d//,/}"`), so
        `pg16,pg17` became `pg16pg17` and was rejected. Now split on commas.

      CI ran `./install.sh --yes`, where the answer defaults to `none` and the
      validation loop never executes — which is why it shipped. The new step asserts
      the printed list actually contains `pg18` and `mariadb12`, and fails on the old
      code. The typed path itself needs a tty and stays uncovered until task 33
      replaces the prompts.

- [x] **33. Free-text prompts where a selectable list belongs** — FIXED
      Two questions expect typed input for a closed set of options:

      - **Images**: `Pull the images or build them? [pull]:` — the paragraph above it
        explains both, but you have to read it all before answering.
      - **Databases**: typing space-separated names you have not been shown.

      Both should be arrow-key selections: highlight an option, see what it does,
      space to toggle for the multi-choice one. No typing, no guessing at names, and
      the explanation attaches to the option instead of sitting in a wall of text
      above the prompt.

      Three prompts became arrow-key menus, in a new `lib/menu.sh`: PHP version,
      images, and one list holding the databases and mail together. The PHP version
      was not in the report but is the same shape of question, and converting it
      retired the hardcoded `case "$PHPV" in 83|84|85)` — the valid set is now
      whatever the compose file defines, the rule `bin/forge` already followed.

      **The option text is read from the compose files, not written by hand.** One
      query for the base images, one per profile; the difference is what that profile
      adds:

      ```
      pg18        postgres:18
      mariadb11   mariadb:11.8        <- the profile name does not tell you the .8
      mail        axllent/mailpit:latest  ->  mail.phpforge.dev
      ```

      Adding postgres 19 makes it appear with no other change. The typed fallback
      keeps its grouped `PostgreSQL / MariaDB` labels, which is the one place those
      words are still spelled out.

      Written for bash 3.2, since macOS ships it: no associative arrays, no
      `mapfile`, integer `read` timeouts only. Falls back to the typed prompts when
      there is no `/dev/tty`, when `TERM` is `dumb`, or with `NO_MENU=1` — the path
      `--yes` and CI already use.

      **This also closes the hole task 32 documented.** CI drives a real pty with
      `python3 -m pty` (already on the runner, unlike `expect`): arrow and digit
      keys, space to toggle, enter to confirm, asserting the resulting `.env`. The
      driver locates each option by reading the drawn menu rather than counting
      keypresses, so adding a database cannot silently break it — the first version
      did count, and would have.

- [ ] **34. The installer's last words send you to `docker compose`, not `forge`**
      It ends with:

      ```
      🎉 Done. Restart your browser so it picks up the new CA.
         Start the environment with: docker compose up -d
      ```

      So the first command anyone learns is the one `forge` exists to replace, and
      `forge help` never gets discovered. It should say `forge start`.

      Located while doing task 33: it is `install_cert.sh:144`, not `install.sh` —
      that one already ends with `forge start`. The installer calls the certificate
      script last, so its closing line is what you actually read.

- [ ] **35. The README teaches `docker compose` in 11 places**
      Same problem, wider. `README.md` lines 133, 269, 318, 322, 368, 401, 433, 436,
      439 and the Spanish equivalents reach for compose where a `forge` subcommand
      exists.

      Make `forge` the documented interface, and say once — near the top — that it
      wraps `docker compose`, so anyone who knows compose knows nothing is hidden and
      the raw commands still work. Where no `forge` equivalent exists yet, that is a
      gap to close, not a reason to document compose.

- [ ] **36. There is no uninstall**
      `install.sh` writes `.env`, generates certificates, installs a CA into the
      system trust store and the NSS stores, symlinks `forge` into `~/.local/bin`,
      creates `~/php-devforge`, and configures systemd-resolved. Undoing that today
      means knowing all of it.

      Wanted: `forge uninstall`, doing the reverse in the reverse order, saying what
      it will touch before touching it, and asking separately about the two things
      that are not ours to assume — the projects directory and the docker volumes
      holding database data.

      Reconstructing this list by hand for the cleanup on 2026-08-22 is what turned
      up the missing pieces: base images, 13.6 GB of build cache, and dangling
      images. An uninstall command should get those right without a person auditing
      `docker system df` afterwards.

- [ ] **37. "How it works" opens with the most advanced thing in the project**
      `README.md:22` starts with the `sites/` folder and hostnames like
      `v2--api.phpforge.dev` — path segments reversed and joined with `--` — before
      saying what the basic rule is. It also shows `my-app.phpforge.dev` there and
      `my-app--sites.phpforge.dev` further down, which reads like two different
      systems.

      Lead with the plain rule: a folder becomes a URL, nothing to register or
      restart. Then introduce `sites/` as what it is — the shortcut you reach for
      when you want a cleaner URL — rather than as the way it works.

- [x] **38. Profiles are not discoverable from the command line** — FIXED
      `forge help` and `forge db list` both already exist, which is its own evidence
      for tasks 34 and 35: they were never found because nothing points at them.

      `forge db list` also only covers `pg*` and `mariadb*`. The stack has nine
      profiles — `mail`, `nginx`, `search` and `tools` are invisible. Wanted: one
      command that lists every profile with what it starts and whether it is on, so
      the answer does not live only in `docker-compose.override.yml`.

      **Two pieces from task 33 are already sitting there for this.**

      - `profile_images()` in `install.sh` derives what a profile adds by diffing
        `docker compose config --images` against the base set. That is exactly the
        "what it starts" column, and it stays correct on its own — `forge db list`
        could show `pg18  postgres:18` instead of bare `pg18`. It belongs in a shared
        place if both callers want it; `install.sh` also has `compose_with_env()`,
        which only the installer needs (it runs before `.env` exists, while `forge`
        is behind `need_env`).
      - `lib/menu.sh` is sourceable from `bin/forge`, which resolves the same root
        (`bin/forge:9`). If `forge db` should become selectable rather than
        name-argument driven, the menus are written and already exercised by CI.

      Also worth folding in: `db_profiles()` (`bin/forge:123`) swallows errors the
      same way task 32's bug did — `2>/dev/null ... || true`. Every caller is behind
      `need_env` today, so it cannot bite, but this task rewrites that function.

      Done as `forge profile list [filter] | on <name> | off <name>`. `forge db` and
      `forge mail` stay as wrappers — they read well and the installer already names
      them — and `db_profiles()` now fails loudly.

      ```
        mail        ON   mailpit:latest
        nginx       off  nginx:dev            replaces apachedev
        pg18        ON   postgres:18
        search      off  elasticsearch:8.14.2, kibana:8.14.2
        tools       -    mkcert:dev           used by forge certs
      ```

      `compose_with_env()` and `profile_images()` moved out of `install.sh` into
      **`lib/compose.sh`**, joined by `profile_services()`. That **retired
      `compose_service()`**, the hardcoded `pg* -> postgres*dev` rule: the service a
      profile starts is now diffed out of the compose files like everything else.

      **A bug in that move, found before shipping:** the base set was read with
      `.env`'s own `COMPOSE_PROFILES` active, so an already-enabled profile appeared
      on both sides of the diff. `forge profile off pg18` would have reported that
      pg18 starts nothing, and stopped nothing. `compose_with_env()` now clears
      `COMPOSE_PROFILES`; callers ask for one with `--profile`.

      Two profiles are stated rather than detected, with the reason in a comment:
      `nginx` publishes the same 80/443 as `apachedev`, so turning it on stops apache
      and turning it off brings it back; `tools` is a one-shot mkcert run, so turning
      it on is refused and points at `forge certs`. Detecting either means parsing
      ports or restart policies out of YAML with no `jq` guaranteed, and the signals
      lie — postgres has no `restart:` either.

      CI drives the nginx pair through `forge` instead of the manual stop/start dance
      it used to spell out, which is the only case where turning something on turns
      something else off. Elasticsearch is asserted in the listing but deliberately
      not started: the task is discoverability, and a 700 MB pull buys no signal.
---

## 🧪 Found while verifying task 38 against a real local stack

Both surfaced from running the CI steps against running containers rather than
reasoning about them.

- [ ] **39. nginx dies when there is no certificate; Apache degrades**
      A checkout without `certificates/php-devforge.pem` — a fresh clone, or one where
      `install_cert.sh` was skipped — cannot run the nginx variant at all:

      ```
      nginx: [emerg] cannot load certificate "/etc/nginx/ssl/php-devforge.pem":
             BIO_new_file() failed ... no such file
      ```

      The container restarts forever. Apache in the same state comes up fine and
      serves over a self-signed certificate: `docker-library/httpd/Dockerfile:63`
      installs an entrypoint that generates one into `ssl-fallback/`, and
      `devlocal_https.conf:5-13` picks between them with `<IfFile>`. Task 7 gave
      Apache that safety net; nginx never got it.

      `docker-library/nginx/Dockerfile` has no `ENTRYPOINT` at all — only a `CMD`
      that runs `envsubst` over the templates — so there is nowhere the fallback
      could be generated today. `site.conf.tpl:30,53` name the certificate twice.

      Wanted: the same treatment, so a missing certificate is a browser warning
      rather than a container that will not start. Worth checking whether the two
      entrypoints should share one script rather than growing a second copy.

      CI never caught this because it runs `install_cert.sh` before the nginx step,
      so the certificate always exists there.

- [ ] **40. Two checkouts of the project fight over the same containers**
      `COMPOSE_PROJECT_NAME=php-devforge` is a fixed literal in `.env.example:4`, so
      every clone claims the same compose project. Seen for real with a second
      checkout used to test a fresh install:

      ```
      NAME           STATUS        CONFIG FILES
      php-devforge   running(7)    .../php-devforge/docker-compose.yml
                                   .../php-devforge/docker-compose.override.yml
                                   .../test-devforge/docker-compose.yml
                                   .../test-devforge/docker-compose.override.yml
      ```

      Docker treats both directories as one project. Consequences, in rising order
      of damage: `docker compose up -d` from either directory **adopts and recreates
      the other's containers** with its own configuration; `forge stop` in one stops
      the other; and `docker compose down -v` — a documented command — would delete
      database volumes belonging to a checkout the person was not even in.

      Cloning twice is not exotic: it is how anyone would test an upgrade without
      touching the setup that works, which is exactly what happened here.

      The ports make them genuinely exclusive anyway, so the goal is not running both
      at once — it is that the second one refuses clearly instead of silently taking
      the first one's containers. Options to weigh: derive the name from the checkout
      directory, keep the literal but have the installer detect an existing project
      pointing elsewhere and say so, or both.
