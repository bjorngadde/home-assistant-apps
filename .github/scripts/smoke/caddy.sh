#!/usr/bin/env bash
# Smoke test for the Caddy app: the reference Caddyfile is valid, the app
# serves it on 443, and it refuses to start without a Caddyfile.
set -euo pipefail
image="$1"
work="$(mktemp -d)"
mkdir -p "$work/ssl" "$work/share/caddy" "$work/empty"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=*.gadde.nu" \
    -addext "subjectAltName=DNS:*.gadde.nu" \
    -keyout "$work/ssl/privkey.pem" -out "$work/ssl/fullchain.pem" 2>/dev/null
cp caddy/Caddyfile "$work/share/caddy/Caddyfile"

docker run --rm -v "$work/ssl:/ssl:ro" -v "$work/share:/share:ro" "$image" \
    caddy validate --config /share/caddy/Caddyfile --adapter caddyfile

if docker run --rm -v "$work/empty:/share:ro" "$image" > "$work/missing.log" 2>&1; then
    echo "::error::started without a Caddyfile"; exit 1
fi
grep -q "not found" "$work/missing.log"

docker run -d --name caddy-smoke -p 8443:443 \
    -v "$work/ssl:/ssl:ro" -v "$work/share:/share:ro" "$image"
trap 'docker logs caddy-smoke; docker rm -f caddy-smoke >/dev/null' EXIT
for _ in $(seq 1 30); do
    curl -sk -o /dev/null --resolve www.gadde.nu:8443:127.0.0.1 https://www.gadde.nu:8443/ && break
    sleep 1
done
# The back ends don't exist here, so 502 means Caddy routed the request.
code=$(curl -sk -o /dev/null -w '%{http_code}' \
    --resolve intervals.gadde.nu:8443:127.0.0.1 https://intervals.gadde.nu:8443/SMOKESECRET/mcp)
test "$code" = "502" || { echo "::error::expected 502, got $code"; exit 1; }
sleep 1
if docker logs caddy-smoke 2>&1 | grep -q SMOKESECRET; then
    echo "::error::the request path appeared in Caddy's log"; exit 1
fi
