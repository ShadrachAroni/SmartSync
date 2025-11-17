#ifndef SCHEDULE_MANAGER_H
#define SCHEDULE_MANAGER_H

#include <Arduino.h>
#include <vector>

struct ScheduleEntry {
    uint8_t id = 0;
    uint8_t hour = 0;
    uint8_t minute = 0;
    uint8_t fanSpeed = 0;
    uint8_t ledBrightness = 0;
    bool enabled = true;
    bool repeatDaily = true;
    uint16_t lastExecutedMinute = 0xFFFF;
};

class DeviceStorage; // Forward declaration

class ScheduleManager {
public:
    typedef void (*ScheduleCallback)(const ScheduleEntry& entry);

    ScheduleManager();

    void begin(DeviceStorage* storage);
    void loop();

    bool add(const ScheduleEntry& entry);
    bool remove(uint8_t id);
    bool toggle(uint8_t id, bool enabled);
    bool update(const ScheduleEntry& entry);
    void clear();

    const std::vector<ScheduleEntry>& all() const { return _entries; }

    void onExecute(ScheduleCallback callback);
    void persist();

private:
    DeviceStorage* _storage;
    std::vector<ScheduleEntry> _entries;
    ScheduleCallback _callback;
    unsigned long _lastCheck;
    uint8_t _nextId;

    void _loadFromStorage();
    uint16_t _currentMinuteOfDay() const;
};

#endif // SCHEDULE_MANAGER_H

