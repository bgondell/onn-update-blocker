#!/usr/bin/env bash
# onn-hotspot.sh — turn a Linux laptop into a Wi-Fi hotspot that gives an Android TV /
# Google TV device internet but DNS-blackholes Google's OTA update servers, so a buggy
# forced update can never download (used to stop the onn 4K "update bricks the device" loop).
#
# Works on a SINGLE Wi-Fi radio that supports AP+STA: the hotspot is forced onto the
# uplink's current channel (a kernel requirement for one radio). Needs NetworkManager,
# dnsmasq, iw, and root.
#
# Usage:  sudo ./onn-hotspot.sh up      # create/start the blocking hotspot
#         sudo ./onn-hotspot.sh down    # tear it down
#         sudo ./onn-hotspot.sh fw      # re-apply only the firewall openings
set -uo pipefail

# ----------------------------- CONFIG (edit me) -----------------------------
HOTSPOT_SSID="OnnSetup"
HOTSPOT_PSK="changeme123"        # >= 8 chars — CHANGE THIS
UPLINK_IF=""                     # empty = auto-detect the connected Wi-Fi interface
UPLINK_SSID=""                   # optional: connect uplink to this SSID first (use a 2.4GHz one)
AP_IF="ap0"
# Domains permanently blackholed = the OTA *download* path (keeps the device brick-proof).
# NOTE: gvt1/gvt2 also serve Play app-update binaries, so app updates are blocked too.
BLOCK_DOMAINS=(gvt1.com gvt2.com update.googleapis.com)
# ---------------------------------------------------------------------------
BLOCKFILE="/etc/NetworkManager/dnsmasq-shared.d/block-ota-updates.conf"

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 ${1:-up}"; exit 1; }
[ -z "$UPLINK_IF" ] && UPLINK_IF=$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2=="wifi"&&$3=="connected"{print $1; exit}')
[ -z "$UPLINK_IF" ] && UPLINK_IF=wlan0

# ---- firewall: make AP traffic survive a restrictive firewall / VPN killswitch ----
# (e.g. PIA, UFW with default-DROP policies). Harmless no-ops on an open firewall.
del_marks() {  # $1=table (may contain a space) $2=chain
  local h
  while h=$(nft -a list chain $1 $2 2>/dev/null | awk '/onn-allow/{for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1); exit}}'); [ -n "$h" ]; do
    nft delete rule $1 $2 handle "$h" 2>/dev/null || break
  done
}
firewall_close() {
  del_marks "ip filter" INPUT; del_marks "ip filter" OUTPUT
  del_marks "ip filter" FORWARD; del_marks "ip raw" PREROUTING
}
firewall_open() {
  echo "==> enabling IP forwarding + opening firewall for $AP_IF (best effort)"
  sysctl -wq net.ipv4.ip_forward=1
  firewall_close
  nft insert rule ip filter INPUT   iifname "$AP_IF" accept comment \"onn-allow\" 2>/dev/null || true
  nft insert rule ip filter OUTPUT  oifname "$AP_IF" accept comment \"onn-allow\" 2>/dev/null || true
  nft insert rule ip filter FORWARD iifname "$AP_IF" accept comment \"onn-allow\" 2>/dev/null || true
  nft insert rule ip filter FORWARD oifname "$AP_IF" accept comment \"onn-allow\" 2>/dev/null || true
  nft insert rule ip raw    PREROUTING iifname "$AP_IF" accept comment \"onn-allow\" 2>/dev/null || true
}

down() {
  echo "==> tearing down hotspot"
  firewall_close
  nmcli connection down OnnHotspot 2>/dev/null || true
  nmcli connection delete OnnHotspot 2>/dev/null || true
  iw dev "$AP_IF" del 2>/dev/null || true
  rm -f "$BLOCKFILE"
  echo "done."
}

