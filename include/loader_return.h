// =====================================================================
//  loader_return.h  —  drop-in "return to the M5Cardputer Loader" helper
// ---------------------------------------------------------------------
//  Include this in YOUR firmware (the app that gets launched from SD) so
//  it can hand control back to the loader. This is only required when the
//  loader is built WITHOUT bootloader rollback (the default [env:cardputer]
//  build). With [env:cardputer-rollback], a plain RESET already returns to
//  the loader automatically and you don't need this file at all.
//
//  The loader lives in the `factory` partition. returnToLoader() simply
//  sets the boot partition back to factory and reboots.
//
//  Usage in your app:
//      #include "loader_return.h"
//      ...
//      // e.g. when the user presses the backtick (`) key:
//      if (userWantsToExit) returnToLoader();
// =====================================================================
#pragma once
#include "esp_ota_ops.h"
#include "esp_system.h"

static inline void returnToLoader() {
    const esp_partition_t* factory = esp_partition_find_first(
        ESP_PARTITION_TYPE_APP, ESP_PARTITION_SUBTYPE_APP_FACTORY, nullptr);
    if (factory) {
        esp_ota_set_boot_partition(factory);
    }
    esp_restart();
}
