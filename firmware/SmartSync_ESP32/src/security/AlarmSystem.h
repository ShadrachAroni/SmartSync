#ifndef ALARM_SYSTEM_H
#define ALARM_SYSTEM_H

#include <Arduino.h>

class AlarmSystem {
public:
    AlarmSystem();

    void begin(uint8_t buzzerPin, uint8_t statusLedPin);
    void update(bool motionDetected, float distanceCm, float temperatureC);
    void triggerManualAlarm(uint16_t durationMs = 5000);
    void enableManualAlarm(bool enabled);
    void silence();

    bool isActive() const { return _alarmActive || _manualAlarmLatched || _manualAlarmActive; }
    bool isManualAlarmLatched() const { return _manualAlarmLatched; }
    bool isManualAlarmActive() const { return _manualAlarmActive; }
    bool isSecurityAlarmActive() const { return _alarmActive && !_manualAlarmLatched && !_manualAlarmActive; }

private:
    uint8_t _buzzerPin;
    uint8_t _statusLedPin;
    bool _initialized;
    bool _alarmActive;
    unsigned long _alarmUntil;
    bool _buzzerState;
    unsigned long _lastBuzzerToggle;
    uint8_t _buzzerPulseCount;
    bool _manualAlarmLatched;
    bool _manualAlarmActive;
    unsigned long _manualAlarmUntil;

    void _setBuzzer(bool enabled);
    void _setStatusLed(bool enabled);
};

#endif // ALARM_SYSTEM_H

