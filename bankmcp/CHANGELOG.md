# Changelog

## 1.0.0

- Moved from the local app (`/addons/bankmcp`) to the `bjorngadde/home-assistant-apps`
  repository, so the slug changes from `local_bankmcp` to `<repo-hash>_bankmcp`.
  Home Assistant downloads a prebuilt image instead of building it.
- Upstream image pinned to 0.1.15 by digest instead of `:latest` (the same image
  `:latest` pointed to). Renovate proposes newer versions.

## 0.1.0

- First local version, running `ghcr.io/noskillish/bankmcp:latest`.
