#!/usr/bin/env bash
# Smoke test for the Intervals.icu MCP app: refuses to start without an auth
# mode, serves /healthz, 404s /mcp, answers MCP initialize on the secret path,
# and never logs the secret.
set -euo pipefail
image="$1"

data=$(mktemp -d)
echo '{"log_level": "info"}' > "$data/options.json"
if timeout 120 docker run --rm -v "$data:/data" "$image" > "$data/out.log" 2>&1; then
    cat "$data/out.log"; echo "::error::the app started without an auth mode"; exit 1
fi
grep -q "No authentication mode configured" "$data/out.log"

data=$(mktemp -d)
secret=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
python3 - "$secret" > "$data/options.json" <<'PY'
import json, sys
print(json.dumps({
    "api_key": "ci-placeholder-api-key",
    "athlete_id": "i1",
    "path_secret": sys.argv[1],
    "log_level": "info",
}))
PY
docker run -d --name intervals-smoke -v "$data:/data" -p 8099:8099 "$image"
trap 'docker logs intervals-smoke 2>&1 | sed -E "s#/[A-Za-z0-9_-]{43}/#/<secret>/#g"; docker rm -f intervals-smoke >/dev/null' EXIT
for _ in $(seq 1 90); do
    curl -fsS http://127.0.0.1:8099/healthz >/dev/null 2>&1 && break
    sleep 2
done
curl -fsS http://127.0.0.1:8099/healthz | grep -q '"ok"'

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8099/mcp)
test "$code" = "404" || { echo "::error::/mcp returned $code, expected 404"; exit 1; }

init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ci","version":"0"}}}'
curl -fsS -X POST "http://127.0.0.1:8099/${secret}/mcp" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -d "$init" | grep -q '"serverInfo"'

docker logs intervals-smoke > "$data/app.log" 2>&1
if grep -qF "$secret" "$data/app.log"; then
    echo "::error::the path secret appeared in the app log"; exit 1
fi
grep -q "modes=secret-path" "$data/app.log"
grep -q "/__secret__/mcp" "$data/app.log"
