# onn 4K boot images — DEVICE-SPECIFIC, keep for recovery

> # ⚠️ THESE IMAGES ARE FOR ONE EXACT DEVICE/BUILD ONLY
>
> Everything here was downloaded, extracted, and verified for **my** unit:
>
> | | |
> |---|---|
> | Product | Walmart **onn. Google TV 4K**, model **YOC** (`onn_4k_gtv`) |
> | Build | **`SGZ3.231226.096.A1`** / `12865554` (Android 12, armeabi-v7a) |
> | Fingerprint | `onn/onn_4k_gtv/YOC:12/SGZ3.231226.096.A1/12865554:user/release-keys` |
>
> **These worked on THIS device. They may or may not work on another device —
> and flashing a mismatched image can SOFT- or HARD-BRICK it.**
>
> Do **NOT** flash these on:
> - a different model (2024 4K Pro / SNA, 2K Stick / XNA, Gen-1 2021, etc.), or
> - the same YOC model on a **different build** (e.g. `SGZ1…`, `SGZ2…`, or a
>   newer `SGZ3` patch).
>
> For any other unit, get **that** unit's own stock image from **its** matching
> full OTA (see `../ROOT.md`). Use these only as a reference
> or to recover **this** specific device.

---

## Files

| File | What it is | SHA-256 |
|---|---|---|
| `stock-SGZ3.231226.096.A1/vendor_boot.img` | **Stock** vendor_boot (recovery lifeline) | `27481be4…88a76c4` |
| `stock-SGZ3.231226.096.A1/boot.img` | Stock boot (reference) | `5ca601db…d457af63` |
| `vendor_boot-magisk_patched.img` | Magisk-26.1-patched vendor_boot **(rooted this device)** | `5ba9ed0b…157658b5` |
| `Magisk-v26.1.apk` | The exact Magisk version used | `ae1a02b1…f705dccb` |

The stock images were extracted from the build's full OTA:
`https://android.googleapis.com/packages/ota-api/package/070579547986cd91f559b421ff80a1993f22249c.zip`

## Use (this device only)

```bash
# re-apply root (flash the working patched image to both slots)
adb reboot bootloader
fastboot flash vendor_boot_a vendor_boot-magisk_patched.img
fastboot flash vendor_boot_b vendor_boot-magisk_patched.img
fastboot reboot

# back to 100% stock vendor_boot (un-root)
fastboot flash vendor_boot_a stock-SGZ3.231226.096.A1/vendor_boot.img
fastboot flash vendor_boot_b stock-SGZ3.231226.096.A1/vendor_boot.img
fastboot reboot
```

> Keep these files. If an update ever changes the build, they will no longer
> match — re-extract from the new build's OTA before flashing anything.
