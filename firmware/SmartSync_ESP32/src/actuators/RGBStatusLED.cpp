#include "RGBStatusLED.h"
#include "../../include/config.h"

RGBStatusLED::RGBStatusLED()
    : _initialized(false),
      _commonAnode(true),
      _redPin(255),
      _greenPin(255),
      _bluePin(255),
      _redChannel(255),
      _greenChannel(255),
      _blueChannel(255),
      _mode(Mode::SCANNING),
      _alertOn(false),
      _lastBlink(0) {}

bool RGBStatusLED::begin(uint8_t redPin,
                         uint8_t greenPin,
                         uint8_t bluePin,
                         uint8_t redChannel,
                         uint8_t greenChannel,
                         uint8_t blueChannel,
                         bool commonAnode) {
    _redPin = redPin;
    _greenPin = greenPin;
    _bluePin = bluePin;
    _redChannel = redChannel;
    _greenChannel = greenChannel;
    _blueChannel = blueChannel;
    _commonAnode = commonAnode;

    pinMode(_redPin, OUTPUT);
    pinMode(_greenPin, OUTPUT);
    pinMode(_bluePin, OUTPUT);

    ledcSetup(_redChannel, RGB_LED_PWM_FREQ, RGB_LED_PWM_RESOLUTION);
    ledcSetup(_greenChannel, RGB_LED_PWM_FREQ, RGB_LED_PWM_RESOLUTION);
    ledcSetup(_blueChannel, RGB_LED_PWM_FREQ, RGB_LED_PWM_RESOLUTION);

    ledcAttachPin(_redPin, _redChannel);
    ledcAttachPin(_greenPin, _greenChannel);
    ledcAttachPin(_bluePin, _blueChannel);

    _initialized = true;
    _applyColor(0, 0, 0);
    setMode(Mode::SCANNING);
    return true;
}

void RGBStatusLED::setMode(Mode mode) {
    if (!_initialized) {
        return;
    }

    bool modeChanged = (_mode != mode);
    if (modeChanged) {
        _mode = mode;
        _alertOn = false;
        _lastBlink = millis();
    }

    switch (_mode) {
        case Mode::CONNECTED:
            _applyColor(0, 60, 20);
            break;
        case Mode::DISARMED:
            _applyColor(120, 60, 0); // dim amber
            break;
        case Mode::SCANNING:
            _applyColor(0, 0, 0); // breathing handled in update
            break;
        case Mode::ALERT:
            _applyColor(255, 0, 0); // will blink in update
            break;
        case Mode::IDLE:
            _applyColor(0, 0, 0); // fully off
            break;
    }
}

void RGBStatusLED::update() {
    if (!_initialized) {
        return;
    }

    const unsigned long now = millis();

    if (_mode == Mode::SCANNING) {
        const uint16_t period = 2000;
        uint16_t phase = now % period;
        uint8_t level;
        if (phase < period / 2) {
            level = map(phase, 0, period / 2, 20, 255);
        } else {
            level = map(phase - period / 2, 0, period / 2, 255, 20);
        }
        _applyColor(level, 0, 0);
    } else if (_mode == Mode::CONNECTED) {
        const uint16_t period = 1600;
        uint16_t phase = now % period;
        uint8_t level;
        if (phase < period / 2) {
            level = map(phase, 0, period / 2, 30, 200);
        } else {
            level = map(phase - period / 2, 0, period / 2, 200, 30);
        }
        _applyColor(0, level, 40); // teal breathing
    } else if (_mode == Mode::ALERT) {
        if (now - _lastBlink >= 250) {
            _alertOn = !_alertOn;
            _applyColor(_alertOn ? 255 : 0, 0, 0);
            _lastBlink = now;
        }
    }
}

void RGBStatusLED::_applyColor(uint8_t r, uint8_t g, uint8_t b) {
    if (!_initialized) {
        return;
    }

    auto writeChannel = [&](uint8_t channel, uint8_t value) {
        uint8_t duty = _commonAnode ? (255 - value) : value;
        ledcWrite(channel, duty);
    };

    writeChannel(_redChannel, r);
    writeChannel(_greenChannel, g);
    writeChannel(_blueChannel, b);
}

void RGBStatusLED::flash(uint8_t r, uint8_t g, uint8_t b, uint16_t durationMs) {
    if (!_initialized) {
        return;
    }
    Mode previous = _mode;
    _applyColor(r, g, b);
    delay(durationMs);
    setMode(previous);
}

