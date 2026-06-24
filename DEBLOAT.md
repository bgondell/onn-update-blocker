# Debloat & block updates on the onn 4K (Google TV) — no root, over USB

A small, **reversible** toolkit to (1) **stop the device from updating itself** and
(2) **remove bloatware** on the 2023 Walmart **onn. Google TV 4K (model YOC)** and
similar Android TV / Google TV devices — **without rooting**, using only ADB over USB.

Everything is done with `pm disable-user` (the app stays in `/system`, it just won't
run) and a documented global setting — so it's **fully reversible** and a factory
reset always brings the device back to stock.

> ⚠️ **Use on hardware you own.** This is a non-root mitigation, not a guarantee for
> every firmware. No warranty. The OTA package names below are confirmed for the
> **YOC** model — other models ship different updaters (the tool tries them all and
> skips whatever isn't present).

---

## Why

The onn 4K (YOC) shipped on build `SGZ3.231226.096.A1` (Android 12). Some units **brick
themselves on a forced system update**, and the stock OS is full of preinstalled apps
and telemetry. This toolkit turns off the automatic updater and lets you strip the
device down — all from a laptop, no root, no unlocking.

---

## What you need

- A computer with **`adb`** installed
  (Linux: `sudo pacman -S android-tools` / `sudo apt install adb`; macOS: `brew install android-platform-tools`; Windows: Google "SDK platform-tools").
- The dongle's **USB power cable**. The onn 4K's micro-USB **power port is also a data
  port**, so that one cable carries power *and* ADB. No special hardware needed.
- The TV (to see and approve the on-screen prompt).

---

## Step 1 — Enable USB debugging (on the TV, with the remote)

1. **Settings → System → About →** highlight **"Android TV OS build"** and click it
   **7 times** until it says *"You are now a developer."*
2. **Settings → System → Developer options →** turn on **USB debugging**.

## Step 2 — Connect over USB

1. **Unplug** the dongle's USB cable from the wall power adapter and plug it into a
   **USB port on your computer**. Keep the **HDMI plugged into the TV**.
2. Run:
   ```bash
   ./onn-adb-connect.sh
   ```
3. A popup appears **on the TV**: *"Allow USB debugging?"* — tick **"Always allow from
   this computer"** and choose **Allow**.
4. You should see your device listed (`model:onn__4K_Streaming_Box`, `device:YOC`).

> If a USB port can't power the dongle (screen flickers/reboots), use a **USB 3 port**
> or a **powered USB hub**.

## Step 3 — Run the tool

```bash
./onn-debloat.sh
```

It walks you through two steps, and **logs every change** to `logs/removed-<timestamp>.log`
so you can undo it later.

### A) Update block

It disables the on-device updater apps and sets the non-root OTA flag:

| Target | What it is |
|---|---|
| `com.google.android.factoryota` | Generic Google TV factory OTA (if present) |
| `com.onn.updatenotification` | Onn/Walmart "update available" notifier (YOC) |
| `com.google.android.tv.dfuservice` | Amlogic Device Firmware Update service (YOC) |
| `settings put global ota_disable_automatic_update 1` | Turns off **automatic** OTA checks/downloads (no root) |

### B) Debloat

You review a catalog of known packages, tagged by risk:

- **`safe`** — clearly removable (preloaded streaming apps, Play Games, print spooler,
  feedback/telemetry, screensavers, sync adapters…).
- **`aggr`** — removable but you lose a feature (Chromecast receiver, Google Assistant /
  voice search, recommendation rows, backup…).
- **`DANGER`** — never auto-selected and warned (the launcher, Play Store, Google Play
  services, Setup Wizard). Don't disable these unless you know exactly why.

For each line: **Enter** accepts the default, **y** removes, **n** keeps. The tool then
lists anything installed that it doesn't recognize, so you can disable extra vendor
preloads too. Nothing is applied until you confirm the final list.

---

## ❗ Can the device still update? (honest answer)

- **Automatic updates: blocked.** The updater apps are disabled and
  `ota_disable_automatic_update=1` stops background checks.
- **A manual "Check for system update" in Settings: may still work.** The onn 4K uses
  **A/B seamless updates** driven by **Google Play services** (`com.google.android.gms`),
  which is a **protected package** — `pm disable-user` on its update components is
  refused without root (`SecurityException`). That core path can only be removed with
  **root**.

So this toolkit gives you the **strongest possible non-root, device-side block**. If you
need a 100% guarantee against a *manual* update too, that requires **root** — with root you
can disable the GMS `.update.*` components directly, and a Magisk-modified `vendor_boot`
breaks A/B OTA outright. See **[ROOT.md](ROOT.md)** (⚠️ high risk — read the warnings).

---

## Reversing everything

Every run writes a log. To undo a run (re-enable all packages and clear the flag):

```bash
./onn-debloat.sh restore logs/removed-20240101-120000.log
```

Or **factory reset** the device — `disable-user` changes don't survive a reset, so the
device returns 100% to stock.

---

## Other commands

```bash
./onn-debloat.sh dump            # print every installed package (pipe-clean)
./onn-debloat.sh --serial XXXX   # target a specific device if several are attached
./onn-adb-connect.sh status      # show attached USB devices
```

---

## Troubleshooting

- **`unauthorized`** in `adb devices`: you didn't accept the popup on the TV. Re-run
  `./onn-adb-connect.sh` and approve it.
- **No popup appears**: USB debugging isn't on, or the cable/port is power-only on the
  computer side. Try another cable/port; confirm Developer options → USB debugging.
- **A disabled app came back**: a Play Store update or reboot can sometimes re-enable an
  app. Re-run the tool, or `adb shell pm disable-user --user 0 <pkg>` again.
- **Something broke / black screen**: re-enable with the restore command, or factory
  reset. Don't disable `DANGER`-tier packages.

---

## Compatibility with other Google TV / Android TV devices

The debloat **catalog is generic** — anything not installed is silently skipped, so it's
safe to run on other Google TV boxes. The **update-blocking package names differ per
device/SoC**; this tool targets the generic Google TV updater plus the Amlogic/onn ones.
On a different device, run `./onn-debloat.sh dump`, look for packages with `update`,
`ota`, or `dfu` in the name, and add them to `OTA_PKGS` near the top of the script.

## License

MIT. No warranty — you run this at your own risk on hardware you own.
