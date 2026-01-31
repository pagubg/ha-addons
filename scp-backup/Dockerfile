FROM alpine:latest

ENV LANG=C.UTF-8

RUN apk add --no-cache \
    bash \
    openssh-client \
    curl \
    jq \
    coreutils \
    dcron

COPY src /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/usr/local/bin/main.sh"]

LABEL \
    org.opencontainers.image.title="SCP Backup" \
    org.opencontainers.image.description="Backup Home Assistant to a remote server via SCP" \
    org.opencontainers.image.source="https://github.com/pagubg/ha-addons" \
    org.opencontainers.image.authors="pagubg" \
    org.opencontainers.image.licenses="Apache-2.0"
