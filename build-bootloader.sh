#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 p0rtm0lester
# Build the custom M5Cardputer Loader bootloader (with the boot-once hook) STANDALONE.
#
# Why: pioarduino's `framework = arduino` flow always flashes a PREBUILT bootloader and
# never compiles one, so a project bootloader_components/ hook never reaches the device.
# We therefore build the ESP-IDF bootloader sub-project directly (it DOES honor
# PROJECT_SOURCE_DIR/bootloader_components), producing bl_build/bootloader.bin which is
# flashed at 0x0. The hook (bootloader_components/loader_boot) forces a boot-once flag so
# RESET returns to the loader from ANY firmware, including self-validating ones (Bruce).
set -e
PROJ="$(cd "$(dirname "$0")" && pwd)"
export IDF_PATH="${IDF_PATH:-$HOME/.platformio/packages/framework-espidf}"
TC="$HOME/.platformio/packages/toolchain-xtensa-esp-elf/bin"
export PATH="$TC:$HOME/.platformio/packages/tool-cmake/bin:$HOME/.platformio/packages/tool-ninja:$PATH"
IDFPY="$(ls $HOME/.platformio/penv/.espidf-*/bin/python | head -1)"
ESPTOOL="$HOME/.platformio/packages/tool-esptoolpy/esptool.py"
BL="$IDF_PATH/components/bootloader/subproject"
BUILD="$PROJ/bl_build"

rm -rf "$BUILD"
cmake -S "$BL" -B "$BUILD" -G Ninja \
  -DIDF_TARGET=esp32s3 -DPYTHON_DEPS_CHECKED=1 -DPYTHON="$IDFPY" -DIDF_PATH="$IDF_PATH" \
  -DSDKCONFIG="$BUILD/sdkconfig" -DSDKCONFIG_DEFAULTS="$PROJ/bl_sdkconfig.defaults" \
  -DPROJECT_SOURCE_DIR="$PROJ" -DEXTRA_COMPONENT_DIRS="$IDF_PATH/components/bootloader"

# ninja's final elf2image step uses the IDF venv python which lacks esptool; let it fail
# there, then generate the .bin ourselves with the working esptool.
ninja -C "$BUILD" || true
python3 "$ESPTOOL" --chip esp32s3 elf2image --flash_mode dio --flash_freq 80m --flash_size 8MB \
  --min-rev-full 0 --max-rev-full 99 -o "$BUILD/bootloader.bin" "$BUILD/bootloader.elf"

echo "=== verifying hook is linked in ==="
"$TC/xtensa-esp32s3-elf-nm" "$BUILD/bootloader.elf" | grep -E "bootloader_after_init|bootloader_hooks_include" \
  && echo "OK: hooked bootloader at $BUILD/bootloader.bin" \
  || { echo "ERROR: hook not linked!"; exit 1; }
