#include "AlarmSystem.h"
#include "../../include/config.h"

AlarmSystem::AlarmSystem()
    : _buzzerPin(255),
      _statusLedPin(255),
      _initialized(false),
      _alarmActive(false),
      _alarmUntil(0),
      _buzzerState(false),
      _lastBuzzerToggle(0),
      _buzzerPulseCount(0),
      _manualAlarmLatched(false),
      _manualAlarmActive(false),
      _manualAlarmUntil(0) {}

void AlarmSystem::begin(uint8_t buzzerPin, uint8_t statusLedPin) {
    _buzzerPin = buzzerPin;
    _statusLedPin = statusLedPin;

    if (_buzzerPin != 255) {
        pinMode(_buzzerPin, OUTPUT);
    }
    if (_statusLedPin != 255) {
        pinMode(_statusLedPin, OUTPUT);
    }
    _setBuzzer(false);
    _setStatusLed(false);

    _initialized = true;
}

void AlarmSystem::_setBuzzer(bool enabled) {
    if (_buzzerPin == 255) return;
    digitalWrite(_buzzerPin, enabled ? HIGH : LOW);
    _buzzerState = enabled;
}

void AlarmSystem::_setStatusLed(bool enabled) {
    if (_statusLedPin == 255) return;
    digitalWrite(_statusLedPin, enabled ? HIGH : LOW);
}

void AlarmSystem::triggerManualAlarm(uint16_t durationMs) {
    if (!_initialized) return;
    _manualAlarmActive = true;
    _manualAlarmUntil = millis() + durationMs;
    _buzzerPulseCount = 0;
    _lastBuzzerToggle = millis();
    _setStatusLed(true);
    // Don't set _manualAlarmLatched - this is a timed alarm, not latched
}

void AlarmSystem::enableManualAlarm(bool enabled) {
    if (!_initialized) return;

    if (enabled) {
        if (!_manualAlarmLatched) {
            _manualAlarmLatched = true;
            _buzzerPulseCount = 0;
            _lastBuzzerToggle = millis();
        }
        _setStatusLed(true);
    } else {
        if (_manualAlarmLatched) {
            _manualAlarmLatched = false;
            _alarmActive = false;
            _setBuzzer(false);
            _setStatusLed(false);
            _buzzerPulseCount = 0;
            _lastBuzzerToggle = 0;
        } else {
            silence();
        }
    }
}

void AlarmSystem::silence() {
    _alarmActive = false;
    // Don't silence manual alarms (SOS) - they have their own timer
    if (!_manualAlarmLatched && !_manualAlarmActive) {
        _setBuzzer(false);
        _setStatusLed(false);
        _buzzerPulseCount = 0;
        _lastBuzzerToggle = 0;
    }
}

void AlarmSystem::update(bool motionDetected, float distanceCm, float temperatureC) {
    if (!_initialized) return;

    const unsigned long now = millis();

    // Check if manual alarm (SOS) has expired
    if (_manualAlarmActive && now >= _manualAlarmUntil) {
        _manualAlarmActive = false;
        if (!_manualAlarmLatched && !_alarmActive) {
            _setBuzzer(false);
            _setStatusLed(false);
            _buzzerPulseCount = 0;
            _lastBuzzerToggle = 0;
            return;
        }
    }

    // Check for security alarm conditions (only if not a manual alarm)
    if (!_manualAlarmActive && !_manualAlarmLatched) {
        const bool proximityAlert = (distanceCm > 0 && distanceCm < PROXIMITY_THRESHOLD);
        const bool tempAlert = temperatureC > (TEMP_MAX_THRESHOLD + 2.0f);

        if (motionDetected && proximityAlert) {
            _alarmActive = true;
            _alarmUntil = now + 3000;
            _buzzerPulseCount = 0;
            _lastBuzzerToggle = now;
        } else if (tempAlert) {
            _alarmActive = true;
            _alarmUntil = now + 2000;
            _buzzerPulseCount = 0;
            _lastBuzzerToggle = now;
        } else if (_alarmActive && now >= _alarmUntil) {
            _alarmActive = false;
        }
    }

    const bool shouldAlarm = _manualAlarmActive || _manualAlarmLatched || _alarmActive;

    if (!shouldAlarm) {
        _setBuzzer(false);
        _setStatusLed(false);
        _buzzerPulseCount = 0;
        _lastBuzzerToggle = 0;
        return;
    }

    // Smoke detector pattern: beep-beep-beep-pause (100ms beep, 100ms pause, repeat 3x, then 500ms pause)
    const unsigned long beepOnTime = 100;      // Beep duration
    const unsigned long beepOffTime = 100;     // Pause between beeps
    const unsigned long pauseTime = 500;        // Long pause after 3 beeps
    const unsigned long beepCycle = beepOnTime + beepOffTime;  // One beep cycle
    const unsigned long fullCycle = beepCycle * 3 + pauseTime; // Full pattern cycle

    // Calculate time since last toggle (or start of alarm)
    unsigned long timeSinceStart = now - _lastBuzzerToggle;
    unsigned long timeInCycle = timeSinceStart % fullCycle;

    // Determine if we're in a beep phase (first 3 beeps) or pause phase
    if (timeInCycle < beepCycle * 3) {
        // We're in one of the 3 beeps
        unsigned long beepIndex = timeInCycle / beepCycle;
        unsigned long phaseInBeep = timeInCycle % beepCycle;
        
        if (phaseInBeep < beepOnTime) {
            // Beep ON
            if (!_buzzerState) {
                _setBuzzer(true);
            }
        } else {
            // Beep OFF (pause between beeps)
            if (_buzzerState) {
                _setBuzzer(false);
            }
        }
    } else {
        // We're in the long pause after 3 beeps
        if (_buzzerState) {
            _setBuzzer(false);
        }
    }

    _setStatusLed(true);
}

