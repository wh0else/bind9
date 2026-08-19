#!/usr/bin/env bash
set -euo pipefail

log() { echo "[entrypoint] $*"; }

BIND_DIR="/etc/bind"
DATA_DIR="/var/bind"
RNDC_KEY="${BIND_DIR}/rndc.key"
CONF="${BIND_DIR}/named.conf"

mkdir -p "$BIND_DIR" "$DATA_DIR"/{pri,sec,dyn}

# --- Timezone ----------------------------------------------------------
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# --- rndc key (generated once, then persisted in the /etc/bind volume) -
# This is a secret, not config, so it's the one thing still generated
# rather than hand-written.
if [ ! -f "$RNDC_KEY" ]; then
    log "generating rndc key"
    rndc-confgen -a -c "$RNDC_KEY" -A hmac-sha256 >/dev/null
fi

# --- named.conf: entirely your file from here on -----------------------
# Seeded once on first boot with a minimal working authoritative-only
# config; never touched again. Edit it (and add named.conf.options /
# named.conf.local alongside it if you want to split things up) directly
# in the /etc/bind volume.
if [ ! -f "$CONF" ]; then
    log "seeding starter ${CONF}"
    cat > "$CONF" <<EOF2
include "${RNDC_KEY}";

controls {
    inet 127.0.0.1 port 953 allow { any; } keys { "rndc-key"; };
};

options {
    directory "${DATA_DIR}";
    pid-file "/var/run/named/named.pid";
    listen-on { any; };
    listen-on-v6 { any; };
    allow-query { any; };
    recursion no;
    dnssec-validation auto;
    allow-transfer { none; };
};

// Zone definitions go here, e.g.:
//
// zone "example.com" {
//     type master;
//     file "/var/bind/pri/example.com.zone";
// };
EOF2
fi

chown -R named:named "$BIND_DIR" "$DATA_DIR" /var/run/named 2>/dev/null || true
chmod 640 "$RNDC_KEY"

log "checking configuration"
named-checkconf "$CONF"

log "starting named in foreground"
exec named -u named -g -c "$CONF"
