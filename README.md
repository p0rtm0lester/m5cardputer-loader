# M5Cardputer Loader

A resident **firmware launcher** for the [M5Cardputer](https://docs.m5stack.com/en/core/Cardputer)
(ESP32‑S3, 8 MB). It lives in on‑board flash, keeps a library of firmwares as
`.bin` files on the microSD card, and boots into any of them from a simple list
UI — then **a tap of RESET returns you to the loader, for any firmware** (even
ones that self‑validate their OTA image, like Bruce).

Inspired by [bmorcelli/Launcher](https://github.com/bmorcelli/Launcher) and
[tobozo/M5Stack-SD-Updater](https://github.com/tobozo/M5Stack-SD-Updater).

---

## What it does

- **Main screen** lists installed firmwares (bright orange) at the top, then the
  functions (`-  OTA Install  -`, `-  WebUI Upload  -`, `-  Power  -`,
  `-  Settings  -`, `-  About  -`, `-  Reboot  -`). Firmware names are cleaned up
  for display (`Bruce.1.2.3.3.tar.bin` → `Bruce 1.2.3.3`).
- **Launch / Rename / Delete** any firmware. Launch copies it into `ota_0` and
  reboots into it.
- **RESET returns to the loader** — see *Return mechanism* below.
- **OTA Install** — pulls the live **M5Burner catalog** (Cardputer category,
  ~550 firmwares) and/or installs from a **GitHub release**, downloads over
  WiFi, and saves a launchable `.bin` to the SD card (with a progress bar).
- **WebUI Upload** — hosts a web page; upload/delete `.bin`s from a browser over WiFi.
- **Per‑firmware persistence** — each firmware keeps its own internal state
  (NVS + SPIFFS) across runs; files apps write to the SD card persist naturally.
- **Settings** — WiFi (SSID/pass in an isolated NVS), WiFi test, brightness, SD rescan.
- **Power** — battery %, auto‑dim timeout, power off / deep sleep.

### Controls
`;` up · `.` down · `ENTER` select · `` ` `` or `Backspace` back.

---

## Hardware (research summary)
ESP32‑S3FN8, dual‑core LX7 @240 MHz, **8 MB flash, no PSRAM**; ST7789V2 240×135;
56‑key keyboard; microSD on SPI **CS=G12 MOSI=G14 CLK=G40 MISO=G39**; G0 = the
user button (also the boot strapping pin — *don't hold it at power‑on*).

---

## Partition table ([`partitions.csv`](partitions.csv))

```
nvs_ldr   0x009000  16 KB   loader's OWN config (isolated from apps)
bootflag  0x00d000   4 KB   one-shot boot flag (read by the bootloader hook)
otadata   0x00e000   8 KB   boot selection
factory   0x010000 1.4 MB   the LOADER (this project)
ota_0     0x170000 6.06 MB  runtime slot (selected firmware runs here)
nvs       0x780000  24 KB   app NVS    (snapshotted per-firmware)
spiffs    0x786000 424 KB   app FS     (snapshotted per-firmware)
coredump  0x7f0000  64 KB
```

---

## Return mechanism (the important part)

A launched app becomes the boot target, and apps like Bruce mark their own image
"valid" — so plain OTA rollback can't bring you back. The fix is a **custom
bootloader hook** (`bootloader_components/loader_boot/loader_boot.c`):

- On every boot it reads the `bootflag` sector:
  - **magic set** → clear it, keep otadata → boot `ota_0` (the chosen firmware) **once**.
  - **not set** → wipe otadata → **force‑boot the loader** (`factory`).
- The loader's `armBootOnce()` writes the magic right before launching a firmware.

Because the bootloader runs *before* the app and rewrites the boot selection
itself, **RESET always returns to the loader regardless of what the app did.**

> pioarduino's `framework = arduino` always flashes a *prebuilt* bootloader and
> never compiles one, so the hook can't go through the normal build. It's built
> standalone (see below) and flashed at `0x0`.

---

## Building & flashing

Requires [PlatformIO](https://platformio.org/) (`pip install platformio`).

```bash
# 1) App (fast, ~11s)
pio run -e cardputer

# 2) Hooked bootloader (only needed once, or when the hook/partitions change)
./build-bootloader.sh            # -> bl_build/bootloader.bin (verifies the hook is linked)

# 3) Flash
./flash-all.sh full              # bootloader + partitions + (wifi creds) + app, first time
./flash-all.sh app               # JUST the app at 0x10000, for day-to-day code changes
```

`build-bootloader.sh` builds the ESP‑IDF bootloader sub‑project directly (it
honors the project's `bootloader_components/`), using the toolchain + IDF venv
that pioarduino already installed. `flash-all.sh full` also clears
`bootflag`/`otadata` so the device boots cleanly into the loader.

Optional WiFi creds: generate a 16 KB NVS image (namespace `loader`, keys
`ssid`/`pass`) and place it at `/tmp/wifi_nvs_4000.bin`; `flash-all.sh full`
writes it to `nvs_ldr` (0x9000). Or just set WiFi on‑device in Settings.

---

## SD card

Format **FAT32, ≤ 32 GB, MBR**. Firmwares live in `/firmware/*.bin`. The loader
manages it: `/firmware/_m5cat.tsv` (cached M5Burner index) and
`/firmware/data/<fw>/` (per‑firmware NVS/SPIFFS snapshots) are created automatically.

---

## Known limitation

Firmwares that need their **own data partition** (e.g. UIFlow, or some Marauder
builds that expect a specific SPIFFS/partition layout) may not run when launched
from `ota_0`, because the live partition table is the loader's. Self‑contained
apps (Bruce, NEMO, most tools) work fine. A future "partition‑manager" mode could
rewrite the table per‑firmware to cover these.

---

## Project layout

```
src/main.cpp                              the loader (UI, SD, OTA, WebUI, Power, persistence)
partitions.csv                            8MB table (nvs_ldr/bootflag/factory/ota_0/nvs/spiffs)
bootloader_components/loader_boot/        the boot-once bootloader hook
bl_sdkconfig.defaults                     sdkconfig defaults for the standalone bootloader build
build-bootloader.sh                       builds bl_build/bootloader.bin (with the hook)
flash-all.sh                              flash helper (app | full)
platformio.ini                            app build config
```

### Sources
- [M5Cardputer hardware docs](https://docs.m5stack.com/en/core/Cardputer)
- [bmorcelli/Launcher](https://github.com/bmorcelli/Launcher)
- [tobozo/M5Stack-SD-Updater](https://github.com/tobozo/M5Stack-SD-Updater)
