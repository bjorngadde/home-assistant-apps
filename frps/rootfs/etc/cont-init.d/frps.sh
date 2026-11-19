#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Render frps.toml and the ingress nginx.conf from the app options
# ==============================================================================

readonly FRPS_CONFIG=/tmp/frps.toml
readonly TOKEN_FILE=/tmp/frps.token
readonly NGINX_CONFIG=/tmp/nginx.conf
readonly USERS_CONFIG=/tmp/frps-users.json
readonly OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
# Must match the frps-users default listen address.
readonly USERS_PLUGIN_ADDR=127.0.0.1:7598
# Must match ingress_port in config.yaml.
readonly INGRESS_PORT=7599
# Only the Supervisor's ingress proxy may talk to the ingress port.
readonly INGRESS_CLIENT="${INGRESS_CLIENT:-172.30.32.2}"

# Quote a value as a TOML basic string.
toml_string() {
    local value="${1//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
}

# Turn "6000-6100, 6200" into TOML allowPorts entries.
allow_ports_toml() {
    local spec="${1// /}"
    local entries=()
    local part
    IFS=',' read -ra parts <<< "${spec}"
    for part in "${parts[@]}"; do
        if [[ "${part}" == *-* ]]; then
            entries+=("{ start = ${part%-*}, end = ${part#*-} }")
        else
            entries+=("{ single = ${part} }")
        fi
    done
    local IFS=','
    printf '[%s]' "${entries[*]}"
}

