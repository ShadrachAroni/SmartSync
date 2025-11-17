#ifndef ALARM_SYSTEM_H
#define ALARM_SYSTEM_H

#include <Arduino.h>

class AlarmSystem {
public:
    AlarmSystem();

    void begin(uint8_t buzzerPin, uint8_t statusLedPin);
    void update(bool motionDetected, float distanceCm, float temperatureC);
    void triggerManualAlarm(uint16_t durationMs = 5000);
    void silence();

    bool isActive() const { return _alarmActive; }

private:
    uint8_t _buzzerPin;
    uint8_t _statusLedPin;
    bool _initialized;
    bool _alarmActive;
    unsigned long _alarmUntil;

    void _setBuzzer(bool enabled);
    void _setStatusLed(bool enabled);
};

#endif // ALARM_SYSTEM_H

