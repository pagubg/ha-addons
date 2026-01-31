FROM alpine:latest

ENV LANG C.UTF-8

RUN apk add --no-cache \
    bash \
    openssh-client \
    curl \
    jq \
    coreutils \
    dcron \
    git

RUN mkdir -p /usr/lib/bashio && \
    curl -sSL https://github.com/hassio-addons/bashio/archive/master.tar.gz | tar xzf - -C /tmp && \
    cp -r /tmp/bashio-master/lib/* /usr/lib/bashio/ && \
    rm -rf /tmp/bashio-master

ENV PATH="/usr/lib/bashio:${PATH}"

COPY src /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/usr/local/bin/main.sh"]

LABEL \
    org.opencontainers.image.title="SCP Backup" \
    org.opencontainers.image.description="Backup Home Assistant to a remote server via SCP" \
    org.opencontainers.image.source="https://github.com/pagubg/ha-addons" \
    org.opencontainers.image.authors="pagubg" \
    org.opencontainers.image.licenses="Apache-2.0"
