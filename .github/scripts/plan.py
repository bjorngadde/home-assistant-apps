#!/usr/bin/env python3
"""Decide which apps to lint and build, for the Build workflow.

An app is a top-level folder with a config.yaml. On a pull request or push,
only apps whose folder changed are built; a change under .github/ builds all
of them. A manual run builds the apps named in INPUT_APPS, or all of them.

Prints GitHub Actions outputs:
  apps=<JSON list of app folders>
  builds=<JSON list of {app, arch, platform, image, version}>
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

PLATFORMS = {"amd64": "linux/amd64", "aarch64": "linux/arm64"}
ZERO_SHA = "0" * 40


def all_apps() -> list[str]:
    return sorted(p.parent.name for p in Path(".").glob("*/config.yaml"))


def changed_paths(base: str) -> list[str] | None:
    """Files changed since base, or None when base can't be used."""
    if not base or base == ZERO_SHA:
        return None
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", f"{base}...HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout
    except subprocess.CalledProcessError:
        return None
    return out.splitlines()


def select_apps() -> list[str]:
    apps = all_apps()
    if os.environ.get("EVENT") == "workflow_dispatch":
        wanted = os.environ.get("INPUT_APPS", "").split()
        unknown = sorted(set(wanted) - set(apps))
        if unknown:
            sys.exit(f"Unknown apps: {', '.join(unknown)}")
        return wanted or apps
    paths = changed_paths(os.environ.get("BASE", ""))
    if paths is None or any(p.startswith(".github/") for p in paths):
        return apps
    return [a for a in apps if any(p.startswith(f"{a}/") for p in paths)]


def builds_for(app: str) -> list[dict]:
    config = yaml.safe_load(Path(app, "config.yaml").read_text())
    image = config.get("image")
    if not image or "{arch}" not in image:
        sys.exit(f"{app}/config.yaml needs an image with {{arch}} in it")
    out = []
    for arch in config["arch"]:
        if arch not in PLATFORMS:
            sys.exit(f"{app}: unsupported arch {arch}")
        out.append({
            "app": app,
            "arch": arch,
            "platform": PLATFORMS[arch],
            "image": image.replace("{arch}", arch),
            "version": str(config["version"]),
        })
    return out


def main() -> None:
    apps = select_apps()
    builds = [b for app in apps for b in builds_for(app)]
    print(f"apps={json.dumps(apps)}")
    print(f"builds={json.dumps(builds)}")


if __name__ == "__main__":
    main()
