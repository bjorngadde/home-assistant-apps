# Caddy

Runs the official [Caddy](https://caddyserver.com/) image (pinned by digest) as the HTTPS reverse
proxy for Home Assistant and the other apps in this repository. It replaces the NGINX Home
Assistant SSL proxy app.

| | |
| --- | --- |
| Port | 443/tcp, published on the host. Forward 443 on the router here. |
| Certificates | `/ssl`, read-only (for example from the Let's Encrypt app). |
| Configuration | `/share/caddy/Caddyfile`, read-only. |
| State | `/data` (Caddy's own storage; nothing to back up). |

## Setup

1. Copy the [reference Caddyfile](Caddyfile) to `/share/caddy/Caddyfile`, for example with the
   Samba or File editor app.
2. Check the back-end host names in it against each app's info page (see below).
3. Make sure Home Assistant trusts the proxy. `configuration.yaml` needs:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 172.30.33.0/24
   ```

   That is the same network the NGINX app used, so an existing setup already has it.
4. Start the app and read its log. Without the Caddyfile it stops with a message saying so.

Only one app can own port 443. Stop the NGINX app before starting this one, or give this app a
different host port while you test.

## The Caddyfile

The copy in git is the reference. The app reads `/share/caddy/Caddyfile`; edit that file, then
bring the change back into the repository. Caddy watches the file: saving applies the change, and
a broken change is logged while the running configuration stays in place.

Other apps on Home Assistant's internal network are reached by host name,
`<repo-hash>-<slug with dashes>`, for example `38f2f41e-bankmcp`. The hash depends on the exact
URL the repository was added with, so check the app's info page. Home Assistant Core is at
`homeassistant.local.hass.io:8123`, and apps on the host network (frps) at `172.30.32.1`.

The reference file:

- loads the wildcard certificate from `/ssl` for every site, so Caddy never requests
  certificates itself and needs no port 80;
- serves HTTP/1.1 and HTTP/2 only, since UDP 443 (HTTP/3) is not published;
- writes no access log and drops request URIs from error entries, so secret paths are never
  logged;
- streams MCP responses without buffering.

## Certificate renewal

Caddy reads certificate files only when it loads its configuration. The app checks
`/ssl/fullchain.pem` every hour and reloads Caddy when it changes, so a renewed certificate is
served within an hour.
