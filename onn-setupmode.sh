#!/usr/bin/env bash
# onn-setupmode.sh — temporarily blackhole the update CHECK endpoints (not just the
# download) so the setup wizard reports "couldn't check / up to date" and lets you past
# the FORCED update. These hosts are also used for Google sign-in, so:
#   turn ON  -> get past the "checking for updates" step
#   turn OFF -> finish sign-in / device registration  (the permanent gvt1 block stays)
#
# Usage:  sudo ./onn-setupmode.sh on|off
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 on|off"; exit 1; }
CONF=/etc/NetworkManager/dnsmasq-shared.d/zz-setupmode.conf

# Hosts that deliver the "update available" verdict during the wizard.
CHECK_DOMAINS=(android.googleapis.com android.clients.google.com dl.google.com play.googleapis.com update.googleapis.com)

case "${1:-}" in
  on)
    : > "$CONF"
    for d in "${CHECK_DOMAINS[@]}"; do
      printf 'address=/%s/0.0.0.0\naddress=/%s/::\n' "$d" "$d" >> "$CONF"
    done
    nmcli connection up OnnHotspot >/dev/null 2>&1
    echo "SETUP MODE: ON — update check blocked. Run the wizard; if it can't sign in,"
    echo "either SKIP sign-in, or run '$0 off' then Retry to finish registration."
    ;;
  off)
    rm -f "$CONF"
    nmcli connection up OnnHotspot >/dev/null 2>&1
    echo "SETUP MODE: OFF — sign-in/apps restored. OTA download stays blocked (brick-proof)."
    ;;
  *) echo "Usage: sudo $0 on|off"; exit 1 ;;
esac
