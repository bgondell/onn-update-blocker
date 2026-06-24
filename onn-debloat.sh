#!/usr/bin/env bash
# ============================================================================
#  onn-debloat.sh — interactive debloat + OTA-block tool for the Onn 4K
#                   (Walmart onn. Google TV 4K, model YOC) and other Google TV
#                   / Android TV devices.
#
#  Non-destructive: uses `pm disable-user --user 0`, NOT uninstall. The APK
#  stays in the read-only /system partition and is simply prevented from
#  loading. Everything is reversible:
#       ./onn-debloat.sh restore <log>      # re-enable from a change log
#       (or a factory reset restores the device completely)
#
#  Connection: USB ONLY. The Onn 4K's power port is also a data port — plug it
#  into the laptop (keep HDMI in the TV) and enable "USB debugging".
#  See ./onn-adb-connect.sh.
#
#  Usage:
#       ./onn-debloat.sh                 # interactive (connect + OTA + debloat)
#       ./onn-debloat.sh --serial XXXX   # pick a specific USB device
#       ./onn-debloat.sh restore logs/removed-YYYYmmdd-HHMMSS.log
#       ./onn-debloat.sh dump            # just print installed packages & exit
#
#  Share-friendly: no secrets, no host-specific paths. MIT.
# ============================================================================
set -uo pipefail

# ---- config / args ---------------------------------------------------------
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
ASSUME_YES=0
SERIAL="${ONN_SERIAL:-}"   # optional explicit USB serial

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    -y|--yes) ASSUME_YES=1; shift;;
    dump)   MODE=dump; shift;;
    restore) MODE=restore; RESTORE_LOG="${2:-}"; shift 2 || true;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done
MODE="${MODE:-interactive}"
A() { adb -s "$SERIAL" "$@"; }

