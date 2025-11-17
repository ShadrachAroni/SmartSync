#include "FanController.h"

FanController::FanController()
    : _pin(0),
      _channel(0),
      _frequency(0),
      _resolution(8),
      _initialized(false),
      _currentSpeed(0),
      _targetSpeed(0),
      _rampStart(0),
      _rampDuration(0),
      _statusLedPin(255) {}

void FanController::begin(uint8_t pin,
                          uint8_t channel,
                          uint32_t frequency,
                          uint8_t resolution) {
    _pin = pin;
    _channel = channel;
    _frequency = frequency;
    _resolution = resolution;

    ledcSetup(_channel, _frequency, _resolution);
    ledcAttachPin(_pin, _channel);
    _apply(0);

    _initialized = true;
}

void FanController::attachStatusLed(uint8_t ledPin) {
    _statusLedPin = ledPin;
    pinMode(_statusLedPin, OUTPUT);
    digitalWrite(_statusLedPin, LOW);
}

void FanController::_apply(uint8_t speed) {
    if (!_initialized) {
        return;
    }

    _currentSpeed = speed;
    ledcWrite(_channel, speed);
    _updateStatusLed();
}

void FanController::setSpeed(uint8_t speed) {
    _targetSpeed = speed;
    _rampDuration = 0;
    _apply(speed);
}

void FanController::smoothTo(uint8_t targetSpeed, uint16_t durationMs) {
    if (!_initialized) {
        return;
    }

    _targetSpeed = targetSpeed;
    _rampDuration = durationMs;
    _rampStart = millis();
}

void FanController::powerOff() {
    smoothTo(0, 250);
}

void FanController::_updateStatusLed() {
    if (_statusLedPin == 255) {
        return;
    }

    const bool shouldGlow = _currentSpeed > 10;
    digitalWrite(_statusLedPin, shouldGlow ? HIGH : LOW);
}

void FanController::loop() {
    if (!_initialized || _rampDuration == 0) {
        return;
    }

    const unsigned long now = millis();
    const unsigned long elapsed = now - _rampStart;

    if (elapsed >= _rampDuration) {
        _apply(_targetSpeed);
        _rampDuration = 0;
        return;
    }

    const float progress = static_cast<float>(elapsed) / _rampDuration;
    const int delta = static_cast<int>(_targetSpeed) - static_cast<int>(_currentSpeed);
    const uint8_t interpolated = _currentSpeed + delta * progress;
    ledcWrite(_channel, interpolated);
}

