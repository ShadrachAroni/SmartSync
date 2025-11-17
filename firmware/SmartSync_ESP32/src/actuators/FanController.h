#ifndef FAN_CONTROLLER_H
#define FAN_CONTROLLER_H

#include <Arduino.h>

class FanController {
public:
    FanController();

    void begin(uint8_t pin,
               uint8_t channel,
               uint32_t frequency,
               uint8_t resolution);

    void setSpeed(uint8_t speed);
    void smoothTo(uint8_t targetSpeed, uint16_t durationMs = 400);
    void powerOff();

    uint8_t getSpeed() const { return _currentSpeed; }
    bool isReady() const { return _initialized; }

    void attachStatusLed(uint8_t ledPin);
    void loop();

private:
    uint8_t _pin;
    uint8_t _channel;
    uint32_t _frequency;
    uint8_t _resolution;
    bool _initialized;

    uint8_t _currentSpeed;
    uint8_t _targetSpeed;
    unsigned long _rampStart;
    unsigned long _rampDuration;

    uint8_t _statusLedPin;

    void _apply(uint8_t speed);
    void _updateStatusLed();
};

#endif // FAN_CONTROLLER_H

