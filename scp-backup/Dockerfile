ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG C.UTF-8

RUN apk add --no-cache \
    bash \
    openssh-client \
    curl \
    jq \
    coreutils \
    dcron

COPY rootfs /
COPY src /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh && \
    chmod +x /etc/services.d/scp-backup/run && \
    chmod +x /etc/services.d/scp-backup/finish

LABEL \
    org.opencontainers.image.title="SCP Backup" \
    org.opencontainers.image.description="Backup Home Assistant to a remote server via SCP" \
    org.opencontainers.image.source="https://github.com/pagubg/ha-addons" \
    org.opencontainers.image.authors="HA Addon Developer" \
    org.opencontainers.image.licenses="Apache-2.0"
