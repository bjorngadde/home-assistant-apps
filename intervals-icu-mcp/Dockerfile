# Built by GitHub Actions and pulled by Home Assistant as a prebuilt image.
# Every upstream input is pinned (images by digest, the server by commit);
# Renovate keeps them current.
FROM ghcr.io/home-assistant/base-python:3.13-alpine3.24@sha256:c7d34ae22a87275d46deb65bcb0511b389d7bc6eb8dccb28d44dd7cb8616e603

ARG BUILD_VERSION=0.0.0
ARG BUILD_ARCH
ARG INTERVALS_MCP_REPO=https://github.com/bjorngadde/intervals-icu-mcp
# The server's source: a commit on the fork's main branch.
# renovate: datasource=git-refs depName=intervals-icu-mcp packageName=https://github.com/bjorngadde/intervals-icu-mcp branch=main
ARG INTERVALS_MCP_REF=1fd031f8bc9f845ba1158f7e8d0342cb5a02c8b2
# renovate: datasource=pypi depName=uv
ARG UV_VERSION=0.11.32

# The server is fetched from git at INTERVALS_MCP_REF. Dependencies are
# installed from the committed uv.lock with hashes (pip hash-checking mode),
# then the package itself without deps. Every locked dependency ships
# musllinux wheels for amd64 and aarch64.
ENV SETUPTOOLS_SCM_PRETEND_VERSION=${BUILD_VERSION}
RUN set -eux; \
    apk add --no-cache --virtual .build-deps git; \
    git clone --filter=blob:none "${INTERVALS_MCP_REPO}" /tmp/src; \
    git -C /tmp/src checkout --detach "${INTERVALS_MCP_REF}"; \
    pip install --no-cache-dir "uv==${UV_VERSION}"; \
    uv export --project /tmp/src --frozen --no-dev --no-emit-project -o /tmp/requirements.txt; \
    pip install --no-cache-dir --only-binary=:all: -r /tmp/requirements.txt; \
    pip install --no-cache-dir --no-deps /tmp/src; \
    pip uninstall -y uv; \
    rm -rf /tmp/src /tmp/requirements.txt; \
    apk del .build-deps

COPY run.py /run.py

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -m intervals_icu_mcp.healthcheck --port 8099

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Home Assistant App: Intervals.icu MCP" \
    org.opencontainers.image.source="https://github.com/bjorngadde/home-assistant-apps"

CMD ["python3", "/run.py"]
