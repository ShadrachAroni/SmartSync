#ifndef DEVICE_STORAGE_H
#define DEVICE_STORAGE_H

#include <Arduino.h>
#include <Preferences.h>
#include <vector>

#include "../scheduler/ScheduleManager.h"
#include "../../include/config.h"

class DeviceStorage {
public:
    DeviceStorage();

    void begin(const char* ns = PREF_NAMESPACE);
    void end();
    bool ready() const { return _ready; }

    bool saveFanSpeed(uint8_t speed);
    uint8_t loadFanSpeed(uint8_t fallback = 0);

    bool saveLedBrightness(uint8_t brightness);
    uint8_t loadLedBrightness(uint8_t fallback = 128);

    bool saveAutoMode(bool enabled);
    bool loadAutoMode(bool fallback = false);

    bool saveSecurityEnabled(bool enabled);
    bool loadSecurityEnabled(bool fallback = true);

    bool saveSchedules(const std::vector<ScheduleEntry>& entries);
    bool loadSchedules(std::vector<ScheduleEntry>& entries);

private:
    Preferences _prefs;
    bool _ready;
};

#endif // DEVICE_STORAGE_H

