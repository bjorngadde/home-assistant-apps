# BankMCP

A thin Home Assistant app around **[BankMCP](https://github.com/noskillish/bankmcp)** (MIT), an
open-source, read-only MCP server for your own bank accounts. BankMCP talks to banks through
**Enable Banking** (PSD2 account information; the free "restricted production" mode is limited to
the app owner's own linked accounts). claude.ai uses it as a custom connector named **BankMCP**.

The app runs the upstream prebuilt image unchanged and adds Home Assistant packaging and
persistent storage. TLS and the public host name come from the [Caddy app](../caddy/).

## Architecture

```text
claude.ai (custom connector, OAuth via BankMCP's admin password)
   │  https://bank.gadde.nu/mcp
   ▼
Router, port 443 forwarded to Home Assistant
   ▼
Caddy app (bank.gadde.nu site block, wildcard certificate from /ssl)
   │  reverse_proxy <repo-hash>-bankmcp:8080 over HA's internal Docker network
   ▼
BankMCP app, state in /data (HA per-app persistent storage)
   ▼
Enable Banking API (JWT-signed with the app's RSA private key)
   ▼
The banks
```

BankMCP has no host port mapping. Only the reverse proxy reaches it, by its internal host name.
The site block is in the [reference Caddyfile](../caddy/Caddyfile).

## Configuration

There are no app options. The environment is fixed in [config.yaml](config.yaml):

| Variable | Value | Why |
| --- | --- | --- |
| `BASE_URL` | `https://bank.gadde.nu` | Public URL; used for OAuth and the Enable Banking callback. |
| `DATA_DIR` | `/data` | HA's persistent per-app storage. |
| `BIND_HOST` | `0.0.0.0` | Must listen on the internal network so the proxy can reach it. |

## State that is not in git

Everything below lives in the app's `/data` volume and must never be committed:

- the Enable Banking application ID and RSA private key (generated on BankMCP's setup page),
- the admin password (set on the setup page),
- the bank sessions and consents,
- account labels,
- OAuth client registrations (the claude.ai connector).

External configuration:

- **Enable Banking Control Panel:** a production app in restricted mode. Redirect URL
  `https://bank.gadde.nu/callback`; privacy and terms URLs `https://bank.gadde.nu/privacy` and
  `/terms`.
- **claude.ai:** custom connector `https://bank.gadde.nu/mcp`. The `household-finance-review`
  skill refers to the connector and the account labels.

## Moving from the local app

Moving from `/addons/bankmcp` to this repository changes the slug from `local_bankmcp` to
`<repo-hash>_bankmcp`:

1. **New `/data` volume.** Key, consents, password and labels do not follow automatically.
   Either copy the old data directory (`/mnt/data/supervisor/addons/data/local_bankmcp`) into the
   new app's before its first start, or set it up again: re-upload the `.pem` (or register a new
   Enable Banking app), give BankID consent for each bank, set the labels again and re-authorise
   the claude.ai connector.
2. **New host name.** Point the proxy at `<repo-hash>-bankmcp:8080`. The app's info page (or
   `ha apps info <slug>`) shows the exact name.

Uninstall the old local app only once the new one is verified.

## Updating

Renovate opens a pull request when upstream publishes a new image. BankMCP holds a bank key and
upstream is a young one-person project, so read upstream's changes before merging. Merging
publishes a new app version, which shows up as an update in Home Assistant.

## Open improvements

1. **Sign-in and watch notifications.** BankMCP POSTs events (sign-ins, watch triggers) to
   `NOTIFY_WEBHOOK_URL` (checked in upstream's `src/config.ts`). The URL of a Home Assistant
   webhook is a secret, so it cannot go in `config.yaml`; it needs an app option and a small
   start script, or a fixed webhook ID kept out of git.
2. **Backups.** HA backups include this app's `/data` (private key and consents). Make sure they
   are encrypted, or exclude this app.
3. **Visible state (optional).** `map: [addon_config:rw]` with `DATA_DIR=/config` would put state
   under `/addon_configs/<slug>/`, where it can be inspected and backed up deliberately.
4. **Watchdog.** The upstream image has a Docker `HEALTHCHECK` on `/healthz`. Turn the watchdog
   on in the app's UI so Home Assistant restarts the app when it turns unhealthy.

## Operational notes

- **Consent renewal:** consents run 180 days. Renew with the `start_consent` tool and BankID;
  `consent_status` shows the days left.
- **Kill switch:** changing the admin password invalidates all client sessions. Consents can be
  revoked at the banks or in Enable Banking.
- **Rate limit:** PSD2 limits unattended background polling (watches) to about 4 per day per
  account. Interactive queries are not affected.
