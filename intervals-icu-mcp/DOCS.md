# Intervals.icu MCP — Home Assistant app

This app runs the [Intervals.icu MCP server](https://github.com/bjorngadde/intervals-icu-mcp)
as a **remote MCP server** that Claude (web, mobile, desktop and scheduled tasks) can use as a
*custom connector*. It listens on port **8099** on Home Assistant's internal network and is
meant to sit behind the [Caddy app](../caddy/), which provides TLS.

The app **refuses to start** unless at least one authentication mode is configured:

| Mode | Claude connector URL | Uses | Needs |
|---|---|---|---|
| **Secret URL** | `https://<host>/<path_secret>/mcp` | your API key | `api_key`, `athlete_id`, `path_secret` |
| **OAuth** | `https://<host>/mcp` | each athlete's own OAuth token | an approved Intervals.icu OAuth app |

The two modes can run together. Use the secret URL until your OAuth app is approved, then
switch Claude over to OAuth.

## Generating strong secrets

Run one of these on any machine. Each prints a 43-character URL-safe secret:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
```

```bash
openssl rand -base64 32 | tr '+/' '-_' | tr -d '='
```

Store the secret in a password manager.
The app never logs them: the secret path shows up in logs as `/__secret__/mcp`.

## Options

| Option | Mode | Description |
|---|---|---|
| `api_key` | secret URL | Intervals.icu → Settings → *Developer Settings* → API key. |
| `athlete_id` | secret URL | Your athlete ID, for example `i123456`. |
| `path_secret` | secret URL | At least 32 characters from `A–Z a–z 0–9 . _ ~ -`. A shorter value stops the app. |
| `oauth_client_id` | OAuth | Intervals.icu → Settings → Apps → *Manage App*. |
| `oauth_client_secret` | OAuth | Same page. Changing it logs every connected client out. |
| `public_base_url` | OAuth | The public URL the reverse proxy serves, for example `https://intervals.example.com`. |
| `allowed_athlete_ids` | OAuth | Comma-separated athlete IDs that may log in. **Empty rejects everyone.** |
| `scopes` | OAuth | Default `ACTIVITY:READ,WELLNESS:READ,CALENDAR:WRITE,SETTINGS:READ`. It must match what the app allows. |
| `delete_mode` | all | Which delete tools Claude gets: `safe` (default: future events, gear, library items, notes and duplicate activities), `full` (everything, including past events and activities) or `none`. See [Delete Safety Mode](https://github.com/bjorngadde/intervals-icu-mcp/blob/main/docs/tools.md#delete-safety-mode). |
| `log_level` | all | `debug`, `info`, `warning` or `error`. |

State (OAuth clients and tokens, encrypted, mode 0700) is kept
in the app's `/data` directory. It is included in Home Assistant backups.

## Setup — secret URL mode (works today)

1. Set `api_key`, `athlete_id` and a generated `path_secret`. Start the app and check the log
   for `modes=secret-path`.
2. Set up the reverse proxy (see below).
3. In Claude, go to **Settings → Connectors → Add custom connector**. Name it "Intervals.icu",
   enter the URL `https://<host>/<path_secret>/mcp` and leave authentication empty.

Anyone who has that URL can use your Intervals.icu account through the tools. To rotate it, change
`path_secret`, restart the app and update the connector.

## Setup — OAuth mode

1. In Intervals.icu → Settings → Apps → *Manage App*:
   - **Redirect URI:** `https://<host>/auth/callback`, exactly.
   - **Scopes:** at least the ones in the `scopes` option.
   - Optionally tick **Require PKCE**. The app always uses PKCE (S256).
2. Set `oauth_client_id`, `oauth_client_secret`, `public_base_url` (`https://<host>`) and
   `allowed_athlete_ids` (your ID, for example `i123456`). Restart the app and check the log
   for `modes=oauth`.
3. In Claude, go to **Settings → Connectors → Add custom connector** with URL
   `https://<host>/mcp`. Claude registers itself, opens a consent page served by the app, then
   sends you to the Intervals.icu login. Connectors added on claude.ai also work in the mobile
   apps and in scheduled tasks.
4. If the athlete is not in `allowed_athlete_ids`, the login ends on an "Access denied" page and
   the authorisation is revoked again in Intervals.icu.

## Reverse proxy (Caddy app)

The [reference Caddyfile](../caddy/Caddyfile) has a site block for this app. It proxies to the
app's internal host name (`<repo-hash>-intervals-icu-mcp:8099`; the app's info page shows the
exact name) and passes on the `X-Forwarded-*` headers. Caddy streams responses without
buffering, writes no access log by default, and the reference file drops request paths from
Caddy's own error log, so secret paths and tokens never land in a log.

Unlike the old NGINX snippet, Caddy has no built-in rate limit, so there is no per-IP limit on
secret-path guesses. A 43-character secret makes guessing impractical anyway; see the open
questions in the repository README.

**Do not forward port 8099 on your router.** It is not published on the host by default. Only
443 (Caddy) should be reachable from the internet.

The app trusts `X-Forwarded-*` only from the Supervisor network (`172.30.32.0/23`). Public URLs
are always built from `public_base_url`, never from request headers.

## Checking that it works

- `https://<host>/healthz` returns `{"status":"ok"}` (no authentication).
- `https://<host>/mcp` returns `401` with a `WWW-Authenticate` header (OAuth mode), or `404`
  (secret-URL mode only).
- `https://<host>/.well-known/oauth-authorization-server` returns JSON in OAuth mode.
- Everything else, including wrong secrets, returns `404`.

## Updating

The image is built by GitHub Actions from a pinned commit of
[`bjorngadde/intervals-icu-mcp`](https://github.com/bjorngadde/intervals-icu-mcp) (`INTERVALS_MCP_REF`
in the [Dockerfile](Dockerfile)). Renovate opens a pull request when the fork's `main` moves on;
merging it publishes a new version, which shows up as an update in Home Assistant. Dependencies
come from the fork's committed `uv.lock` with hash checking.
