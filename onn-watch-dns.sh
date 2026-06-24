#!/usr/bin/env bash
# onn-watch-dns.sh — live-log every DNS query the hotspot clients make, so you can see
# exactly which update host the device hits and confirm it's blackholed (or spot one to add).
# Usage:  sudo ./onn-watch-dns.sh on    # enable query logging + watch
#         sudo ./onn-watch-dns.sh off   # disable query logging
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 on|off"; exit 1; }
CONF=/etc/NetworkManager/dnsmasq-shared.d/zz-logqueries.conf

case "${1:-on}" in
  on)
    echo "log-queries" > "$CONF"
    nmcli connection up OnnHotspot >/dev/null 2>&1; sleep 2
    echo "Watching DNS. Trigger an update check on the device. Ctrl-C to stop."
    echo "  'config <host> is 0.0.0.0' = BLOCKED   |   'forwarded <host>' = allowed through"
    journalctl -t dnsmasq -f -o cat 2>/dev/null | grep --line-buffered -iE 'query|config|forwarded|0\.0\.0\.0'
    ;;
  off)
    rm -f "$CONF"; nmcli connection up OnnHotspot >/dev/null 2>&1
    echo "query logging disabled."
    ;;
  *) echo "Usage: sudo $0 on|off"; exit 1 ;;
esac