# auth_token is required without users. With users it's optional: it's then
# only the admin's token, and leaving it out disables the admin login.
auth_token=""
if bashio::config.has_value 'auth_token'; then
    auth_token="$(bashio::config 'auth_token')"
    if [[ ${#auth_token} -lt 16 ]]; then
        bashio::exit.nok "auth_token must be at least 16 characters long."
    fi
fi
# The token lives in its own file, so it never needs escaping in TOML.
printf '%s' "${auth_token}" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"

# internal_only: bind tunnel listeners to the host's address on HA's internal
# Docker network (interface "hassio"), where reverse proxy apps reach it but
# LAN devices don't. Clients still connect on bind_port as before.
proxy_bind_addr="0.0.0.0"
if bashio::config.true 'internal_only'; then
    proxy_bind_addr="${INTERNAL_ADDR:-}"
    if [[ -z "${proxy_bind_addr}" ]]; then
        proxy_bind_addr="$({ ip -4 addr show hassio 2>/dev/null || true; } | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p')"
        proxy_bind_addr="${proxy_bind_addr%%$'\n'*}"
    fi
    if [[ -z "${proxy_bind_addr}" ]]; then
        bashio::exit.nok "internal_only: can't find the internal network address (interface hassio)."
    fi
    bashio::log.info "Tunnels only on the internal network: point your reverse proxy at http://${proxy_bind_addr}:$(bashio::config 'vhost_http_port')"
fi

# Certificate frps presents to frpc, so clients can verify the server.
tls_cert=""
tls_key=""
if bashio::config.has_value 'certfile' || bashio::config.has_value 'keyfile'; then
    if ! bashio::config.has_value 'certfile' || ! bashio::config.has_value 'keyfile'; then
        bashio::exit.nok "Set both certfile and keyfile, or neither."
    fi
    tls_cert="/ssl/$(bashio::config 'certfile')"
    tls_key="/ssl/$(bashio::config 'keyfile')"
    for f in "${tls_cert}" "${tls_key}"; do
        [[ -f "${f}" ]] || bashio::exit.nok "Certificate file ${f} not found."
    done
    bashio::log.info "Using certificate ${tls_cert} for frpc connections."
else
    bashio::log.warning "No certfile set: frps uses a self-signed certificate, so frpc can't verify the server. See the docs."
fi
# Read by the certwatch service, which restarts frps when the cert renews.
printf '%s' "${tls_cert}" > /tmp/frps-certfile

dashboard_port="$(bashio::config 'dashboard_port')"
if [[ "${dashboard_port}" -eq "${INGRESS_PORT}" || "${dashboard_port}" -eq "${USERS_PLUGIN_ADDR##*:}" ]]; then
    bashio::exit.nok "dashboard_port ${dashboard_port} is reserved by the app."
fi

# Users: written as JSON for the frps-users plugin, which frps only calls when
# at least one user is configured.
jq --arg admin "${auth_token}" '{
    admin_token: $admin,
    users: [(.users // [])[] | {
        name,
        token,
        subdomains: ((.subdomains // "") | split(",")
            | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase)
            | map(select(length > 0)))
    }]
}' "${OPTIONS_FILE}" > "${USERS_CONFIG}"
chmod 600 "${USERS_CONFIG}"
user_count="$(jq '.users | length' "${USERS_CONFIG}")"
if [[ "${user_count}" -gt 0 ]]; then
    frps-users -check -config "${USERS_CONFIG}" \
        || bashio::exit.nok "Invalid users configuration."
    bashio::log.info "Users: $(jq -r '[.users[].name] | join(", ")' "${USERS_CONFIG}")"
    bashio::log.info "Users mode: clients sign in with metadatas.token (auth.token must be empty)."
    if [[ -z "${auth_token}" ]]; then
        bashio::log.info "No auth_token set: admin login is disabled, everyone signs in as a user."
    fi
elif [[ -z "${auth_token}" ]]; then
    bashio::exit.nok "Set auth_token (or add users) so clients can sign in."
fi

# The dashboard always runs, because the sidebar panel shows it. Without a
# dashboard password it only listens on localhost, with random credentials
# that only the ingress proxy knows.
if bashio::config.has_value 'dashboard_password'; then
    dashboard_addr="0.0.0.0"
    dashboard_user="$(bashio::config 'dashboard_user')"
    dashboard_password="$(bashio::config 'dashboard_password')"
    bashio::log.info "Dashboard available on the LAN at port ${dashboard_port}."
else
    dashboard_addr="127.0.0.1"
    dashboard_user="ha-ingress"
    # Fixed-size input: no SIGPIPE, which would abort under bashio's pipefail.
    dashboard_password="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
    bashio::log.info "Dashboard only in the sidebar (set dashboard_password to open it on the LAN)."
fi

{
    echo 'bindAddr = "0.0.0.0"'
    echo "bindPort = $(bashio::config 'bind_port')"
    echo "transport.tls.force = $(bashio::config 'force_tls')"
    if [[ -n "${tls_cert}" ]]; then
        echo "transport.tls.certFile = $(toml_string "${tls_cert}")"
        echo "transport.tls.keyFile = $(toml_string "${tls_key}")"
    fi
    echo 'detailedErrorsToClient = false'
    echo
    echo 'auth.method = "token"'
    if [[ "${user_count}" -gt 0 ]]; then
        # frps derives the control-channel key from auth.token, so all
        # clients must share it: keep it empty and let the users plugin check
        # each client's metadatas.token instead. TLS still encrypts the link.
        echo 'auth.token = ""'
    else
        echo 'auth.tokenSource.type = "file"'
        echo "auth.tokenSource.file.path = $(toml_string "${TOKEN_FILE}")"
    fi
    echo
    echo "proxyBindAddr = $(toml_string "${proxy_bind_addr}")"
    echo "vhostHTTPPort = $(bashio::config 'vhost_http_port')"
    if bashio::config.has_value 'subdomain_host'; then
        echo "subDomainHost = $(toml_string "$(bashio::config 'subdomain_host')")"
    fi
    if bashio::config.has_value 'allow_ports'; then
        echo "allowPorts = $(allow_ports_toml "$(bashio::config 'allow_ports')")"
    fi
    echo "maxPortsPerClient = $(bashio::config 'max_ports_per_client')"
    echo
    echo "webServer.addr = $(toml_string "${dashboard_addr}")"
    echo "webServer.port = ${dashboard_port}"
    echo "webServer.user = $(toml_string "${dashboard_user}")"
    echo "webServer.password = $(toml_string "${dashboard_password}")"
    if [[ "$(bashio::config 'metrics_port')" -gt 0 ]]; then
        echo 'metricsServer.addr = "0.0.0.0"'
        echo "metricsServer.port = $(bashio::config 'metrics_port')"
    fi
    echo
    echo 'log.to = "console"'
    echo "log.level = $(toml_string "$(bashio::config 'log_level')")"
    echo 'log.disablePrintColor = true'
    # Tables must come last: keys after them would belong to the table.
    if [[ "${user_count}" -gt 0 ]]; then
        echo
        echo '[[httpPlugins]]'
        echo 'name = "users"'
        echo "addr = $(toml_string "${USERS_PLUGIN_ADDR}")"
        echo 'path = "/handler"'
        echo 'ops = ["Login", "NewProxy"]'
    fi
} > "${FRPS_CONFIG}"
chmod 600 "${FRPS_CONFIG}"

if ! bashio::config.has_value 'allow_ports'; then
    bashio::log.warning "allow_ports is empty: clients may open any port on this host."
fi

frps verify -c "${FRPS_CONFIG}" > /dev/null \
    || bashio::exit.nok "Generated frps configuration is invalid."

# Ingress proxy for the sidebar panel. It adds the dashboard credentials, so
# the panel never shows a login prompt, and fixes frps' absolute redirect
# from / to /static/, which would otherwise escape the ingress path.
basic_auth="$(printf '%s:%s' "${dashboard_user}" "${dashboard_password}" | base64 | tr -d '\n')"
cat > "${NGINX_CONFIG}" <<EOF
daemon off;
worker_processes 1;
pid /tmp/nginx.pid;
error_log stderr warn;

events {
    worker_connections 64;
}

http {
    access_log off;
    server_tokens off;
    client_body_temp_path /tmp/nginx-client-body;
    proxy_temp_path /tmp/nginx-proxy;

    server {
        listen ${INGRESS_PORT};
        allow ${INGRESS_CLIENT};
        deny all;
        absolute_redirect off;

        location = / {
            return 302 static/;
        }

        location / {
            proxy_pass http://127.0.0.1:${dashboard_port};
            proxy_http_version 1.1;
            proxy_set_header Authorization "Basic ${basic_auth}";
            proxy_hide_header WWW-Authenticate;
        }
    }
}
EOF
chmod 600 "${NGINX_CONFIG}"
