# The upstream prebuilt image, used as-is. Pinned by digest because the server
# holds a bank key; Renovate proposes new versions (read upstream's changes
# before merging).
FROM ghcr.io/noskillish/bankmcp:0.1.15@sha256:938b951ca55b7ef36a119f80e64ce4786835fa8d3e3b19a7b07fe273ee667099

ARG BUILD_VERSION
ARG BUILD_ARCH
LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Home Assistant App: BankMCP" \
    org.opencontainers.image.source="https://github.com/bjorngadde/home-assistant-apps"
