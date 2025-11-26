#include "LCDDisplay.h"
#include "../../include/config.h"

// Forward declaration for debug macros if not available
#ifndef DEBUG_PRINTLN
#define DEBUG_PRINTLN(x) Serial.println(x)
#define DEBUG_PRINT(x) Serial.print(x)
#define DEBUG_PRINTF(x, ...) Serial.printf(x, __VA_ARGS__)
#endif

LCDDisplay::LCDDisplay() 
    : _lcd(nullptr), 
      _initialized(false),
      _lastConnectionStatus(false),
      _lastUpdate(0),
      _lastStatusChange(0),
      _roomName(""),
      _isPrimaryHub(false),
      _hubConfigChanged(false) {
}

LCDDisplay::~LCDDisplay() {
    if (_lcd != nullptr) {
        delete _lcd;
    }
}

bool LCDDisplay::begin(uint8_t address, uint8_t cols, uint8_t rows) {
    DEBUG_PRINTLN("Initializing LCD Display...");
    
    try {
        _lcd = new LiquidCrystal_I2C(address, cols, rows);
        
        // Initialize LCD
        _lcd->init();
        _lcd->backlight();
        
        // Test display
        _lcd->setCursor(0, 0);
        _lcd->print("SmartSync v");
        _lcd->print(FIRMWARE_VERSION);
        delay(1000);
        
        _lcd->clear();
        _initialized = true;
        showWelcome();
        
        _lastConnectionStatus = false;
        _lastStatusChange = millis();
        _lastUpdate = millis();
        
        DEBUG_PRINTLN("LCD Display initialized successfully");
        return true;
    } catch (...) {
        DEBUG_PRINTLN("LCD Display initialization failed");
        _initialized = false;
        return false;
    }
}

void LCDDisplay::update() {
    if (!_initialized || _lcd == nullptr) return;
    
    unsigned long currentMillis = millis();
    
    // Update connection status display every 500ms
    if (currentMillis - _lastUpdate >= 500) {
        _updateConnectionDisplay();
        _lastUpdate = currentMillis;
    }
}

void LCDDisplay::setConnectionStatus(bool connected) {
    if (!_initialized) return;
    
    if (connected != _lastConnectionStatus) {
        _lastConnectionStatus = connected;
        _lastStatusChange = millis();
        _updateConnectionDisplay();
    }
}

void LCDDisplay::setRoomName(const char* roomName) {
    if (!_initialized) return;
    String newRoomName = roomName ? String(roomName) : String("");
    if (newRoomName != _roomName) {
        _roomName = newRoomName;
        _hubConfigChanged = true;
        _updateConnectionDisplay();
    }
}

void LCDDisplay::setIsPrimaryHub(bool isPrimary) {
    if (!_initialized) return;
    if (isPrimary != _isPrimaryHub) {
        _isPrimaryHub = isPrimary;
        _hubConfigChanged = true;
        _updateConnectionDisplay();
    }
}

void LCDDisplay::_updateConnectionDisplay() {
    if (!_initialized || _lcd == nullptr) return;
    
    // Line 1: Hub Type (Primary Hub or Room Name)
    _lcd->setCursor(0, 0);
    if (_isPrimaryHub) {
        _lcd->print("*** MAIN HUB ***   ");
    } else if (_roomName.length() > 0) {
        // Show room name, truncate if too long
        String displayText = "Room: " + _roomName;
        if (displayText.length() > 20) {
            displayText = displayText.substring(0, 17) + "...";
        }
        _lcd->print(displayText);
        // Pad with spaces if needed
        for (int i = displayText.length(); i < 20; i++) {
            _lcd->print(" ");
        }
    } else {
        _lcd->print("SmartSync Hub      ");
    }
    
    // Line 2: Connection Status
    _lcd->setCursor(0, 1);
    if (_lastConnectionStatus) {
        _lcd->print("BT: CONNECTED      ");
    } else {
        _lcd->print("BT: DISCONNECTED   ");
    }
    
    // Line 3: Connection indicator
    _lcd->setCursor(0, 2);
    if (_lastConnectionStatus) {
        _lcd->print("[=====] Connected  ");
    } else {
        // Show disconnected state clearly
        _lcd->print("[-----] Disconnected");
    }
    
    // Line 4: Additional info
    _lcd->setCursor(0, 3);
    if (_lastConnectionStatus) {
        _lcd->print("Ready for commands ");
    } else {
        // Show that we're waiting for reconnection
        unsigned long elapsed = millis() - _lastStatusChange;
        int dotCount = (elapsed / 500) % 4;
        _lcd->print("Waiting");
        for (int i = 0; i < dotCount; i++) {
            _lcd->print(".");
        }
        for (int i = dotCount; i < 4; i++) {
            _lcd->print(" ");
        }
        _lcd->print("        ");
    }
}

void LCDDisplay::showWelcome() {
    if (!_initialized || _lcd == nullptr) return;
    
    _lcd->clear();
    _lcd->setCursor(0, 0);
    _lcd->print("   SmartSync Hub   ");
    _lcd->setCursor(0, 1);
    _lcd->print("  Firmware v");
    _lcd->print(FIRMWARE_VERSION);
    _lcd->print("   ");
    _lcd->setCursor(0, 2);
    _lcd->print(" Initializing...   ");
    _lcd->setCursor(0, 3);
    _lcd->print("  Please wait...   ");
}

void LCDDisplay::showStatus(const char* line1, const char* line2, const char* line3, const char* line4) {
    if (!_initialized || _lcd == nullptr) return;
    
    _lcd->clear();
    
    if (line1 != nullptr && strlen(line1) > 0) {
        _lcd->setCursor(0, 0);
        _lcd->print(line1);
    }
    if (line2 != nullptr && strlen(line2) > 0) {
        _lcd->setCursor(0, 1);
        _lcd->print(line2);
    }
    if (line3 != nullptr && strlen(line3) > 0) {
        _lcd->setCursor(0, 2);
        _lcd->print(line3);
    }
    if (line4 != nullptr && strlen(line4) > 0) {
        _lcd->setCursor(0, 3);
        _lcd->print(line4);
    }
}

void LCDDisplay::clear() {
    if (!_initialized || _lcd == nullptr) return;
    _lcd->clear();
}

void LCDDisplay::_printCentered(uint8_t row, const char* text) {
    if (!_initialized || _lcd == nullptr) return;
    
    int len = strlen(text);
    int startPos = (20 - len) / 2;
    if (startPos < 0) startPos = 0;
    
    _lcd->setCursor(startPos, row);
    _lcd->print(text);
}

