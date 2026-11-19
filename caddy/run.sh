#!/bin/sh
# Start Caddy with the Caddyfile from /share/caddy.
#
# Caddy reads certificate files only when it loads its config, so a
# background loop reloads it when the certificate in /ssl is renewed.
# Caddy also watches the Caddyfile itself (--watch): saving a change applies
# it, and a broken change is logged and the running config is kept.
set -eu

CADDYFILE="${CADDYFILE:-/share/caddy/Caddyfile}"
CERTFILE="${CERTFILE:-/ssl/fullchain.pem}"
CERTWATCH_INTERVAL="${CERTWATCH_INTERVAL:-3600}"

log() { echo "[caddy-app] $*" >&2; }

if [ ! -f "${CADDYFILE}" ]; then
    log "${CADDYFILE} not found. Copy the reference Caddyfile from the app's"
    log "documentation there (for example with the Samba or File editor app)."
    exit 1
fi

watch_cert() {
    last="$(stat -c %Y "${CERTFILE}" 2>/dev/null || true)"
    while true; do
        sleep "${CERTWATCH_INTERVAL}"
        current="$(stat -c %Y "${CERTFILE}" 2>/dev/null || true)"
        if [ -n "${current}" ] && [ "${current}" != "${last}" ]; then
            last="${current}"
            log "${CERTFILE} changed, reloading Caddy..."
            caddy reload --config "${CADDYFILE}" --adapter caddyfile --force \
                || log "Reload failed; Caddy keeps the old certificate."
        fi
    done
}

watch_cert &
exec caddy run --config "${CADDYFILE}" --adapter caddyfile --watch
