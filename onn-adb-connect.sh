#!/usr/bin/env bash
# Connect to the Onn 4K dongle for ADB over USB (USB-only by design).
#
# The Onn 4K (YOC) is an HDMI dongle whose single power port (micro-USB) is
# ALSO a data port. So with "USB debugging" enabled you can drive it from a PC:
# unplug the dongle's power cable from the wall brick and plug it into the
# LAPTOP's USB port — the laptop powers it AND gets ADB. Keep the HDMI in the
# TV so you can tap "Allow" on the authorization popup.
#
# On the dongle first:
#   Settings > System > About > "Android TV OS build"  -> click 7x (developer)
#   Settings > System > Developer options > enable "USB debugging"
#
# Usage:
#   ./onn-adb-connect.sh            # wait for the USB device, authorize on TV
#   ./onn-adb-connect.sh status     # show currently attached USB devices

set -uo pipefail

case "${1:-connect}" in
  status)
    adb devices -l
    ;;
  connect)
    echo "Plug the dongle's USB cable into this laptop now (keep HDMI in the TV)."
    echo "Waiting for the device..."
    adb wait-for-usb-device 2>/dev/null || adb wait-for-device
    echo "--- a popup should appear ON THE TV: 'Allow USB debugging?' -> Allow ---"
    echo "    (tick 'Always allow from this computer')"
    sleep 1
    adb devices -l
    state="$(adb get-state 2>/dev/null || true)"
    if [[ "$state" == device ]]; then
      echo "USB ADB ready. Now run: ./onn-debloat.sh"
    else
      echo "If it says 'unauthorized', accept the popup on the TV, then re-run."
    fi
    ;;
  *) echo "usage: $0 [connect | status]"; exit 1;;
esac
