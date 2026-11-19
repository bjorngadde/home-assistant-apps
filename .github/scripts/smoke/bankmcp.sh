#!/usr/bin/env bash
# Smoke test for the BankMCP app: it starts with an empty /data and serves
# /healthz on 8080 with the environment from config.yaml.
set -euo pipefail
image="$1"
data="$(mktemp -d)"
docker run -d --name bankmcp-smoke -p 8080:8080 -v "$data:/data" \
    -e BASE_URL=https://bank.example.com -e DATA_DIR=/data -e BIND_HOST=0.0.0.0 "$image"
trap 'docker logs bankmcp-smoke; docker rm -f bankmcp-smoke >/dev/null' EXIT
for _ in $(seq 1 60); do
    curl -fsS http://127.0.0.1:8080/healthz >/dev/null 2>&1 && exit 0
    sleep 2
done
echo "::error::/healthz never answered"; exit 1
