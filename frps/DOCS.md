# Home Assistant App: FRP Server

Runs [frp](https://github.com/fatedier/frp)'s server, `frps`, on your Home
Assistant host. Together with `frpc` on your laptop it works like a
self-hosted ngrok: you get a public URL such as `https://myapp.example.com`
that tunnels to `localhost:3000` on whatever machine runs `frpc`, wherever
that machine is.

```text
internet ──► router :443 ──► reverse proxy (e.g. Nginx Proxy Manager)
                                   │  *.example.com
                                   ▼
                       frps vhost :7080 ◄── tunnel ── frpc on laptop ──► localhost:3000
                                                ▲
internet ──► router :7000 ──► frps bind :7000 ──┘
```

## Installation

1. In Home Assistant, go to **Settings → Apps → App store**, open the menu
   in the top right and choose **Repositories**.
2. Add `https://github.com/bjorngadde/home-assistant-apps`.
3. Install **FRP Server**. Home Assistant downloads a prebuilt image.
4. Set an **Auth token** (at least 16 random characters), then start the app.

## Configuration

| Option | Default | What it does |
| --- | --- | --- |
| `auth_token` | (required) | Shared secret every `frpc` must present. |
| `bind_port` | `7000` | Port `frpc` connects to. Forward this one in your router. |
| `force_tls` | `true` | Reject clients that don't use TLS. `frpc` uses TLS by default. |
| `vhost_http_port` | `7080` | Plain-HTTP port where frps routes tunnels by host name. Your reverse proxy points here. Don't forward it. |
| `internal_only` | `false` | Serve tunnels only on Home Assistant's internal network. See [Keeping tunnels off your LAN](#keeping-tunnels-off-your-lan). |
| `subdomain_host` | empty | Base domain for tunnels. With `example.com`, a client asking for subdomain `myapp` is served at `myapp.example.com`. |
| `allow_ports` | empty | Ports clients may open for TCP/UDP tunnels, e.g. `6000-6100, 6200`. Empty means any port. |
| `max_ports_per_client` | `0` | Limit on TCP/UDP ports per client. `0` means no limit. |
| `dashboard_port` | `7500` | Port for the frps web dashboard. `7599` is reserved for the sidebar panel. |
| `dashboard_user` | `admin` | Dashboard username for LAN access. |
| `dashboard_password` | empty | Set it to also open the dashboard on the LAN. The sidebar panel works without it. |
| `metrics_port` | `0` | Prometheus `/metrics` and `/healthz` listener. `0` turns it off. |
| `log_level` | `info` | `trace`, `debug`, `info`, `warn` or `error`. |
| `users` | empty | People with their own token and subdomains. See [Users](#users). |

frpc connects to frps over TCP, so forwarding TCP `bind_port` is enough for
HTTP tunnels. UDP is only needed for `type = "udp"` tunnels (forward their
remote ports) or a QUIC/KCP client transport, which this app doesn't enable.

The app uses the host network, so every port above is opened directly on the
Home Assistant host. Make sure none of them collide with other apps.

Only `bind_port` (and any TCP/UDP tunnel ports you allow) should be forwarded
in your router. Keep the dashboard, metrics and vhost ports LAN-only.

## Putting HTTPS in front with the NGINX Home Assistant SSL proxy app

The NGINX app includes extra server files from `/share/nginx_proxy/`. Turn
that on in its configuration:

```yaml
customize:
  active: true
  default: nginx_proxy_default*.conf
  servers: nginx_proxy/*.conf
```

Then create `/share/nginx_proxy/frps.conf`, using the certificate files from
the NGINX app's own `certfile`/`keyfile` options (it must cover the tunnel
names, e.g. a `*.example.com` wildcard):

```nginx
map $http_upgrade $frps_connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 443 ssl;
    server_name *.example.com;

    ssl_certificate     /ssl/fullchain.pem;
    ssl_certificate_key /ssl/privkey.pem;

    client_max_body_size 64m;

    location / {
        proxy_pass http://<home-assistant-ip>:7080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $frps_connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }
}
```

Restart the NGINX app and check its log: a broken file stops NGINX, and with
it remote access to Home Assistant.

Nginx prefers exact names over `*.example.com`, so subdomains that already
have their own server block keep working. Subdomains matched by a regex or by
the default server would be taken over by the wildcard, so check with
`grep -rn server_name /share/nginx_proxy/` first.

## Putting HTTPS in front with Nginx Proxy Manager

frps serves the tunnels as plain HTTP on `vhost_http_port`. Let your reverse
proxy terminate TLS and hand the requests to frps:

1. DNS: make sure `*.example.com` (or `*.t.example.com`) resolves to your
   router.
2. In Nginx Proxy Manager, add a **proxy host**:
   - Domain names: `*.example.com`
   - Forward to `http://<home-assistant-ip>:7080`
   - Turn on **Websockets support**.
3. SSL: request a wildcard certificate. Wildcards need the **DNS challenge**,
   so pick your DNS provider and paste its API credentials.

Nginx prefers exact host names over wildcards, so existing hosts such as
`www.example.com` keep working next to the `*.example.com` catch-all.

## Using it from a client

Install `frpc` (a single binary from the
[frp releases](https://github.com/fatedier/frp/releases)), then:

```toml
# frpc.toml
serverAddr = "example.com"
serverPort = 7000
auth.token = "your-auth-token"

[[proxies]]
name = "myapp"
type = "http"
localPort = 3000
subdomain = "myapp"
```

```sh
frpc -c frpc.toml
# → https://myapp.example.com
```

Proxy names must be unique across all connected clients.

## Keeping tunnels off your LAN

The app uses the host network, so by default `vhost_http_port` (and any TCP
tunnel port) is reachable from every device on your LAN over plain HTTP.
Reverse proxy apps such as the NGINX app run on Home Assistant's internal
Docker network instead, where the host has its own address (normally
`172.30.32.1`).

With `internal_only: true`, frps serves tunnels only on that internal
address. The log shows it at startup:

```text
Tunnels only on the internal network: point your reverse proxy at http://172.30.32.1:7080
```

Use that address in your reverse proxy (e.g. `proxy_pass` in the NGINX
server file) instead of the host's LAN IP. Clients still connect to
`bind_port` as before. TCP tunnels become internal-only too.

## Verifying the server (recommended)

By default frps uses a self-signed certificate on `bind_port`, and frpc
doesn't check the server's certificate unless told to. On a hostile network
someone could then pose as your server and capture client tokens.

1. Set `certfile` and `keyfile` to a certificate in `/ssl` that covers the
   address clients connect to, e.g. the Let's Encrypt app's `fullchain.pem`
   and `privkey.pem` with a `*.example.com` wildcard for `frp.example.com`.
   The app restarts frps by itself when the certificate is renewed.
2. Make every client verify it:

   ```toml
   transport.tls.useSystemCa = true
   ```

   On frpc versions without `useSystemCa`, point at the system CA bundle
   instead, e.g. `transport.tls.trustedCaFile = "/etc/ssl/cert.pem"` on
   macOS. The name checked is `serverAddr`, unless `transport.tls.serverName`
   says otherwise.

## Users

By default everyone shares `auth_token`. To give people their own token
instead, add them under `users`:

```yaml
users:
  - name: anna
    token: a-long-random-token-for-anna
    subdomains: brite, anna-*
```

- `subdomains` is a comma-separated list; `*` is a wildcard. Users can only
  create plain HTTP tunnels on those subdomains: no TCP/UDP ports, no
  `customDomains`, no load-balancing groups.
- Without a user name you are the admin, with `auth_token` as your token and
  no restrictions. With users configured, `auth_token` is optional: leave it
  empty to have no admin login at all and add yourself as a user instead.
- To revoke someone, remove them and restart the app. Their client is
  disconnected and can't sign in again.
- The FRP sidebar panel shows connected clients and traffic per user.

frp derives its connection encryption key from `auth.token`, so all clients
have to share it. With users configured, the app therefore runs frps with an
empty `auth.token` (the connection is still encrypted with TLS) and every
client, you included, signs in with `metadatas.token` instead:

```toml
# a user
serverAddr = "example.com"
serverPort = 7000
user = "anna"
metadatas.token = "a-long-random-token-for-anna"

[[proxies]]
name = "brite-webhook"          # shown as anna.brite-webhook
type = "http"
localPort = 5000
subdomain = "brite"
```

```toml
# the admin: no user, auth_token as metadatas.token
serverAddr = "example.com"
serverPort = 7000
metadatas.token = "your-auth-token"
```

Clients that still set `auth.token` are refused while users are configured.
Removing all users switches back to plain `auth.token`.

With `user` set, frp prefixes proxy names with the user name, so two people
can both have a proxy called `webhook`. Subdomains still have to be unique.

## Inspecting and replaying requests

frps has no ngrok-style request inspector. Run one on the client side
instead, for example mitmproxy's web UI:

```sh
mitmweb --mode reverse:http://localhost:3000 -p 8081
# then point the tunnel at localPort = 8081
```

## Dashboard and metrics

The frps dashboard shows live clients, proxies and per-proxy traffic (7 days
of history). It's in the Home Assistant sidebar as **FRP**, behind your normal
Home Assistant login. If you don't want the panel, turn off **Show in
sidebar** on the app's page.

Without `dashboard_password`, the dashboard listens on localhost only, with
random credentials that only the sidebar panel uses. With a password set, it
is also reachable at `http://<home-assistant-ip>:7500`.

With `metrics_port` set, Prometheus can scrape
`http://<home-assistant-ip>:<metrics_port>/metrics`.
