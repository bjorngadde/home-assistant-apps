# https://contributors.home-assistant.io/apps/guides/dockerfile/
# Built by GitHub Actions and pulled by Home Assistant as a prebuilt image.
# Every upstream image is pinned by digest; Renovate keeps them current.

# frps-users: the server plugin behind the users option (see plugin/).
# Cross-compiled on the build machine, so the arm64 image needs no emulated Go.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280 AS users-plugin
ARG TARGETARCH
WORKDIR /src
COPY plugin/ ./
RUN go test ./... \
    && CGO_ENABLED=0 GOARCH="${TARGETARCH}" go build -trimpath -ldflags="-s -w" -o /frps-users .

FROM ghcr.io/home-assistant/base:3.24@sha256:5021aac8a4b7f2a1397e23a9749dfe9f736463ffa471df6b200216c68d530fe6

# nginx is the ingress proxy for the sidebar panel.
RUN apk add --no-cache nginx

# renovate: datasource=github-releases depName=fatedier/frp
ARG FRP_VERSION=0.72.0
ARG TARGETARCH
RUN \
    if [ -z "${TARGETARCH}" ]; then \
        echo "TARGETARCH is not set, please use Docker BuildKit for the build." && exit 1; \
    fi \
    && case "${TARGETARCH}" in \
        amd64) frp_arch="amd64" ;; \
        arm64) frp_arch="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && frp_name="frp_${FRP_VERSION}_linux_${frp_arch}" \
    && release="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}" \
    && cd /tmp \
    && curl -sSLf -o "${frp_name}.tar.gz" "${release}/${frp_name}.tar.gz" \
    && curl -sSLf -o frp_sha256_checksums.txt "${release}/frp_sha256_checksums.txt" \
    && grep "  ${frp_name}.tar.gz\$" frp_sha256_checksums.txt | sha256sum -c - \
    && tar -xzf "${frp_name}.tar.gz" \
    && install -m 0755 "${frp_name}/frps" /usr/bin/frps \
    && rm -rf "${frp_name}.tar.gz" frp_sha256_checksums.txt "${frp_name}" \
    && cd / \
    && frps --version

COPY --from=users-plugin /frps-users /usr/bin/frps-users

# Copy root filesystem
COPY rootfs /

ARG BUILD_VERSION
ARG BUILD_ARCH
LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Home Assistant App: FRP Server" \
    org.opencontainers.image.description="frp tunnel server (frps), a self-hosted ngrok alternative" \
    org.opencontainers.image.source="https://github.com/bjorngadde/home-assistant-apps" \
    org.opencontainers.image.licenses="Apache License 2.0"
