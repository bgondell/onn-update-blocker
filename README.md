# Block the forced (bricking) update on the onn 4K Google TV — with a Linux laptop

The 2023 Walmart **onn 4K Google TV (YOC)** — and some other Android TV / Google TV devices —
**force a system update during the setup wizard**, and on affected units that update **corrupts /
bricks the device**. You factory-reset, and it just tries to update and break again.

These scripts turn a **Linux laptop into a Wi‑Fi hotspot** that gives the device internet but
**DNS‑blackholes Google's OTA update servers**, so the bad update can never download. The device
runs normally; it just can't update itself.

> ⚠️ Use on hardware you own. Blocking `gvt1`/`gvt2` also blocks Play **app** updates. This is a
> DNS-level mitigation, not a guarantee for every firmware. No warranty.

> 🧹 **Already past setup and just want to stop updates + remove bloat on the device itself?**
> See **[DEBLOAT.md](DEBLOAT.md)** — a separate, **no-root, USB-only** toolkit
> (`onn-adb-connect.sh` + `onn-debloat.sh`) that disables the on-device updaters and strips
> bloatware via ADB. Fully reversible. It does **not** need this hotspot.

> 🔓 **Want full root?** See **[ROOT.md](ROOT.md)** + `onn-root.sh` — a Magisk root for the
> YOC over USB (handles the lz4-legacy `vendor_boot` quirk, verifies + backs up, one-command
> rollback). **⚠️ HIGH RISK, entirely your choice — can brick the device. Read the warnings.**

## How it works

1. **NetworkManager "shared" hotspot** on the laptop → DHCP + DNS (dnsmasq) + NAT for the device.
2. A **dnsmasq blocklist** returns `0.0.0.0` for the OTA hosts.
3. Two-phase blocking, because Google's wizard is stubborn:
   - **Always blocked — the *download*** (`gvt1.com`, `gvt2.com`, `update.googleapis.com`).
     This alone gives "update available → can't download → continues", which is brick-proof.
   - **Blocked only during the wizard — the *check*** (`android.googleapis.com`,
     `play.googleapis.com`, `dl.google.com` …). Blocking these makes the wizard report
     "couldn't check / up to date" so it lets you **past the forced-update screen**. These hosts
     are also used for **Google sign-in**, so you turn them back on to finish setup.

## VPN / geolocation (optional, but often needed)

A VPN is **not required to block updates**, but it has a second, important use: many of these devices
**geo-restrict their setup by IP address**. If you're setting up a US device (like the onn) **from
outside the US**, run a VPN **on the laptop** with an exit in the device's home country (e.g. a US
server).

You don't configure anything on the device for this. The hotspot **NATs the device's traffic out
through the laptop's default route**, so whenever the VPN is up, the device automatically appears to
be in the VPN's country and passes the geo-check. Turn the VPN off and the device uses your real
location.

If your VPN has a **killswitch / firewall** (PIA, Mullvad lockdown, UFW…), it will otherwise drop the
hotspot's DHCP and forwarded traffic — `onn-hotspot.sh` opens the needed holes for the `ap0` subnet
(re-apply anytime with `sudo ./onn-hotspot.sh fw`), and you should enable "Allow LAN" in the VPN app.
No VPN and an open firewall? The script's firewall step simply no-ops.

## Requirements

- Linux with **NetworkManager**, **dnsmasq**, **iw**, `nft`, `dig`, and **root**.
- A Wi‑Fi card that supports **AP + STA at the same time** (`iw list` → "valid interface
  combinations" shows `AP`). Most Intel/MediaTek cards do. **Single-radio caveat:** the hotspot is
  forced onto the **same channel** as your internet uplink — the script handles this automatically.
- The device must support **2.4 GHz** (most reliable). Connect your laptop's uplink to a **2.4 GHz**
  network so the hotspot lands on 2.4 GHz too.

## Setup

```bash
chmod +x onn-*.sh
# 1) Edit onn-hotspot.sh -> set HOTSPOT_SSID / HOTSPOT_PSK (and UPLINK_SSID if you want it forced)
# 2) Make sure the laptop is online via a 2.4 GHz Wi-Fi network.

sudo ./onn-hotspot.sh up           # start the hotspot (verify it prints gw/DNS=10.42.0.1)
```

Then on the device — **factory reset** and at Wi‑Fi setup join your hotspot SSID:

```bash
# A) get PAST the forced update:
sudo ./onn-setupmode.sh on         # blocks the update *check*
#    ...run the wizard; it should pass the update step...

# B) when it reaches sign-in and says "can't connect to internet":
sudo ./onn-setupmode.sh off        # restores sign-in hosts (download stays blocked)
#    ...hit Retry on the device; finish setup...
```

After setup, **leave the hotspot as the device's permanent network**. It will occasionally say
"update available" and fail to download — that's the whole point. Done.

Tear down later with `sudo ./onn-hotspot.sh down`.

## Watching / debugging

```bash
sudo ./onn-watch-dns.sh on     # live DNS log — see exactly what the device requests
                               #   'config <host> is 0.0.0.0' = blocked, 'forwarded' = allowed
sudo ./onn-watch-dns.sh off
```

If an **update slips through**, run the watcher during a check, find any update-ish host that's
`forwarded` (e.g. `*.googleapis.com`, `*.gvt1.com`), and add it to `BLOCK_DOMAINS` in
`onn-hotspot.sh` (permanent) or `CHECK_DOMAINS` in `onn-setupmode.sh` (wizard-only).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `802.1X supplicant took too long` / AP won't start | Uplink and AP on different channels. The script auto-matches them; if your router uses **auto-channel** and keeps hopping, **pin its 2.4 GHz channel** (1/6/11) in the router admin. |
| Device gets no IP ("IP configuration failure") | A firewall/**VPN killswitch** (PIA, UFW) is dropping DHCP/forwarding. `onn-hotspot.sh` opens the needed holes; re-apply with `sudo ./onn-hotspot.sh fw`. Also enable "Allow LAN" in your VPN. |
| Device won't even see the hotspot | Move it within ~2 m; some radios report low TX power. Confirm uplink is on **2.4 GHz**. |
| Stuck at "update available → can't download, can't continue" | You only blocked the download. Use `onn-setupmode.sh on` to also block the **check**. |
| "Can't connect to internet" at sign-in | The check-block is still on — `onn-setupmode.sh off`, then Retry. |

## Last resort

If the wizard can't be beaten by DNS on your firmware, the community route for the YOC is to
**bypass setup via the bootloader** (hold the reset button while connecting the device to a PC over
USB → `fastboot`), before the forced update locks things. See the XDA YOC guide.

## Credits

Solution worked out interactively for a single-radio **MediaTek MT7922** laptop on **CachyOS** behind
a **PIA** VPN. Adapt the config block to your machine. PRs welcome.
