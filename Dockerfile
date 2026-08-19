FROM alpine:3.23

# bind             - named itself (pulls in bind-tools + dns-root-hints as deps)
# bind-tools       - dig/nslookup/rndc, also used by the healthcheck
# ca-certificates  - trust store
# tzdata           - so TZ env var actually does something
# bash             - entrypoint.sh uses bash features
RUN set -eu; \
    apk update; \
    apk upgrade; \
    apk add --no-cache \
        bind \
        bind-tools \
        ca-certificates \
        tzdata \
        bash; \
    rm -rf /tmp/* /var/cache/apk/*

RUN set -eu; \
    mkdir -p /var/bind /var/log/named; \
    chown -R named:named /var/bind /var/log/named /etc/bind /var/run/named

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

# named.conf and friends (zone stanzas, rndc.key) live here, persisted
# across recreates; zone files go under /var/bind
VOLUME ["/etc/bind", "/var/bind"]

EXPOSE 53/tcp 53/udp 953/tcp

# Confirms named is up and answering queries - independent of whatever
# zones/recursion policy is actually configured (REFUSED still counts as "alive")
HEALTHCHECK --interval=60s --timeout=10s --retries=3 --start-period=30s \
    CMD dig +time=2 +tries=1 @127.0.0.1 -p 53 version.bind CH TXT || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
