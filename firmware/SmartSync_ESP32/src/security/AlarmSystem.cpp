#include "AlarmSystem.h"
#include "../../include/config.h"

AlarmSystem::AlarmSystem()
    : _buzzerPin(255),
      _statusLedPin(255),
      _initialized(false),
      _alarmActive(false),
      _alarmUntil(0) {}

void AlarmSystem::begin(uint8_t buzzerPin, uint8_t statusLedPin) {
    _buzzerPin = buzzerPin;
    _statusLedPin = statusLedPin;

    pinMode(_buzzerPin, OUTPUT);
    pinMode(_statusLedPin, OUTPUT);
    _setBuzzer(false);
    _setStatusLed(false);

    _initialized = true;
}

void AlarmSystem::_setBuzzer(bool enabled) {
    if (_buzzerPin == 255) return;
    digitalWrite(_buzzerPin, enabled ? HIGH : LOW);
}

void AlarmSystem::_setStatusLed(bool enabled) {
    if (_statusLedPin == 255) return;
    digitalWrite(_statusLedPin, enabled ? HIGH : LOW);
}

void AlarmSystem::triggerManualAlarm(uint16_t durationMs) {
    if (!_initialized) return;
    _alarmActive = true;
    _alarmUntil = millis() + durationMs;
    _setBuzzer(true);
    _setStatusLed(true);
}

void AlarmSystem::silence() {
    _alarmActive = false;
    _setBuzzer(false);
    _setStatusLed(false);
}

void AlarmSystem::update(bool motionDetected, float distanceCm, float temperatureC) {
    if (!_initialized) return;

    const bool proximityAlert = (distanceCm > 0 && distanceCm < PROXIMITY_THRESHOLD);
    const bool tempAlert = temperatureC > (TEMP_MAX_THRESHOLD + 2.0f);

    if (motionDetected && proximityAlert) {
        _alarmActive = true;
        _alarmUntil = millis() + 3000;
    } else if (tempAlert) {
        _alarmActive = true;
        _alarmUntil = millis() + 2000;
    }

    if (_alarmActive) {
        const unsigned long now = millis();
        if (now >= _alarmUntil) {
            silence();
        } else {
            _setBuzzer(true);
            _setStatusLed(true);
        }
    } else {
        _setBuzzer(false);
        _setStatusLed(false);
    }
}

