# M5Cardputer Loader

A resident **firmware launcher** for the [M5Cardputer](https://docs.m5stack.com/en/core/Cardputer).
It lives in the on-board flash and lets you keep a library of `.bin` firmwares
on the **microSD card** and boot into any of them from a simple list UI — plus
install new firmware over-the-air. Inspired by
[bmorcelli/Launcher](https://github.com/bmorcelli/Launcher) and
[tobozo/M5Stack-SD-Updater](https://github.com/tobozo/M5Stack-SD-Updater),
with the requested focus on **storing firmwares on the SD card and loading from there**.

---

## The hardware (research summary)

| Item        | Spec |
|-------------|------|
| MCU         | ESP32-S3FN8, dual-core Xtensa LX7 @ 240 MHz |
| Flash       | 8 MB (no PSRAM) |
| Display     | ST7789V2, 1.14", 240 × 135 px, SPI |
| Keyboard    | 56 keys (4 × 14 matrix) |
| microSD     | SPI — **CS=G12, MOSI=G14, CLK=G40, MISO=G39** |
| Audio       | NS4168 I²S speaker, SPM1423 MEMS mic |
| IR          | GPIO44 emitter |
| Radio       | 2.4 GHz Wi-Fi |
| Battery     | 120 mAh internal + 1400 mAh in base |
| Buttons     | Reset + User (G0) |

---

## How firmware loading works

The ESP32 can't overwrite the app partition it's currently executing from, so
the loader uses a **`factory` + `ota_0`** partition scheme (see
[`partitions.csv`](partitions.csv)):

```
factory  0x010000  1.5 MB   <- the LOADER (this project), always the boot fallback
ota_0    0x190000  6   MB   <- the "runtime slot": selected firmware is copied here
spiffs   0x790000  384 KB
coredump 0x7F0000  64  KB
```

**Launching a firmware from SD:**

1. The loader runs from `factory`, so `esp_ota_get_next_update_partition()` returns `ota_0`.
2. The selected `/firmware/*.bin` is streamed from SD straight into `ota_0` (`Update.writeStream`).
3. `Update.end(true)` marks `ota_0` as the boot partition and the device reboots into it.

Because ESP32 app images are relocated by the MMU at boot, a normal Cardputer
`.bin` runs fine from `ota_0` as long as **it fits in 6 MB** — no recompilation
for a special layout is needed (this is the same trick SD-Updater uses).

**OTA install** does the same thing but streams the `.bin` from an HTTPS URL
into `ota_0` instead of from the SD card.

### Returning to the loader

This is the one wrinkle of any ESP32 launcher (you can't run two apps at once).
Two supported mechanisms:

| Build env | How you get back to the loader |
|-----------|-------------------------------|
| **`cardputer-rollback`** (recommended) | The loaded app is booted in *pending-verify* state. If it never calls `esp_ota_mark_app_valid_cancel_rollback()` (most apps don't), the bootloader **rolls back to `factory` on the next RESET** — so just press RESET to return. No changes to the app needed. |
| **`cardputer`** (default, fast build) | The loaded app must be *launcher-aware*: include [`include/loader_return.h`](include/loader_return.h) and call `returnToLoader()` (it sets boot back to `factory` and reboots). Three lines of code. |

> If you flash an app that *does* use OTA itself (and marks itself valid), it
> will "stick" — re-flash the loader over USB, or use a launcher-aware build.

---

## SD card layout

Format the card **FAT32, ≤ 32 GB, MBR** (SDHC, not SDXC). Then:

```
/firmware/
    doom.bin
    marauder.bin
    nemo.bin
    ota.txt          <- optional: remote firmware URL list
```

`ota.txt` lines are `Display Name|https://.../app.bin` (see
[`sdcard/firmware/ota.txt`](sdcard/firmware/ota.txt)). Copy the contents of the
[`sdcard/`](sdcard/) folder to the root of your card to get started.

---

## Controls

| Key | Action |
|-----|--------|
| `;` | move up |
| `.` | move down |
| `ENTER` | select |
| `` ` `` or `BACKSPACE` | back / cancel |

In text-entry screens (WiFi / URL) just type; `ENTER` confirms, `` ` `` cancels.

---

## Features

- **SD Firmware** — scan `/firmware/*.bin`; **every installed firmware is a menu item**. Pick one, confirm, launch.
- **OTA Install** — pulls the live **M5Burner catalog** (Cardputer category, ~550 firmwares: Bruce, NEMO, Marauder, Doom, Evil-Cardputer, UIFlow…), lets you pick one, downloads it over Wi-Fi, **extracts the app partition, and saves it to `/firmware/<name>.bin`** so it shows up as a launchable SD menu item. `** Refresh catalog **` re-fetches the list.
- **Settings** — Wi-Fi SSID/password (saved to NVS), screen brightness, SD rescan, mount status.

### How OTA / M5Burner works

The M5Burner list is one ~2.2 MB JSON array (`m5burner-api.m5stack.com/api/firmware`) — bigger than RAM — so the loader **streams** it, brace-splits it into objects, keeps only `category == "cardputer"`, and writes a slim index (`name⇥version⇥file`) to `/firmware/_m5cat.tsv`. The menu reads that.

M5Burner `.bin`s are **full-flash images** (bootloader@0x0 + partition table@0x8000 + app@0x10000) downloaded from `m5burner-cdn.m5stack.com/firmware/<file>`. Since the loader boots apps from `ota_0`, the download path parses the image's partition table, finds the app partition, walks the ESP image segments, and writes **only the app** to the SD card. That app then launches like any other SD firmware.

> **Caveat:** firmwares that ship their own *data* partition (e.g. UIFlow's filesystem, a game's assets) may not fully work when launched from `ota_0`, because the live partition table is the loader's, not theirs. Self-contained apps (Bruce, NEMO, Marauder, most tools) work. Those needing a data partition are the case M5Burner's own full-chip flash is for.
- **About** — device + partition info and the active return-to-loader mode.
- Scrollable list UI with progress bars for both SD and OTA installs.

---

## Build & flash

Requires [PlatformIO](https://platformio.org/).

```bash
# Fast build (precompiled core). Apps must use loader_return.h to return.
pio run -e cardputer -t upload

# OR: rollback build — press RESET to return from any app (slower first build).
pio run -e cardputer-rollback -t upload

pio device monitor          # 115200 baud
```

The first flash installs the loader into `factory` and leaves `ota_0` empty.
After that you only ever flash over USB again if you want to update the loader
itself — everything else loads from SD or OTA.

---

## Project layout

```
platformio.ini              build config (two envs)
partitions.csv              factory + ota_0 8MB scheme
src/main.cpp                the loader firmware
include/loader_return.h     drop-in "return to loader" helper for your apps
sdcard/firmware/ota.txt     sample OTA URL list to copy onto the SD card
```

---

## Caveats / notes

- A loadable firmware must **fit in `ota_0` (6 MB)** and target the ESP32-S3.
- Apps that perform their **own** OTA and mark themselves valid will not auto-roll-back; use a launcher-aware build for those.
- HTTPS OTA uses `setInsecure()` (no certificate pinning) for convenience — fine
  for hobby use; tighten if you care about MITM.
- SD speed is set to 25 MHz; drop it in `mountSD()` if your card is flaky.

### Sources

- [M5Cardputer hardware docs](https://docs.m5stack.com/en/core/Cardputer)
- [bmorcelli/Launcher](https://github.com/bmorcelli/Launcher)
- [tobozo/M5Stack-SD-Updater](https://github.com/tobozo/M5Stack-SD-Updater)
