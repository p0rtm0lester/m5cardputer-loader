#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 p0rtm0lester
# Flash the M5Cardputer Loader.
#   ./flash-all.sh app    -> flash ONLY the loader app (0x10000). Fast; for app-code changes.
#                            The hooked bootloader + partitions stay untouched.
#   ./flash-all.sh full   -> flash hooked bootloader + partitions + wifi creds + app,
#                            then clear bootflag/otadata for a clean boot to the loader.
#                            Use after build-bootloader.sh or a partition-table change.
#
# Prereq for app:  pio run -e cardputer
# Prereq for full: ./build-bootloader.sh   (produces bl_build/bootloader.bin)
set -e
PORT="${PORT:-/dev/ttyACM0}"
P="$(cd "$(dirname "$0")" && pwd)"
ESPTOOL="$HOME/.platformio/packages/tool-esptoolpy/esptool.py"
FW="$P/.pio/build/cardputer/firmware.bin"
PT="$P/.pio/build/cardputer/partitions.bin"
BL="$P/bl_build/bootloader.bin"
WIFI="${WIFI:-/tmp/wifi_nvs_4000.bin}"   # optional 0x4000 NVS creds image (namespace "loader")
FLASH="--flash_mode dio --flash_freq 80m --flash_size 8MB"

mode="${1:-app}"
[ -f "$FW" ] || { echo "build the app first:  pio run -e cardputer"; exit 1; }

if [ "$mode" = "app" ]; then
    python3 "$ESPTOOL" --chip esp32s3 --port "$PORT" --baud 921600 \
        --before default_reset --after hard_reset write_flash $FLASH 0x10000 "$FW"
elif [ "$mode" = "full" ]; then
    [ -f "$BL" ] || { echo "build the bootloader first:  ./build-bootloader.sh"; exit 1; }
    ARGS="0x0 $BL 0x8000 $PT 0x10000 $FW"
    [ -f "$WIFI" ] && ARGS="0x0 $BL 0x8000 $PT 0x9000 $WIFI 0x10000 $FW"
    python3 "$ESPTOOL" --chip esp32s3 --port "$PORT" --baud 921600 \
        --before default_reset --after no_reset write_flash $FLASH $ARGS
    # clear bootflag (0xd000) + otadata (0xe000) -> hook boots the loader (factory)
    python3 "$ESPTOOL" --chip esp32s3 --port "$PORT" --before default_reset --after hard_reset \
        erase_region 0xd000 0x3000
else
    echo "usage: $0 [app|full]"; exit 1
fi
echo "done ($mode)."
