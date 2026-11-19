#!/usr/bin/env python3
"""Bump the version of every app a pull request changes but didn't bump.

Home Assistant only offers an update when an app's version changes, and
Renovate doesn't touch config.yaml. The Bump workflow runs this on Renovate's
pull requests: each changed app whose version still equals the base branch's
gets its last version number raised by one and a CHANGELOG entry.

Usage: bump.py <base-ref> <changelog line>
Prints the bumped apps, one "app old -> new" per line.
"""
import re
import subprocess
import sys
from pathlib import Path

VERSION_LINE = re.compile(r'^(version:\s*)(["\']?)([^"\'\s#]+)\2', re.MULTILINE)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def version_of(text: str) -> str | None:
    m = VERSION_LINE.search(text)
    return m.group(3) if m else None


def next_version(version: str) -> str:
    parts = version.split(".")
    if not parts[-1].isdigit():
        sys.exit(f"Can't bump version {version!r}: the last part is not a number")
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)


def main() -> None:
    base, note = sys.argv[1], sys.argv[2]
    changed = git("diff", "--name-only", f"{base}...HEAD").splitlines()
    apps = sorted({p.split("/")[0] for p in changed if "/" in p and Path(p.split("/")[0], "config.yaml").exists()})
    for app in apps:
        config = Path(app, "config.yaml")
        text = config.read_text()
        current = version_of(text)
        try:
            base_version = version_of(git("show", f"{base}:{app}/config.yaml"))
        except subprocess.CalledProcessError:
            continue  # a new app: its first version is set by hand
        if current is None or current != base_version:
            continue  # already bumped
        new = next_version(current)
        config.write_text(VERSION_LINE.sub(lambda m: f"{m.group(1)}{m.group(2)}{new}{m.group(2)}", text, count=1))
        changelog = Path(app, "CHANGELOG.md")
        entry = f"## {new}\n\n- {note}\n\n"
        log = changelog.read_text() if changelog.exists() else "# Changelog\n\n"
        head, sep, rest = log.partition("\n## ")
        if sep:
            log = f"{head.rstrip()}\n\n{entry}## {rest}"
        else:
            log = f"{log.rstrip()}\n\n{entry}"
        changelog.write_text(log.rstrip() + "\n")
        print(f"{app} {current} -> {new}")


if __name__ == "__main__":
    main()
