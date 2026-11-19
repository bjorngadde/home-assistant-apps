# Changelog

## 1.0.0

- Moved to the `bjorngadde/home-assistant-apps` repository. Home Assistant now
  downloads a prebuilt image instead of building it, so the app gets a new
  slug: install it again and copy your options over.
- The server is built from a pinned commit of `bjorngadde/intervals-icu-mcp`
  (Renovate proposes newer commits), not from `main` at build time.
- Port 8099 is no longer published on the host. Caddy reaches the app over
  Home Assistant's internal network. You can turn the port back on in the
  app's network settings.
- The NGINX snippet is gone; see the Caddyfile in the Caddy app instead.

## 0.4.0

- Upstream changes merged (hhopke/intervals-icu-mcp up to #200):
  - `icu_get_stream_stats` is renamed `icu_get_activity_window_stats`. Update any prompt that
    names the old tool.
  - Intensity factor is reported as a ratio (0.85), not a percentage.
  - Fixes for pace curves, activity interval fields and curves without distance data.
  - Activity details and full search include weather.

## 0.3.0

- New option `delete_mode` (`safe`, `full` or `none`), passed on as `INTERVALS_ICU_DELETE_MODE`.
- New tool `icu_delete_duplicate_activity`, available in `safe` and `full` mode.

## 0.2.0

- Removed the webhook receiver and the `webhook_secret` / `ha_webhook_url` options. The coach
  reads the data directly on each run, so the event log added little. Remove both options from
  your configuration if you had set them.

## 0.1.0

- First version: streamable HTTP on port 8099, secret-URL and OAuth modes, webhook receiver,
  NGINX snippet.
