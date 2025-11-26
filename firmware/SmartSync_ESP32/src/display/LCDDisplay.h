#ifndef LCD_DISPLAY_H
#define LCD_DISPLAY_H

#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

class LCDDisplay {
public:
    LCDDisplay();
    ~LCDDisplay();
    
    bool begin(uint8_t address = 0x27, uint8_t cols = 20, uint8_t rows = 4);
    void update();
    
    void setConnectionStatus(bool connected);
    void setRoomName(const char* roomName);
    void setIsPrimaryHub(bool isPrimary);
    void showWelcome();
    void showStatus(const char* line1, const char* line2 = "", const char* line3 = "", const char* line4 = "");
    void clear();
    
    bool isInitialized() const { return _initialized; }

private:
    LiquidCrystal_I2C* _lcd;
    bool _initialized;
    bool _lastConnectionStatus;
    unsigned long _lastUpdate;
    unsigned long _lastStatusChange;
    String _roomName;
    bool _isPrimaryHub;
    bool _hubConfigChanged;
    
    void _updateConnectionDisplay();
    void _printCentered(uint8_t row, const char* text);
};

#endif // LCD_DISPLAY_H

