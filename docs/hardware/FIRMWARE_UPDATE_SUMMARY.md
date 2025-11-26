# Firmware Update Summary - Wiring Diagram Alignment

## Overview
The firmware and app code have been updated to match the new wiring diagram that uses **two separate power sources** (USB-C for ESP32/sensors, 12V adapter for fan only) **without a buck converter**.

## Changes Made

### 1. Pin Assignments Updated (`firmware/SmartSync_ESP32/include/config.h`)

| Component | Old Pin | New Pin | Notes |
|-----------|--------|---------|-------|
| DHT22 Data | GPIO27 | **GPIO4** | With 10kΩ pull-up to 3.3V |
| PIR Output | GPIO25 | **GPIO19** | Direct connection |
| SRF05 Trig | GPIO32 | **GPIO5** | Direct connection |
| SRF05 Echo | GPIO33 | **GPIO18** | Via voltage divider (2×10kΩ) |
| Fan (MOSFET Gate) | GPIO26 | **GPIO13** | With 330Ω + 10kΩ pull-down |
| RGB Red | GPIO4 | **GPIO14** | With 330Ω resistor |
| RGB Green | GPIO16 | **GPIO27** | With 330Ω resistor |
| RGB Blue | GPIO17 | **GPIO26** | With 330Ω resistor |
| Buzzer | GPIO13 | **GPIO23** | Optional 330Ω resistor |
| Green LED 1 | GPIO14 (LED_PIN) | **GPIO25** | With 330Ω resistor |
| Green LED 2 | N/A | **GPIO32** | With 330Ω resistor (new) |
| Green LED 3 | N/A | **GPIO33** | With 330Ω resistor (new) |

**Unchanged:**
- I2C SDA/SCL: GPIO21/GPIO22 (LCD + RTC)
- Status LED: GPIO2 (built-in)

### 2. PWM Channel Assignments

| Component | Channel | Notes |
|-----------|---------|-------|
| Fan | 0 | PWM via MOSFET |
| Green LED 1 | 1 | All 3 green LEDs controlled together |
| Green LED 2 | 2 | |
| Green LED 3 | 3 | |
| RGB Red | 4 | Common anode (inverted logic) |
| RGB Green | 5 | |
| RGB Blue | 6 | |

### 3. Code Changes (`firmware/SmartSync_ESP32/src/main.cpp`)

#### Updated Functions:

1. **`setupPins()`**
   - Removed single `LED_PIN` setup
   - Added setup for 3 separate green LED pins (GPIO25, GPIO32, GPIO33)
   - All initialized to HIGH (OFF) for common cathode configuration

2. **`setupPWM()`**
   - Removed single LED PWM channel setup
   - Added PWM setup for all 3 green LEDs (channels 1, 2, 3)
   - All initialized to 255 (OFF) for inverted logic

3. **`setLEDBrightness()`**
   - Updated to control all 3 green LEDs simultaneously
   - Uses inverted brightness logic (255 - brightness) for common cathode LEDs
   - When brightness = 0 → LEDs OFF (write 255)
   - When brightness = 255 → LEDs ON full (write 0)

### 4. Hardware Documentation Updated

- **`docs/hardware/hardware.md`**: Updated BOM and pin assignments table
- **`docs/hardware/WIRING_DIAGRAM_NO_BUCK.md`**: Already contains correct wiring (reference document)

## Power Supply Configuration

### Two Separate Power Sources:

1. **USB-C Cable (5V)**
   - Powers: ESP32, all sensors, LCD, RTC, buzzer, LEDs
   - Connected to ESP32 USB-C port
   - Provides regulated 5V power

2. **12V Adapter (12V)**
   - Powers: **ONLY the 12V fan** (via MOSFET)
   - Fan red wire → 12V adapter positive
   - Fan black wire → MOSFET Drain
   - **CRITICAL**: 12V adapter negative → Breadboard ground rail (common ground)

### Why This Works:

- ESP32 and sensors get clean, regulated power from USB
- Fan gets proper 12V directly from adapter
- Common ground ensures MOSFET can switch properly
- No buck converter needed (simpler, safer for beginners)

## LED Control Logic

### Green LEDs (3×, Common Cathode):
- **Configuration**: Anode → 5V rail via 330Ω, Cathode → GPIO pin
- **Logic**: LOW = ON, HIGH = OFF
- **PWM**: Inverted (write 255 for OFF, 0 for ON)
- **Control**: All 3 LEDs controlled together via `setLEDBrightness()`

### RGB LED (Common Anode):
- **Configuration**: Anode → 5V rail via 330Ω, Cathodes → GPIO pins via 330Ω
- **Logic**: LOW = ON, HIGH = OFF (inverted in RGBStatusLED class)
- **PWM**: Inverted (already handled in `RGBStatusLED::_applyColor()`)

## Testing Checklist

Before deploying firmware, verify:

- [ ] All pin assignments match wiring diagram
- [ ] DHT22 on GPIO4 with pull-up resistor
- [ ] PIR on GPIO19
- [ ] Ultrasonic TRIG on GPIO5, ECHO on GPIO18 (with voltage divider)
- [ ] Fan MOSFET gate on GPIO13 (with pull-down resistor)
- [ ] RGB LED on GPIO14, GPIO27, GPIO26
- [ ] Green LEDs on GPIO25, GPIO32, GPIO33
- [ ] Buzzer on GPIO23
- [ ] I2C devices (LCD + RTC) on GPIO21/22
- [ ] 12V adapter ground connected to breadboard ground
- [ ] All LEDs have 330Ω current-limiting resistors
- [ ] Voltage divider in place for ultrasonic ECHO pin

## Backward Compatibility

⚠️ **BREAKING CHANGES**: This firmware update is **NOT backward compatible** with the previous wiring setup. If you have an existing device wired with the old pin assignments, you must either:
1. Rewire the device to match the new wiring diagram, OR
2. Revert to the previous firmware version

## App Code

✅ **No changes required**: The Flutter app communicates via BLE and doesn't need to know about hardware pin assignments. All communication is abstracted through the BLE service.

## Next Steps

1. Review the wiring diagram: `docs/hardware/WIRING_DIAGRAM_NO_BUCK.md`
2. Assemble hardware according to the diagram
3. Flash the updated firmware to ESP32
4. Test each component individually before full system test
5. Verify BLE communication with the Flutter app

## Files Modified

- `firmware/SmartSync_ESP32/include/config.h`
- `firmware/SmartSync_ESP32/src/main.cpp`
- `docs/hardware/hardware.md`

## Files Unchanged (No Action Needed)

- App code (Flutter) - communicates via BLE abstraction
- BLE service code - no pin dependencies
- Sensor drivers - use pin definitions from config.h
- Actuator drivers - use pin definitions from config.h

