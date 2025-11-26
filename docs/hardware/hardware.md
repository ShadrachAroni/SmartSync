# SmartSync Prototype Hardware Requirements

This document summarizes the physical components needed to assemble a working SmartSync proof-of-concept based on the current firmware (`firmware/SmartSync_ESP32`) and mobile/BLE architecture. Quantities represent a single-room pilot installation.

**⚠️ IMPORTANT:** This setup uses **TWO SEPARATE POWER SOURCES** (no buck converter required):
- **USB-C cable** powers ESP32 and all sensors/modules (5V)
- **12V adapter** powers ONLY the 12V fan directly

See `docs/hardware/WIRING_DIAGRAM_NO_BUCK.md` for complete wiring instructions.

## Bill of Materials

| # | Item | Qty | Key Specs / Model | Purpose & Notes |
|---|------|-----|------------------|-----------------|
| 1 | ESP32-32U Dev Board | 1 | Dual-core MCU, WiFi + BLE, USB-C | Core controller running SmartSync firmware, handles BLE link to Flutter app. |
| 2 | DHT22 temperature & humidity sensor | 1 | 3.3 V logic, ±0.5 °C | Provides environmental monitoring. **GPIO4** with 10kΩ pull-up. |
| 3 | PIR motion sensor (HC-SR501 or similar) | 1 | 5 V supply, digital OUT | Detects motion/fall events. **GPIO19**. |
| 4 | HY-SRF05 ultrasonic distance sensor | 1 | 5 V supply, 2–400 cm range | Proximity/fall detection. **TRIG: GPIO5, ECHO: GPIO18** (via voltage divider). |
| 5 | DS3231 RTC module | 1 | I²C, battery-backed | Keeps stable time source. **I2C shared with LCD (GPIO21/22)**. |
| 5a | 20×4 Character LCD Display (Yellow/Green) | 1 | I²C backpack, 5V | Shows connection status. **I2C shared with RTC (GPIO21/22)**. |
| 6 | 12 V brushless DC fan | 1 | PWM-controllable | Environmental actuator. **Powered by 12V adapter directly via MOSFET (GPIO13)**. |
| 7 | IRFZ44N MOSFET (or IRF540) | 2 | N-channel, logic-level | Switches 12V fan. **Gate: GPIO13** (with 330Ω + 10kΩ pull-down). |
| 8 | Green LEDs | 3 | 5mm, standard | Ambient lighting. **GPIO25, GPIO32, GPIO33** (each with 330Ω resistor). |
| 9 | RGB LED indicator (common cathode) | 1 | Common cathode | Status indicator. **Red: GPIO14, Green: GPIO27, Blue: GPIO26** (each with 330Ω). |
|10 | Active buzzer module | 1 | 3.3 V–5 V | Audible SOS/alarm feedback. **GPIO23** (optional 330Ω resistor). |
|11 | 330 Ω resistors | 6 | 1/4W | Current limiting for LEDs (3× green LEDs + 3× RGB LED). |
|12 | 10 kΩ resistors | 3 | 1/4W | DHT22 pull-up (1×) + SRF05 voltage divider (2×) + MOSFET pull-down (1×). |
|13 | 12 V DC power adapter | 1 | 12V @ 2A, barrel jack | **Powers ONLY the 12V fan**. Must share ground with ESP32! |
|14 | USB-C cable | 1 | Data-capable | Powers ESP32 and all sensors/modules. Also used for programming. |
|15 | Solderless breadboard | 1 | 830 tie points (full-size) | Prototype wiring base. |
|16 | Dupont jumper wires | 1 set | M–M/M–F/F–F, 22 AWG | Connects modules during prototyping. |
|17 | LM2596S DC-DC Buck Converter | 0 | **NOT USED** | This setup does not require a buck converter. |

## ESP32 Pin Assignments

| GPIO | Component | Notes |
|------|-----------|-------|
| GPIO4 | DHT22 Data | With 10kΩ pull-up to 3.3V |
| GPIO5 | SRF05 Trig | Direct connection |
| GPIO18 | SRF05 Echo | Via voltage divider (2×10kΩ) |
| GPIO19 | PIR Output | Direct connection |
| GPIO21 | I2C SDA | Shared: LCD + RTC |
| GPIO22 | I2C SCL | Shared: LCD + RTC |
| GPIO23 | Active Buzzer | Optional 330Ω resistor |
| GPIO13 | MOSFET Gate (Fan) | With 330Ω + 10kΩ pull-down |
| GPIO14 | RGB Red | With 330Ω resistor |
| GPIO26 | RGB Blue | With 330Ω resistor |
| GPIO27 | RGB Green | With 330Ω resistor |
| GPIO25 | Green LED 1 | With 330Ω resistor |
| GPIO32 | Green LED 2 | With 330Ω resistor |
| GPIO33 | Green LED 3 | With 330Ω resistor |

## Integration Notes

- **Power Setup:** Two separate power sources:
  - **USB-C (5V)**: Powers ESP32, all sensors, LCD, RTC, buzzer, LEDs
  - **12V Adapter**: Powers ONLY the 12V fan (via MOSFET)
  - **CRITICAL**: 12V adapter negative MUST connect to breadboard ground rail (common ground)
- **Level shifting:** The HY-SRF05 echo pin outputs 5V. Use a voltage divider (2×10kΩ resistors) to protect ESP32 GPIO18.
- **LED Control:** All 3 green LEDs are controlled together via PWM (GPIO25, GPIO32, GPIO33). They use common cathode configuration (LOW = ON).
- **RGB LED:** Common anode configuration. PWM is inverted (LOW = ON, HIGH = OFF).
- **Fan Control:** Fan is powered directly from 12V adapter. MOSFET (IRFZ44N) gate is controlled by GPIO13 with PWM. Requires 10kΩ pull-down resistor to keep fan OFF during boot.
- **Power Limitations:** USB-C typically provides 500mA-1A. Ensure total current draw doesn't exceed USB port limits. Use powered USB hub if needed.
- **Prototype vs. production:** The list focuses on a bench-ready build. For field pilots, replace breadboards with a custom PCB and ensure proper power distribution.

## Wiring Reference

See `docs/hardware/WIRING_DIAGRAM_NO_BUCK.md` for complete step-by-step wiring instructions with wire types (M-M, F-M, F-F) for each connection.

Refer to `docs/hardware/bom.xlsx` if you need vendor-specific part numbers or aggregated pricing before procurement.
