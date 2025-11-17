#include "DeviceStorage.h"
#include <ArduinoJson.h>

DeviceStorage::DeviceStorage() : _ready(false) {}

void DeviceStorage::begin(const char* ns) {
    if (_prefs.begin(ns, false)) {
        _ready = true;
    }
}

void DeviceStorage::end() {
    _prefs.end();
    _ready = false;
}

bool DeviceStorage::saveFanSpeed(uint8_t speed) {
    return _ready ? _prefs.putUInt(PREF_FAN_SPEED, speed) > 0 : false;
}

uint8_t DeviceStorage::loadFanSpeed(uint8_t fallback) {
    return _ready ? _prefs.getUInt(PREF_FAN_SPEED, fallback) : fallback;
}

bool DeviceStorage::saveLedBrightness(uint8_t brightness) {
    return _ready ? _prefs.putUInt(PREF_LED_BRIGHTNESS, brightness) > 0 : false;
}

uint8_t DeviceStorage::loadLedBrightness(uint8_t fallback) {
    return _ready ? _prefs.getUInt(PREF_LED_BRIGHTNESS, fallback) : fallback;
}

bool DeviceStorage::saveAutoMode(bool enabled) {
    return _ready ? _prefs.putBool(PREF_AUTO_MODE, enabled) : false;
}

bool DeviceStorage::loadAutoMode(bool fallback) {
    return _ready ? _prefs.getBool(PREF_AUTO_MODE, fallback) : fallback;
}

bool DeviceStorage::saveSecurityEnabled(bool enabled) {
    return _ready ? _prefs.putBool(PREF_SECURITY_ENABLED, enabled) : false;
}

bool DeviceStorage::loadSecurityEnabled(bool fallback) {
    return _ready ? _prefs.getBool(PREF_SECURITY_ENABLED, fallback) : fallback;
}

bool DeviceStorage::saveSchedules(const std::vector<ScheduleEntry>& entries) {
    if (!_ready) return false;

    DynamicJsonDocument doc(2048);
    JsonArray array = doc.createNestedArray("items");
    for (const auto& entry : entries) {
        JsonObject obj = array.createNestedObject();
        obj["id"] = entry.id;
        obj["hour"] = entry.hour;
        obj["minute"] = entry.minute;
        obj["fan"] = entry.fanSpeed;
        obj["led"] = entry.ledBrightness;
        obj["enabled"] = entry.enabled;
        obj["repeat"] = entry.repeatDaily;
    }

    String payload;
    serializeJson(doc, payload);
    return _prefs.putString("schedules", payload) > 0;
}

bool DeviceStorage::loadSchedules(std::vector<ScheduleEntry>& entries) {
    if (!_ready) return false;

    String payload = _prefs.getString("schedules", "");
    if (payload.isEmpty()) return false;

    DynamicJsonDocument doc(2048);
    auto error = deserializeJson(doc, payload);
    if (error) {
        return false;
    }

    entries.clear();
    JsonArray array = doc["items"].as<JsonArray>();
    for (JsonObject obj : array) {
        ScheduleEntry entry;
        entry.id = obj["id"] | 0;
        entry.hour = obj["hour"] | 0;
        entry.minute = obj["minute"] | 0;
        entry.fanSpeed = obj["fan"] | 0;
        entry.ledBrightness = obj["led"] | 0;
        entry.enabled = obj["enabled"] | true;
        entry.repeatDaily = obj["repeat"] | true;
        entry.lastExecutedMinute = 0xFFFF;
        entries.push_back(entry);
    }

    return true;
}

