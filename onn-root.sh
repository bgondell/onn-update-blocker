#!/usr/bin/env bash
# ============================================================================
#  onn-root.sh — root the Walmart onn. Google TV 4K (YOC) with Magisk, via USB.
#
#  ⚠⚠⚠  HIGH RISK — READ THIS  ⚠⚠⚠
#  Rooting flashes the vendor_boot partition. A wrong image, an interrupted
#  flash, or a locked/patched unit can SOFT-BRICK or HARD-BRICK the device and
#  VOID ANY WARRANTY. There is NO guarantee. You run this ENTIRELY AT YOUR OWN
#  RISK and by your own choice. The authors accept no responsibility for any
#  damage. If you are not comfortable recovering a device over fastboot, STOP.
#
#  This script is conservative: it backs up your stock vendor_boot first, makes
#  the patched image, verifies it (magic + Magisk marker + size), and asks for
#  an explicit "yes" before it flashes anything. It also has a `restore` mode.
#
#  Requirements:
#    - Bootloader ALREADY UNLOCKED (this script refuses to run if it's locked;
#      unlocking is a separate, data-wiping step and impossible on patched units).
#    - adb + fastboot on PATH.
#    - The STOCK vendor_boot.img for YOUR EXACT BUILD (see ROOT.md on how to get
#      it from the matching full OTA). You can pass the OTA zip and let the
#      script extract it (needs payload-dumper-go), or pass vendor_boot.img.
#    - Magisk APK (validated with v26.1). Pass with --magisk or it looks for
#      ./Magisk-v26.1.apk.
#
#  Usage:
#    ./onn-root.sh --vendor-boot stock/vendor_boot.img --magisk Magisk-v26.1.apk
#    ./onn-root.sh --ota ota.zip            # extract vendor_boot from a full OTA
#    ./onn-root.sh restore stock/vendor_boot.img   # flash stock back to both slots
#
#  License: MIT. No warranty.
# ============================================================================
set -uo pipefail

SERIAL="${ONN_SERIAL:-}"
VBOOT=""; OTA=""; MAGISK=""; MODE=interactive; RESTORE_IMG=""
WORK="$(cd "$(dirname "$0")" && pwd)/root-work"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor-boot) VBOOT="$2"; shift 2;;
    --ota)         OTA="$2"; shift 2;;
    --magisk)      MAGISK="$2"; shift 2;;
    --serial)      SERIAL="$2"; shift 2;;
    restore)       MODE=restore; RESTORE_IMG="${2:-}"; shift 2 || true;;
    -h|--help)     sed -n '2,40p' "$0"; exit 0;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

if [[ -t 1 ]]; then B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; X=$'\e[0m'
else B=; R=; G=; Y=; C=; X=; fi
die(){ echo "${R}✗ $*${X}" >&2; exit 1; }
ok(){  echo "${G}✓ $*${X}"; }
note(){ echo "${Y}! $*${X}"; }