up() {
  echo "==> [0/5] Locking AP to the uplink's CURRENT channel (single radio needs them equal)"
  if [ -n "$UPLINK_SSID" ]; then
    CUR_SSID=$(iw dev "$UPLINK_IF" info 2>/dev/null | awk '/ssid/{print $2}')
    if [ "$CUR_SSID" != "$UPLINK_SSID" ]; then
      nmcli connection up "$UPLINK_SSID" >/dev/null 2>&1 || nmcli device wifi connect "$UPLINK_SSID" >/dev/null 2>&1 || true
      sleep 3
    fi
  fi
  CHAN=$(iw dev "$UPLINK_IF" info 2>/dev/null | awk '/channel/{print $2}')
  [ -z "$CHAN" ] && { echo "ERROR: $UPLINK_IF not connected to Wi-Fi — connect to internet first."; exit 1; }
  if [ "$CHAN" -le 14 ]; then BAND=bg; else BAND=a; fi
  echo "    uplink $UPLINK_IF on ch $CHAN -> AP will use band $BAND, ch $CHAN"

  echo "==> [1/5] writing OTA blocklist -> $BLOCKFILE"
  install -d /etc/NetworkManager/dnsmasq-shared.d
  : > "$BLOCKFILE"
  for d in "${BLOCK_DOMAINS[@]}"; do
    printf 'address=/%s/0.0.0.0\naddress=/%s/::\n' "$d" "$d" >> "$BLOCKFILE"
  done

  echo "==> [2/5] (re)creating AP virtual interface $AP_IF with a distinct MAC"
  nmcli connection delete OnnHotspot 2>/dev/null || true
  iw dev "$AP_IF" del 2>/dev/null || true
  iw dev "$UPLINK_IF" interface add "$AP_IF" type __ap
  BASEMAC=$(cat "/sys/class/net/$UPLINK_IF/address")
  APMAC=$(printf '%02x:%s' "$(( 0x${BASEMAC:0:2} | 0x02 ))" "${BASEMAC:3}")
  ip link set "$AP_IF" address "$APMAC"

  echo "==> [3/5] starting hotspot '$HOTSPOT_SSID' (band $BAND, ch $CHAN)"
  nmcli device set "$AP_IF" managed yes; sleep 1
  nmcli connection add type wifi ifname "$AP_IF" con-name OnnHotspot autoconnect no \
    ssid "$HOTSPOT_SSID" \
    802-11-wireless.mode ap 802-11-wireless.band "$BAND" 802-11-wireless.channel "$CHAN" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PSK" \
    ipv4.method shared ipv6.method ignore
  nmcli connection up OnnHotspot
  sleep 3

  echo "==> [4/5] firewall / forwarding"
  firewall_open

  echo "==> [5/5] verification"
  GW=$(ip -4 addr show "$AP_IF" | grep -oP 'inet \K[\d.]+' || true)
  echo "    AP on ch $(iw dev "$AP_IF" info 2>/dev/null | awk '/channel/{print $2}') , gw/DNS=${GW:-<none, AP failed>}"
  echo "    ip_forward=$(sysctl -n net.ipv4.ip_forward) , onn-allow rules=$(nft -a list ruleset 2>/dev/null | grep -c onn-allow)"
  if [ -n "${GW:-}" ]; then
    echo "    blocked test  ${BLOCK_DOMAINS[0]} -> $(dig +short ${BLOCK_DOMAINS[0]} @"$GW" 2>/dev/null | tr '\n' ' ')(expect 0.0.0.0)"
    echo "    allowed test  google.com -> $(dig +short google.com @"$GW" 2>/dev/null | head -1)"
  fi
  echo
  echo "READY -> join SSID '$HOTSPOT_SSID' / pass '$HOTSPOT_PSK'. Leases: /var/lib/NetworkManager/dnsmasq-${AP_IF}.leases"
}

case "${1:-up}" in
  up) up ;; down) down ;; fw) firewall_open ;;
  *) echo "Usage: sudo $0 [up|down|fw]"; exit 1 ;;
esac
