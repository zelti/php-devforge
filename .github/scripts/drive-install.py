#!/usr/bin/env python3
"""Answer the installer's menus through a pty, so CI exercises the keys a person
actually presses.

Deterministic on purpose: it never sleeps for a fixed length of time, it waits
for the text that proves the installer is ready for the next key. And it locates
each option by reading the drawn menu rather than counting keypresses, so adding
a database to docker-compose.override.yml cannot silently break it.

    python3 .github/scripts/drive-install.py ./install.sh --skip-cert ...
"""
import os
import pty
import re
import select
import sys
import time

ENTER, SPACE = b"\r", b" "
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
ROW = re.compile(r"^\s*(?:\[[ x]\]|>|\s{3})\s+(\S+)\s")

# What to answer, in order: (text that means the menu is up, what to pick).
# A single-choice menu takes one name; a multi-choice menu takes a list.
STEPS = [
    ("Default PHP version", "85"),
    ("Images", "pull"),
    ("space toggles", ["pg18", "mail"]),
]


def rows(text):
    """Ordered option names, read off the last frame the menu drew.

    Only the last frame: the buffer also holds earlier menus and ordinary
    output, and a line like "    5354 free" is shaped exactly like an option.
    """
    plain = ANSI.sub("", text)
    cut = plain.rfind("enter confirms")
    if cut == -1:
        return []
    out = []
    for line in plain[cut:].splitlines():
        m = ROW.match(line)
        if m and m.group(1) not in out:
            out.append(m.group(1))
    return out


def keys_for(text, want):
    """Digits jump straight to a row, so no keypress counting is needed."""
    names = rows(text)
    multi = isinstance(want, list)
    for name in want if multi else [want]:
        if name not in names:
            raise SystemExit("option %r not in the menu: %s" % (name, names))
        if names.index(name) >= 9:
            raise SystemExit("option %r is at %d, past the digit keys: %s"
                             % (name, names.index(name) + 1, names))
    keys = b""
    for name in want if multi else [want]:
        keys += str(names.index(name) + 1).encode()
        if multi:
            keys += SPACE
    return keys + ENTER


def main():
    cmd = sys.argv[1:]
    if not cmd:
        raise SystemExit("usage: drive-install.py <command> [args...]")

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm"
        os.execvp(cmd[0], cmd)

    buf, out, step = b"", b"", 0
    deadline = time.time() + 300
    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], 1)
        if readable:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            out += chunk
        # A plain "[default]: " prompt is answered the way a person accepting
        # defaults does. Without this the run stalls on the first typed question
        # and every menu marker times out, which says nothing about the menus.
        if buf.rstrip(b" ").endswith(b"]:"):
            os.write(fd, ENTER)
            buf = b""
            continue

        if step < len(STEPS):
            marker, want = STEPS[step]
            if marker.encode() in buf:
                time.sleep(0.2)          # let the frame finish drawing
                try:
                    chunk = os.read(fd, 65536)
                    buf += chunk
                    out += chunk
                except (OSError, BlockingIOError):
                    pass
                os.write(fd, keys_for(buf.decode("utf-8", "replace"), want))
                buf = b""                # a stale frame must not match the next marker
                step += 1

    os.close(fd)
    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    sys.stdout.write(out.decode("utf-8", "replace"))
    sys.stdout.write("\n--- answered %d of %d menus, installer exited %d ---\n"
                     % (step, len(STEPS), code))
    if step != len(STEPS):
        raise SystemExit("a menu never appeared")
    raise SystemExit(code)


if __name__ == "__main__":
    main()
