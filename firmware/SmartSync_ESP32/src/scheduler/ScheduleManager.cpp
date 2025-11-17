#include "ScheduleManager.h"

#include <time.h>

#include "../storage/DeviceStorage.h"
#include "../../include/config.h"

ScheduleManager::ScheduleManager()
    : _storage(nullptr),
      _callback(nullptr),
      _lastCheck(0),
      _nextId(1) {}

void ScheduleManager::begin(DeviceStorage* storage) {
    _storage = storage;
    _loadFromStorage();
}

void ScheduleManager::_loadFromStorage() {
    if (_storage == nullptr) return;

    _entries.clear();
    if (_storage->loadSchedules(_entries)) {
        uint8_t maxId = 0;
        for (const auto& entry : _entries) {
            if (entry.id > maxId) {
                maxId = entry.id;
            }
        }
        _nextId = maxId + 1;
    }
}

bool ScheduleManager::add(const ScheduleEntry& entry) {
    ScheduleEntry copy = entry;
    if (copy.id == 0) {
        copy.id = _nextId++;
    } else if (copy.id >= _nextId) {
        _nextId = copy.id + 1;
    }
    copy.lastExecutedMinute = 0xFFFF;
    _entries.push_back(copy);
    persist();
    return true;
}

bool ScheduleManager::remove(uint8_t id) {
    for (auto it = _entries.begin(); it != _entries.end(); ++it) {
        if (it->id == id) {
            _entries.erase(it);
            persist();
            return true;
        }
    }
    return false;
}

bool ScheduleManager::toggle(uint8_t id, bool enabled) {
    for (auto& entry : _entries) {
        if (entry.id == id) {
            entry.enabled = enabled;
            persist();
            return true;
        }
    }
    return false;
}

bool ScheduleManager::update(const ScheduleEntry& entry) {
    for (auto& existing : _entries) {
        if (existing.id == entry.id) {
            uint16_t lastMinute = existing.lastExecutedMinute;
            existing = entry;
            existing.lastExecutedMinute = lastMinute;
            persist();
            return true;
        }
    }
    return false;
}

void ScheduleManager::clear() {
    _entries.clear();
    persist();
}

void ScheduleManager::persist() {
    if (_storage != nullptr) {
        _storage->saveSchedules(_entries);
    }
}

void ScheduleManager::onExecute(ScheduleCallback callback) {
    _callback = callback;
}

uint16_t ScheduleManager::_currentMinuteOfDay() const {
    struct tm timeinfo;
    if (getLocalTime(&timeinfo)) {
        return timeinfo.tm_hour * 60 + timeinfo.tm_min;
    }

    const uint32_t minutes = (millis() / 60000) % (24 * 60);
    return static_cast<uint16_t>(minutes);
}

void ScheduleManager::loop() {
    if (_callback == nullptr || _entries.empty()) {
        return;
    }

    const unsigned long now = millis();
    if (now - _lastCheck < SCHEDULE_CHECK_INTERVAL) {
        return;
    }
    _lastCheck = now;

    const uint16_t minuteNow = _currentMinuteOfDay();
    bool dirty = false;

    for (auto& entry : _entries) {
        if (!entry.enabled) continue;

        const bool alreadyTriggered = entry.lastExecutedMinute == minuteNow;
        if (alreadyTriggered) continue;

        if (entry.hour * 60 + entry.minute == minuteNow) {
            entry.lastExecutedMinute = minuteNow;
            if (_callback) {
                _callback(entry);
            }
            if (!entry.repeatDaily) {
                entry.enabled = false;
                dirty = true;
            }
        } else if (!entry.repeatDaily && entry.lastExecutedMinute != 0xFFFF &&
                   minuteNow > entry.lastExecutedMinute + 1) {
            entry.enabled = false;
            dirty = true;
        }
    }

    if (dirty) {
        persist();
    }
}

