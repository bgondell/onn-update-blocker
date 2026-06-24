# Rooting the onn 4K (Google TV, YOC) with Magisk — over USB

> # ⚠️ STOP — READ THIS FIRST
>
> **Rooting is HIGH RISK. It is entirely YOUR choice and YOUR responsibility.**
>
> - This flashes the `vendor_boot` partition. A wrong image, an interrupted
>   flash, a power loss, or a locked/patched unit can **soft-brick or
>   hard-brick** your device.
> - It will **void any warranty** and can **break OTA updates permanently**
>   (often desired here — but know it).
> - There is **NO guarantee** this works on your unit or firmware. Walmart sells
>   **patched units that cannot be unlocked or rooted at all.**
> - If you are not comfortable recovering a device from `fastboot`, **do not do
>   this.** Nobody but you is responsible for the outcome.
>
> The tooling here is deliberately cautious — it backs up your stock image,
> verifies the patched image, refuses to run on a locked bootloader, and asks
> for explicit confirmation before flashing — but **it cannot make rooting
> safe. Proceed only if you accept the full risk.**

---

## What you get

Root (Magisk) lets you fully control the device: remove the last update hooks,
run modules, automate a kiosk, etc. On the YOC specifically, a Magisk-modified
`vendor_boot` also **breaks A/B OTA updates** outright — a bonus if your goal is
to stop the bricking update for good.

## Why it's fiddly on this device (and how the script handles it)

1. **You must patch `vendor_boot`, not `boot`.** The YOC keeps its root
   filesystem ramdisk in `vendor_boot`.
2. **The ramdisk is a single LZ4-legacy-compressed cpio**, but `magiskboot`
   mis-detects it as `raw` and won't auto-decompress it → "bad cpio header".
   The script injects a **decompress-before-patch / recompress-before-repack**
   step into Magisk's own `boot_patch.sh` to handle this.
3. **Google TV has no file picker**, so Magisk's *"Select and Patch a File"*
   fails. The script patches **on-device via the command line** using Magisk's
   own bundled binaries — no GUI needed.
4. The `vendor_boot` partition is **exactly the size of the stock image**, so
   the patched image must not grow past it. The script keeps the ramdisk
   compressed and **verifies the size fits before flashing.**

---

## Prerequisites

### 1. Bootloader must already be UNLOCKED
Check (with USB debugging on, device plugged into your PC):
```bash
adb shell getprop ro.boot.verifiedbootstate     # must print: orange
```
- `orange` = unlocked → you can proceed.
- `green`/`yellow` = locked → you'd have to unlock first
  (`adb reboot bootloader && fastboot flashing unlock`), which **wipes all data**
  and is **impossible on patched units** (OEM Unlocking greyed out). The script
  **refuses to run** if it's not unlocked — that's intentional and safe.

### 2. Tools on your PC
`adb`, `fastboot`, `unzip`, and (only if extracting from an OTA)
[`payload-dumper-go`](https://github.com/ssut/payload-dumper-go).

### 3. The STOCK `vendor_boot.img` for YOUR EXACT BUILD
This is the single most important safety item. **Using an image from a different
build can brick the device.** Find your build, then get the matching full OTA:
```bash
adb shell getprop ro.build.fingerprint
# e.g. onn/onn_4k_gtv/YOC:12/SGZ3.231226.096.A1/12865554:user/release-keys
```
Full OTAs are hosted by Google at
`https://android.googleapis.com/packages/ota-api/package/<hash>.zip`. Find the
hash for your fingerprint (the XDA YOC thread keeps a list), download it, and
extract `vendor_boot.img`:
```bash
unzip OTA.zip payload.bin
payload-dumper-go -p vendor_boot -o . payload.bin   # -> vendor_boot.img
```
Or let the script do it: `--ota OTA.zip` (or a URL).

### 4. Magisk APK
Validated with **Magisk v26.1**
([release](https://github.com/topjohnwu/Magisk/releases/tag/v26.1)). Other
versions may work but the lz4 workaround is matched to 26.x `boot_patch.sh`.

---

## The easy path — `onn-root.sh`

```bash
# enable USB debugging on the dongle, plug its USB cable into your PC
./onn-adb-connect.sh                 # authorize on the TV

# root (pass your exact-build stock image + Magisk apk)
./onn-root.sh --vendor-boot vendor_boot.img --magisk Magisk-v26.1.apk
#   ...or extract from a full OTA automatically:
./onn-root.sh --ota /path/to/OTA.zip --magisk Magisk-v26.1.apk
```

What it does, in order:
1. Refuses to run unless the bootloader is **unlocked**.
2. **Backs up** your stock `vendor_boot` to `root-work/stock/`.
3. Installs Magisk, stages its binaries on the device, **patches `vendor_boot`
   on-device** (with the lz4 workaround).
4. **Verifies** the result: `VNDRBOOT` magic, contains Magisk, and **fits the
   partition** — aborts (no flash) if any check fails.
5. Asks you to type **`yes`**, then flashes **both** slots and reboots.
6. Confirms `magiskd` is running.

Finally, **on the TV**: open the **Magisk** app. If it asks for *"additional
setup"*, accept it (it reboots once). Done.

Verify from your PC:
```bash
adb shell 'magisk -v'        # 26.1:MAGISK:R
adb shell 'su -c id'         # uid=0(root) ...  (grant the Superuser prompt on TV)
```

---

## If something goes wrong — RECOVERY

As long as you can reach `fastboot` (the script keeps you on USB), restore stock:
```bash
./onn-root.sh restore root-work/stock/vendor_boot.img
```
This flashes your **stock** `vendor_boot` back to both slots — back to normal.

Full reset to stock: a **factory reset** plus restoring stock `vendor_boot`
removes Magisk entirely. (`disable-user`/debloat changes also clear on reset.)

---

## Notes

- **Keep your stock images forever.** `root-work/stock/vendor_boot.img` (and the
  matching `boot.img`) are your lifeline.
- A Magisk-modified `vendor_boot` **will make incremental OTA updates fail** —
  expected, and helpful if you're blocking updates.
- This was validated on **YOC / `SGZ3.231226.096.A1` / Android 12 / armeabi-v7a**.
  Other builds differ; always use **your** build's stock image.

## License
MIT. No warranty. You root at your own risk, by your own choice.
