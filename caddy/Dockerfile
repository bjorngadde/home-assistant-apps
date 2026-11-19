# The official Caddy image, pinned by digest; Renovate keeps it current.
FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0

COPY run.sh /run.sh

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