pick_serial(){
  [[ -n "$SERIAL" ]] && return
  mapfile -t d < <(adb devices | awk '/\tdevice$/ && $1 !~ /:/ {print $1}')
  ((${#d[@]}==1)) && SERIAL="${d[0]}" || { ((${#d[@]}==0)) && die "no USB device (enable USB debugging, plug into PC)"; die "multiple devices, pass --serial"; }
}
A(){ adb -s "$SERIAL" "$@"; }
FB(){ fastboot -s "$SERIAL" "$@"; }

wait_fastboot(){ for _ in $(seq 1 20); do fastboot devices 2>/dev/null | grep -q "$SERIAL" && return 0; sleep 1; done; die "device did not enter fastboot"; }
wait_adb(){ for _ in $(seq 1 90); do A get-state 2>/dev/null | grep -q device && return 0; sleep 1; done; die "device did not come back online"; }

# ---------------------------------------------------------------- restore mode
if [[ "$MODE" == restore ]]; then
  [[ -f "${RESTORE_IMG:-}" ]] || die "restore image not found: ${RESTORE_IMG:-<none>}"
  head -c8 "$RESTORE_IMG" | grep -q VNDRBOOT || die "not a vendor_boot image"
  pick_serial
  note "Flashing STOCK $RESTORE_IMG to BOTH vendor_boot slots..."
  A reboot bootloader; wait_fastboot
  FB flash vendor_boot_a "$RESTORE_IMG" || die "flash a failed"
  FB flash vendor_boot_b "$RESTORE_IMG" || die "flash b failed"
  FB reboot; ok "Stock vendor_boot restored. Device rebooting."
  exit 0
fi

# ------------------------------------------------------------------- preflight
cat <<EOF
${B}=== onn-root.sh — Magisk root for onn 4K (YOC) ===${X}
${R}HIGH RISK: this flashes vendor_boot. Bricks are possible. Your choice, your risk.${X}
EOF
command -v adb >/dev/null || die "adb not found"
command -v fastboot >/dev/null || die "fastboot not found"
pick_serial
MODEL="$(A shell getprop ro.product.device | tr -d '\r')"
ok "device: $SERIAL ($MODEL)"
[[ "$MODEL" == YOC ]] || note "device is '$MODEL', not 'YOC' — package/partition details may differ. Proceed with care."

# Bootloader MUST be unlocked.
VBS="$(A shell getprop ro.boot.verifiedbootstate | tr -d '\r')"
[[ "$VBS" == orange ]] || die "bootloader is NOT unlocked (verifiedbootstate=$VBS). Unlock first (data wipe; impossible on patched units). Aborting — safe."
ok "bootloader unlocked (verifiedbootstate=orange)"

mkdir -p "$WORK"; cd "$WORK"

# ------------------------------------------------------- obtain stock vendor_boot
if [[ -z "$VBOOT" && -n "$OTA" ]]; then
  note "Extracting vendor_boot.img from OTA: $OTA"
  command -v payload-dumper-go >/dev/null || die "payload-dumper-go not on PATH (needed to extract). See ROOT.md."
  if [[ "$OTA" =~ ^https?:// ]]; then curl -L --retry 5 -o ota.zip "$OTA" || die "OTA download failed"; OTA=ota.zip; fi
  unzip -o "$OTA" payload.bin -d . >/dev/null || die "no payload.bin in OTA"
  payload-dumper-go -p vendor_boot -o . payload.bin >/dev/null || die "payload extract failed"
  VBOOT="$WORK/vendor_boot.img"
fi
[[ -f "${VBOOT:-}" ]] || die "need --vendor-boot <img> or --ota <zip|url>. See ROOT.md for getting your exact-build image."
head -c8 "$VBOOT" | grep -q VNDRBOOT || die "$VBOOT is not a vendor_boot image (bad magic)"
mkdir -p stock; cp -f "$VBOOT" stock/vendor_boot.img
ok "stock vendor_boot backed up -> $WORK/stock/vendor_boot.img"
echo "  sha256: $(sha256sum stock/vendor_boot.img | cut -d' ' -f1)"

# ------------------------------------------------------------------ magisk apk
[[ -z "$MAGISK" && -f "$(dirname "$0")/Magisk-v26.1.apk" ]] && MAGISK="$(dirname "$0")/Magisk-v26.1.apk"
[[ -f "${MAGISK:-}" ]] || die "Magisk APK not found. Pass --magisk Magisk-v26.1.apk"
ok "magisk apk: $MAGISK"

# ------------------------------------------------- on-device patch environment
note "Installing Magisk app + staging patch tools on device..."
A install -r "$MAGISK" >/dev/null 2>&1 || die "magisk install failed"
BASE="$(A shell pm path com.topjohnwu.magisk | head -1 | sed 's/package://;s/\r//')"
LIBDIR="$(dirname "$BASE")/lib"
ABI="$(A shell ls "$LIBDIR" | tr -d '\r' | head -1)"   # arm or arm64
LIB="$LIBDIR/$ABI"
WD=/data/local/tmp/onn-root
A shell "rm -rf $WD; mkdir -p $WD"
A shell "cp $LIB/libmagiskboot.so $WD/magiskboot; cp $LIB/libmagiskinit.so $WD/magiskinit; cp $LIB/libbusybox.so $WD/busybox 2>/dev/null
[ -f $LIB/libmagisk64.so ] && cp $LIB/libmagisk64.so $WD/magisk64; [ -f $LIB/libmagisk32.so ] && cp $LIB/libmagisk32.so $WD/magisk32; chmod 755 $WD/*"

# Extract boot_patch.sh + helpers from the APK and inject the lz4_legacy
# vendor_boot workaround (magiskboot mis-detects this ramdisk as 'raw').
TMP="$(mktemp -d)"; unzip -o "$MAGISK" 'assets/boot_patch.sh' 'assets/util_functions.sh' 'assets/stub.apk' -d "$TMP" >/dev/null
BP="$TMP/assets/boot_patch.sh"
grep -q 'Checking ramdisk status' "$BP" || die "unexpected boot_patch.sh (Magisk version?); validated with v26.1"
awk '
  /ui_print "- Checking ramdisk status"/ && !d {
    print "RAMDISK_RECOMPRESS=\"\""
    print "if [ -e ramdisk.cpio ]; then"
    print "  RHDR=$(od -An -tx1 -N4 ramdisk.cpio | tr -d \" \\n\")"
    print "  if [ \"$RHDR\" = \"02214c18\" ]; then"
    print "    ui_print \"- Decompressing lz4_legacy vendor ramdisk\""
    print "    ./magiskboot decompress ramdisk.cpio ramdisk.raw && mv -f ramdisk.raw ramdisk.cpio"
    print "    RAMDISK_RECOMPRESS=lz4_legacy"
    print "  fi"
    print "fi"
    d=1
  }
  /ui_print "- Repacking boot image"/ && !r {
    print "if [ -n \"$RAMDISK_RECOMPRESS\" ]; then"
    print "  ui_print \"- Recompressing ramdisk ($RAMDISK_RECOMPRESS)\""
    print "  ./magiskboot compress=$RAMDISK_RECOMPRESS ramdisk.cpio ramdisk.lz4 && mv -f ramdisk.lz4 ramdisk.cpio"
    print "fi"
    r=1
  }
  { print }
' "$BP" > "$TMP/boot_patch.patched.sh"
A push "$TMP/boot_patch.patched.sh" "$WD/boot_patch.sh" >/dev/null
A push "$TMP/assets/util_functions.sh" "$WD/util_functions.sh" >/dev/null
A push "$TMP/assets/stub.apk" "$WD/stub.apk" >/dev/null
A push "$VBOOT" /sdcard/Download/vendor_boot.img >/dev/null
rm -rf "$TMP"
ok "patch environment ready (abi=$ABI)"

# ------------------------------------------------------------------- patch run
note "Patching vendor_boot with Magisk (on-device)..."
A shell "cd $WD && KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false BOOTMODE=true sh boot_patch.sh /sdcard/Download/vendor_boot.img" 2>&1 | tr -d '\r' | sed 's/^/    /'
A shell "[ -f $WD/new-boot.img ]" || die "patch produced no output image"

# ------------------------------------------------------------- verify patched
A reboot bootloader; wait_fastboot
PSIZE=$(( $(FB getvar partition-size:vendor_boot_a 2>&1 | grep -oE '0x[0-9a-fA-F]+' | head -1) ))
FB reboot; wait_adb
ISIZE=$(A shell "stat -c%s $WD/new-boot.img" | tr -d '\r')
echo "  patched size: $ISIZE   partition: $PSIZE"
(( ISIZE <= PSIZE )) || die "patched image ($ISIZE) > partition ($PSIZE) — would not fit. Aborting (no flash done)."
A shell "cd $WD && rm -rf v && mkdir v && cp new-boot.img v/ && cd v && ../magiskboot unpack new-boot.img >/dev/null 2>&1 && ../magiskboot decompress ramdisk.cpio r >/dev/null 2>&1 && mv -f r ramdisk.cpio && ../magiskboot cpio ramdisk.cpio test" >/dev/null 2>&1
STAT=$(A shell "cd $WD/v && ../magiskboot cpio ramdisk.cpio test >/dev/null 2>&1; echo \$(( \$? & 1 ))" | tr -d '\r')
[[ "$STAT" == 1 ]] || die "patched image does NOT contain Magisk (cpio test). Aborting (no flash done)."
A pull "$WD/new-boot.img" "$WORK/vendor_boot-magisk_patched.img" >/dev/null
ok "patched image verified: VNDRBOOT, Magisk-patched, fits partition"

# ------------------------------------------------------------------ confirm + flash
echo
echo "${B}About to flash ${C}vendor_boot-magisk_patched.img${X}${B} to BOTH slots (vendor_boot_a/_b).${X}"
echo "${R}This is the point of risk. Stock backup: $WORK/stock/vendor_boot.img${X}"
read -r -p "Type 'yes' to flash, anything else to abort: " ans
[[ "$ans" == yes ]] || { note "Aborted by user. Nothing flashed."; exit 0; }

A reboot bootloader; wait_fastboot
FB flash vendor_boot_a "$WORK/vendor_boot-magisk_patched.img" || die "flash a FAILED — restore stock with: $0 restore $WORK/stock/vendor_boot.img"
FB flash vendor_boot_b "$WORK/vendor_boot-magisk_patched.img" || die "flash b FAILED — restore stock with: $0 restore $WORK/stock/vendor_boot.img"
FB reboot
ok "flashed both slots. Waiting for boot..."
wait_adb
for _ in $(seq 1 30); do [ "$(A shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 2; done

# ------------------------------------------------------------------- post-check
MV="$(A shell 'magisk -v' 2>/dev/null | tr -d '\r')"
if [[ -n "$MV" ]]; then
  ok "BOOTED. magiskd reports: $MV"
  echo "${C}Open the Magisk app on the TV; if it asks for 'additional setup', accept it (it will reboot once).${X}"
  echo "${C}Then root is complete. To revert: $0 restore $WORK/stock/vendor_boot.img${X}"
else
  note "Booted but magisk -v empty. Open the Magisk app to finish setup, or restore stock if unstable."
fi
