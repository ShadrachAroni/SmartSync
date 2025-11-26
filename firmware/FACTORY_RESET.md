# Factory Reset Guide

## Overview
The SmartSync firmware includes a factory reset function that clears all stored configuration and returns the device to default settings.

## What Gets Reset

### Stored Preferences (Cleared):
- Fan speed setting
- LED brightness setting
- Auto mode state
- Security enabled state
- Schedules
- Room name
- Primary hub status
- Device ID (if stored)
- Device PIN (if stored)

### Runtime State (Reset to Defaults):
- Fan speed: 0 (off)
- LED brightness: 0 (off)
- Auto mode: Disabled
- Security: Disarmed
- All schedules: Cleared
- Sensor data: Reset
- Room name: Empty
- Primary hub status: False

## Methods to Reset

### Method 1: Serial Command (Recommended)

1. Connect to the ESP32 via Serial Monitor (115200 baud)
2. Type: `RESET` or `FACTORY_RESET` or `CLEAR`
3. Within 5 seconds, type: `RESET CONFIRM` or `CONFIRM`
4. The device will:
   - Clear all preferences
   - Reset all state variables
   - Flash status LED 5 times
   - Restart automatically after 3 seconds

**Example:**
```
> RESET
Factory reset requested. This will clear all stored settings.
Type 'RESET CONFIRM' within 5 seconds to proceed...
> RESET CONFIRM
========================================
FACTORY RESET IN PROGRESS...
========================================
✓ Preferences cleared successfully
========================================
FACTORY RESET COMPLETE
All settings have been cleared.
Device will restart in 3 seconds...
========================================
```

### Method 2: BLE Command

Send a BLE command with:
```json
{
  "cmd": "FACTORY_RESET",
  "value": {
    "confirm": true
  }
}
```

**Note:** The `confirm` field must be set to `true` for the reset to proceed.

## Safety Features

1. **Confirmation Required:** Both methods require explicit confirmation to prevent accidental resets
2. **Visual Feedback:** Status LED flashes 5 times during reset
3. **Automatic Restart:** Device restarts automatically after reset to ensure clean state
4. **Safe Shutdown:** All outputs (fan, LEDs, buzzer) are turned off before reset

## After Reset

After factory reset:
- Device will restart with default settings
- BLE advertising will resume
- All sensors will start reading from scratch
- Device will need to be re-registered in the mobile app
- Room assignment will need to be reconfigured

## Use Cases

- **Development/Testing:** Clean slate for testing
- **Troubleshooting:** Reset corrupted configuration
- **Device Transfer:** Clear previous owner's settings
- **Configuration Issues:** Start fresh when settings cause problems

## Notes

- Factory reset does NOT affect:
  - Firmware version
  - Hardware configuration
  - Pin assignments
  - Sensor calibration (if any)
  
- The reset is immediate and cannot be undone
- Make sure to save any important configuration before resetting

