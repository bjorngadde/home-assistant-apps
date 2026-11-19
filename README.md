# Home Assistant apps

Björn Gadde's Home Assistant apps (add-ons), collected in one repository. Home Assistant
downloads prebuilt images from GHCR; nothing is built on the Home Assistant host.

| App | Folder | What it is |
| --- | --- | --- |
| Caddy | [`caddy/`](caddy/) | HTTPS reverse proxy (official Caddy image) for Home Assistant and the apps below. |
| FRP Server | [`frps/`](frps/) | The frp tunnel server, a self-hosted ngrok. |
| BankMCP | [`bankmcp/`](bankmcp/) | Read-only MCP server for our own bank accounts ([upstream](https://github.com/noskillish/bankmcp)). |
| Intervals.icu MCP | [`intervals-icu-mcp/`](intervals-icu-mcp/) | Remote MCP server for Intervals.icu, built from [bjorngadde/intervals-icu-mcp](https://github.com/bjorngadde/intervals-icu-mcp). |

The Lovelace cards live separately in [bjorngadde/homeassistant](https://github.com/bjorngadde/homeassistant) (HACS).

## Add the repository

In Home Assistant, go to **Settings → Apps → App store → ⋮ → Repositories** and add exactly:

```text
https://github.com/bjorngadde/home-assistant-apps
```

The app slugs, and so the apps' internal host names, start with a hash of that URL: `38f2f41e`
for the URL above (for example `38f2f41e-bankmcp`). Adding it with a trailing slash or `.git`
gives a different hash.

## How it is built

- **Images.** Each app's `Dockerfile` starts from an upstream image pinned by digest
  (`image:tag@sha256:…`), never `:latest`. Other upstream inputs are pinned too: the frp release
  (checked against its published SHA-256), and the Intervals.icu server by git commit.
- **Build workflow** ([`build.yaml`](.github/workflows/build.yaml)). On a pull request it lints
  each changed app, builds it for every architecture in its `config.yaml`, and smoke-tests the
  amd64 image ([`.github/scripts/smoke/`](.github/scripts/smoke/)). On `main` it publishes
  `ghcr.io/bjorngadde/<arch>-ha-app-<slug>:<version>`, the image named in `config.yaml`. A
  published version is never overwritten: changing an app without bumping its version fails the
  build on `main`. Changes to Markdown files alone don't build anything.
- **Renovate** ([`renovate.json`](renovate.json)) opens one pull request per app when an upstream
  image, release or commit changes. The [Bump workflow](.github/workflows/bump.yaml) then raises
  that app's version and adds a CHANGELOG line, so merging is all it takes for Home Assistant to
  offer the update.
- **Secret scan** ([`secrets.yaml`](.github/workflows/secrets.yaml)) runs gitleaks over the whole
  history on every pull request and push.
- **Tests** ([`test.yaml`](.github/workflows/test.yaml)) run pytest on [`tests/`](tests/): the
  apps' own code (`tests/<app>/`, such as the Intervals.icu option launcher) and the scripts
  behind the workflows.

To change an app by hand: edit it, bump `version` in its `config.yaml`, add a CHANGELOG entry and
open a pull request.

## Rules

- No secrets, tokens, passwords or account numbers in git. App state lives in each app's `/data`
  in Home Assistant and is never committed.
- Least privilege: no `host_network`, `hassio_api` or `homeassistant_api` unless an app needs it.
  frps is the exception for now (see below).

## One-time setup

1. **Renovate.** Install the [Renovate GitHub app](https://github.com/apps/renovate) for this
   repository. It opens an onboarding pull request; this repository already has its config, so
   merging that is enough.
2. **GHCR visibility.** The first publish creates the packages
   (`amd64-ha-app-caddy` and so on) as private. Home Assistant pulls without credentials, so make
   each one public under **GitHub → Packages → package → Package settings**.
3. **Public repository.** Home Assistant can only add a public repository. Make it public once
   the secret scan has passed on `main`.

## Open questions

- **frps and `host_network`.** frps still uses `host_network: true`. With only port mappings
  (7000 published, 7080 internal), HTTP tunnels through the vhost port keep working, but TCP/UDP
  tunnels on `allow_ports` would need every port mapped in advance, and the `internal_only`
  option would become unnecessary (an unmapped 7080 is internal anyway). Decide whether TCP/UDP
  tunnels are needed, then either keep host networking or switch to port mappings and drop those
  options.
- **Rate limiting.** The old NGINX snippet for Intervals.icu limited each client IP to 10
  requests per second. Caddy has no rate limit without a plugin, which would mean a custom
  Caddy build instead of the official image. The secret path is 43 random characters, so
  guessing it is impractical anyway.
- **Caddy certificates.** Caddy uses the wildcard certificate from the Let's Encrypt app. Caddy
  could request certificates itself with DNS-01 at Websupport, but that also needs a plugin.
- **BankMCP notifications and backups.** See [bankmcp/DOCS.md](bankmcp/DOCS.md#open-improvements).
- **Old repositories.** `bjorngadde/fast-reverse-proxy-ha-app` and the `ha-addon/` folder in
  `bjorngadde/intervals-icu-mcp` can be archived or removed once the apps here are installed.
