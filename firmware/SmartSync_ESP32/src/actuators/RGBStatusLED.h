#ifndef RGB_STATUS_LED_H
#define RGB_STATUS_LED_H

#include <Arduino.h>

class RGBStatusLED {
public:
    enum class Mode {
        IDLE,
        SCANNING,
        CONNECTED,
        DISARMED,
        ALERT
    };

    RGBStatusLED();

    bool begin(uint8_t redPin,
               uint8_t greenPin,
               uint8_t bluePin,
               uint8_t redChannel,
               uint8_t greenChannel,
               uint8_t blueChannel,
               bool commonAnode = true);

    void setMode(Mode mode);
    void update();
    bool isInitialized() const { return _initialized; }
    void flash(uint8_t r, uint8_t g, uint8_t b, uint16_t durationMs = 120);

private:
    bool _initialized;
    bool _commonAnode;
    uint8_t _redPin;
    uint8_t _greenPin;
    uint8_t _bluePin;
    uint8_t _redChannel;
    uint8_t _greenChannel;
    uint8_t _blueChannel;
    Mode _mode;
    bool _alertOn;
    unsigned long _lastBlink;

    void _applyColor(uint8_t r, uint8_t g, uint8_t b);
};

#endif // RGB_STATUS_LED_H

