# The official Caddy image, pinned by digest; Renovate keeps it current.
FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0

COPY run.sh /run.sh

# Caddy's admin API answers on localhost while Caddy is running.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:2019/config/ || exit 1

ARG BUILD_VERSION
ARG BUILD_ARCH
LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Home Assistant App: Caddy" \
    org.opencontainers.image.source="https://github.com/bjorngadde/home-assistant-apps"

ENTRYPOINT []
CMD ["/run.sh"]
