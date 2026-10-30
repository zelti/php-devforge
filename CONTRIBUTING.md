# Contributing to PHP DevForge

← [README](README.md) · [Documentation](DOCS.md) · [Español](CONTRIBUTING.es.md)

---

1. Fork the repository and create a branch
2. Make your changes
3. Check that CI passes — it installs and runs the whole thing on a clean machine,
   so it catches a fair amount
4. Open a pull request describing what changes and why

CI builds all three PHP versions, runs the installer, configures DNS, checks that a
`.php` is never served as source, that files created in the containers belong to
you, and that both Apache and nginx serve the same sites. If it is green, it works
somewhere other than your laptop.

## Releasing

The version lives in one file, `VERSION`, and `forge version` prints it with the
commit you are on:

```bash
$ forge version
PHP DevForge 0.1.0 (c45e1f3)
```

To cut one: bump `VERSION` and merge it to `main`. That's the whole step —
tagging and the GitHub Release both happen on their own from there:
a `VERSION` change landing on `main` gets tagged automatically
(`.github/workflows/tag-on-version-bump.yml`), and that tag push creates the
Release (`.github/workflows/release.yml`, `gh release create --generate-notes`).

The notes group themselves by label (`.github/release.yml`): `enhancement`,
`bug`, `documentation` — the same labels the repo ships with. One label per
PR, matching whichever commit prefix it already uses (`feat:`/`fix:`/`docs:`);
a fix found while building a feature stays part of that PR, not a second label.

CI refuses a `VERSION` that is not semver, and a tagged commit whose tag and
`VERSION` disagree — so the two cannot drift.

**Prereleases** work the same way — `VERSION=0.3.0-beta.1` tags and releases
itself identically, except the Release is marked a GitHub prerelease, so it
never shows up as "latest" (on the badge above, or to `forge update`, which
skips any tag with a `-` suffix when picking the newest one). `forge update
--edge` tracks `main` regardless, prerelease or not.

## Running a CI step before you push

A round trip through GitHub is six minutes, and most failures are not in the code
but in the step itself: a flag you passed locally and CI does not, a value an
earlier step was supposed to set, a pipeline that behaves differently under
`pipefail`. So run the step as written instead of retyping it:

```bash
forge start                                   # the steps need the stack up

.github/scripts/run-step.py                   # list every step
.github/scripts/run-step.py "the forge command works"
.github/scripts/run-step.py -x "<name>"       # trace, to find the silent grep
```

It reads `.github/workflows/ci.yml` and runs the step's `run:` block verbatim
under `bash -e`, exactly as GitHub does. Needs PyYAML; it tells you how to
install it if you do not have it.

**Steps are not independent.** Some read fixtures an earlier step created — the
`my-app` project, an enabled database — so when one fails on a missing file, run
the earlier step first. `run-step.py` with no arguments lists them in order.

The steps that fetch a page source `.github/scripts/serve.sh` for two helpers:
`serves <host> <text>` asserts a page contains something, and `serve <host>
<path>` retries for a minute and, when it gives up, says why — the status it got,
what curl said, and what was listening on 443.

**Two kinds of step cannot pass locally**, and that is expected:

| Step | Why | To run it anyway |
|---|---|---|
| the HTTPS ones | `curl` without `-k`, on purpose: it checks the system trust store | `./install_cert.sh` (asks for sudo, installs the CA) |
| the DNS ones | they rewrite the system resolver | `./setup-local-dns.sh` (asks for sudo) |

Everything else runs against your own containers.