# Pick the single attached USB device if no serial was given. A USB serial has
# no ':' (network devices look like 10.x.x.x:5555 and are ignored here).
pick_usb_serial() {
  [[ -n "$SERIAL" ]] && return 0
  mapfile -t devs < <(adb devices | awk '/\tdevice$/ && $1 !~ /:/ {print $1}')
  if   ((${#devs[@]}==1)); then SERIAL="${devs[0]}"
  elif ((${#devs[@]}==0)); then SERIAL=""
  else
    echo "Multiple USB devices attached — pass --serial:"; printf '   %s\n' "${devs[@]}"; exit 1
  fi
}

# ---- colors ----------------------------------------------------------------
if [[ -t 1 ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; X=$'\e[0m'
else B=; DIM=; R=; G=; Y=; C=; X=; fi
say()  { printf '%s\n' "$*"; }
hd()   { printf '\n%s== %s ==%s\n' "$B" "$*" "$X"; }
ask()  { # ask "question" default(y/n) -> returns 0 for yes
  local q="$1" d="${2:-y}" a
  [[ $ASSUME_YES == 1 ]] && return 0
  read -r -p "$q [$([[ $d == y ]] && echo 'Y/n' || echo 'y/N')] " a
  a="${a:-$d}"; [[ "$a" =~ ^[Yy] ]]
}

# ============================================================================
#  PACKAGE CATALOG
#  pkg | Friendly name | tier | default
#    tier:  safe       = clearly removable bloat
#           aggressive = removable but you lose a feature (cast, assistant, ...)
#           danger     = can break the UI / boot — never auto-selected, warned
#    default: rm = pre-selected for removal, keep = pre-selected to keep
#  Anything not installed on the device is silently skipped.
# ============================================================================
CATALOG=(
  # --- preloaded streaming apps (safe) ---
  "com.netflix.ninja|Netflix (preload)|safe|rm"
  "com.disney.disneyplus|Disney+ (preload)|safe|rm"
  "com.amazon.amazonvideo.livingroom|Prime Video (preload)|safe|rm"
  "com.hbo.hbonow|Max / HBO (preload)|safe|rm"
  "com.wbd.stream|Max (preload)|safe|rm"
  "tv.pluto.android|Pluto TV (preload)|safe|rm"
  "com.google.android.videos|Google TV / Movies app|safe|rm"
  "com.google.android.youtube.tvmusic|YouTube Music|safe|rm"
  "com.google.android.youtube.tvunplugged|YouTube TV|safe|rm"
  "com.google.android.youtube.tv|YouTube|safe|keep"
  # --- google extras (safe) ---
  "com.google.android.play.games|Play Games|safe|rm"
  "com.google.android.feedback|Google Feedback reporter|safe|rm"
  "com.google.android.printservice.recommendation|Print service reco|safe|rm"
  "com.android.printspooler|Print Spooler|safe|rm"
  "com.google.android.syncadapters.calendar|Calendar sync|safe|rm"
  "com.google.android.syncadapters.contacts|Contacts sync|safe|rm"
  "com.android.bookmarkprovider|Bookmark provider|safe|rm"
  "com.android.dreams.basic|Screensaver (basic)|safe|rm"
  "com.android.dreams.phototable|Screensaver (photos)|safe|rm"
  "com.android.wallpaperbackup|Wallpaper backup|safe|rm"
  "com.google.android.partnersetup|Partner setup/promo|safe|rm"
  "com.google.android.tag|NFC Tag|safe|rm"
  # --- aggressive: lose a feature ---
  "com.google.android.tvrecommendations|Home-screen recommendation rows|aggressive|rm"
  "com.google.android.apps.mediashell|Chromecast/Cast receiver|aggressive|rm"
  "com.google.android.katniss|Google Assistant / voice search (TV)|aggressive|rm"
  "com.google.android.gms.supervision|Family/Supervision|aggressive|rm"
  "com.google.android.backuptransport|Google backup transport|aggressive|rm"
  "com.google.android.backup|Google backup|aggressive|rm"
  "com.google.android.marvin.talkback|TalkBack screen reader (a11y)|aggressive|rm"
  "com.google.android.apps.tv.launcherx.partner|Launcher partner content|aggressive|rm"
  "com.google.android.tungsten.overlay|Tungsten overlay|aggressive|keep"
  # --- danger: can brick the UI/boot — kept, warned ---
  "com.google.android.tvlauncher|Google TV LAUNCHER (home screen)|danger|keep"
  "com.google.android.apps.tv.launcherx|Google TV launcher (new)|danger|keep"
  "com.android.vending|Play Store|danger|keep"
  "com.google.android.gms|Google Play services (CORE)|danger|keep"
  "com.google.android.gsf|Google Services Framework (CORE)|danger|keep"
  "com.google.android.tungsten.setupwizard|Setup Wizard (CORE)|danger|keep"
)

# OTA / system-update targets (handled in the OTA step, not the app list).
# Different Google TV builds ship different updaters — we try them all and skip
# whatever is absent:
#   com.google.android.factoryota        - generic Google TV factory OTA
#   com.onn.updatenotification           - Onn (Walmart) update notifier  [YOC]
#   com.google.android.tv.dfuservice     - Amlogic Device Firmware Update  [YOC]
OTA_PKGS=(
  com.google.android.factoryota
  com.onn.updatenotification
  com.google.android.tv.dfuservice
)
# NOTE: the GMS update path (com.google.android.gms/.update.*) is a PROTECTED
# package — `pm disable-user` is refused without root (SecurityException). The
# global flag below is the strongest non-root lever against it; it stops
# automatic OTA. Fully removing the GMS path requires root.
OTA_SETTING="ota_disable_automatic_update"   # global=1 disables automatic OTA (no root needed)

# ---- connection ------------------------------------------------------------
ensure_connected() {
  pick_usb_serial
  if [[ -z "$SERIAL" ]] || ! adb -s "$SERIAL" get-state >/dev/null 2>&1; then
    say "${R}No authorized USB device.${X}"
    say "Plug the dongle's USB cable into this laptop, enable USB debugging,"
    say "then accept the popup on the TV. Helper: ${C}./onn-adb-connect.sh${X}"
    exit 1
  fi
  local model; model="$(A shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  say "${G}Connected (USB):${X} $SERIAL  (${model:-unknown model})" >&2
}

installed() { A shell pm list packages 2>/dev/null | sed 's/package://; s/\r//' | sort; }

# ---- OTA block step --------------------------------------------------------
do_ota_block() {
  hd "Block system / OTA updates on the device"
  say "${DIM}Disables the on-device updater apps and sets the non-root flag that"
  say "stops automatic OTA — without disabling Google Play services.${X}"
  ask "Apply device-level OTA block now?" y || { say "skipped."; return; }
  : > "$1"  # log
  for p in "${OTA_PKGS[@]}"; do
    printf '   %-42s ' "$p"
    if A shell pm list packages | grep -q "$p"; then
      A shell pm disable-user --user 0 "$p" >/dev/null 2>&1 \
        && { echo "${G}disabled${X}"; echo "pkg $p" >> "$1"; } || echo "${Y}skip${X}"
    else echo "${DIM}absent${X}"; fi
  done
  # non-root global flag: disable automatic OTA scheduling
  printf '   %-42s ' "global/$OTA_SETTING"
  if A shell settings put global "$OTA_SETTING" 1 >/dev/null 2>&1; then
    echo "${G}=1${X}"; echo "setting global $OTA_SETTING" >> "$1"
  else echo "${Y}skip${X}"; fi
  say "${G}OTA block applied.${X}  Logged to ${1#"$PWD"/}"
  say "${DIM}Automatic updates are now off. A MANUAL 'check for update' in Settings${X}"
  say "${DIM}may still work — the GMS update path is root-locked. See the guide.${X}"
}

# ---- debloat step ----------------------------------------------------------
do_debloat() {
  local logf="$1"
  hd "Debloat — choose what to remove"
  mapfile -t INST < <(installed)
  is_installed() { printf '%s\n' "${INST[@]}" | grep -qx "$1"; }

  local -a TODO=()      # packages chosen for removal
  local catpkgs=()

  say "${DIM}Mode: ${B}aggressive defaults pre-selected${X}${DIM}. Review each line —"
  say "Enter=accept default, y=remove, n=keep.${X}\n"

  for entry in "${CATALOG[@]}"; do
    IFS='|' read -r pkg name tier def <<<"$entry"
    catpkgs+=("$pkg")
    is_installed "$pkg" || continue
    local tag def_rm=0
    case "$tier" in
      safe)       tag="${G}safe${X}";;
      aggressive) tag="${Y}aggr${X}";;
      danger)     tag="${R}DANGER${X}";;
    esac
    # aggressive run: promote 'aggressive' tier defaults to remove
    [[ "$def" == rm ]] && def_rm=1
    [[ "$tier" == aggressive ]] && def_rm=1
    [[ "$tier" == danger ]] && def_rm=0
    if [[ $ASSUME_YES == 1 ]]; then
      [[ $def_rm == 1 ]] && TODO+=("$pkg"); continue
    fi
    if [[ "$tier" == danger ]]; then
      printf '  [%s] %-38s %s\n' "$tag" "$name" "${DIM}$pkg${X}"
      ask "    Remove this? (NOT recommended)" n && TODO+=("$pkg")
    else
      printf '  [%s] %-38s %s\n' "$tag" "$name" "${DIM}$pkg${X}"
      ask "    Remove?" "$([[ $def_rm == 1 ]] && echo y || echo n)" && TODO+=("$pkg")
    fi
  done

  # unknown preloads not in our catalog
  hd "Other installed apps (not in catalog)"
  local -a UNKNOWN=()
  for p in "${INST[@]}"; do
    printf '%s\n' "${catpkgs[@]}" | grep -qx "$p" && continue
    # skip obvious core android providers to reduce noise
    case "$p" in
      android|com.android.systemui|com.android.settings*|com.android.providers.*|\
      com.android.bluetooth|com.android.nfc|com.android.shell|com.android.keychain|\
      com.google.android.gsf*|com.google.android.gms*|com.android.inputdevices|\
      com.android.location.fused|com.android.externalstorage) continue;;
    esac
    UNKNOWN+=("$p")
  done
  if ((${#UNKNOWN[@]})); then
    say "${DIM}Vendor/3rd-party packages we don't have a label for:${X}"
    printf '   %s\n' "${UNKNOWN[@]}"
    if ask "Review these one by one to disable extra ones?" n; then
      for p in "${UNKNOWN[@]}"; do ask "  Remove ${C}$p${X}?" n && TODO+=("$p"); done
    fi
  else say "${DIM}none${X}"; fi

  # confirm + apply
  hd "Confirm"
  if ((${#TODO[@]}==0)); then say "Nothing selected. Done."; return; fi
  say "Will ${R}disable${X} ${B}${#TODO[@]}${X} packages:"
  printf '   %s\n' "${TODO[@]}"
  ask "Proceed?" y || { say "Aborted, nothing changed."; return; }
  for p in "${TODO[@]}"; do
    printf '   %-44s ' "$p"
    A shell pm disable-user --user 0 "$p" >/dev/null 2>&1 \
      && { echo "${G}done${X}"; echo "pkg $p" >> "$logf"; } || echo "${R}FAILED${X}"
  done
  say "\n${G}Debloat complete.${X} ${#TODO[@]} packages disabled."
  say "Reverse anytime with: ${C}./onn-debloat.sh restore ${logf#"$PWD"/}${X}"
}

# ---- restore ---------------------------------------------------------------
do_restore() {
  [[ -f "${RESTORE_LOG:-}" ]] || { say "${R}log not found: ${RESTORE_LOG:-<none>}${X}"; exit 1; }
  ensure_connected
  hd "Restore from $RESTORE_LOG"
  while read -r kind val extra; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      pkg|comp)
        printf '   re-enable %-42s ' "$val"
        A shell pm enable "$val" >/dev/null 2>&1 && echo "${G}ok${X}" || echo "${Y}skip${X}";;
      setting)   # line is: setting global <name>
        printf '   reset setting %-39s ' "$extra"
        A shell settings delete "$val" "$extra" >/dev/null 2>&1 && echo "${G}ok${X}" || echo "${Y}skip${X}";;
    esac
  done < "$RESTORE_LOG"
  say "${G}Restore complete.${X}"
}

# ---- main ------------------------------------------------------------------
case "$MODE" in
  dump)    ensure_connected; installed;;
  restore) do_restore;;
  interactive)
    ensure_connected
    mkdir -p "$LOGDIR"
    ts="$(date +%Y%m%d-%H%M%S)"
    log="$LOGDIR/removed-$ts.log"; : > "$log"
    do_ota_block "$log"
    do_debloat   "$log"
    hd "All done"
    say "Change log: ${C}${log}${X}"
    say "Reverse everything with: ${C}./onn-debloat.sh restore ${log#"$PWD"/}${X}"
    ;;
esac
