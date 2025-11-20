# SmartSync Prototype Hardware Requirements

This document summarizes the physical components needed to assemble a working SmartSync proof-of-concept based on the current firmware (`firmware/SmartSync_ESP32`) and mobile/BLE architecture. Quantities represent a single-room pilot installation.

## Bill of Materials

| # | Item | Qty | Key Specs / Model | Purpose & Notes |
|---|------|-----|------------------|-----------------|
| 1 | ESP32 DevKitC / NodeMCU-32S | 1 | Dual-core MCU, WiFi + BLE | Core controller running SmartSync firmware, handles BLE link to Flutter app. |
| 2 | DHT22 temperature & humidity sensor | 1 | 3.3 V logic, ±0.5 °C | Provides environmental monitoring for automation and caregiver dashboards. |
| 3 | PIR motion sensor (HC-SR501 or similar) | 1 | 5 V supply, digital OUT | Detects motion/fall events used by security and activity tracking logic. |
| 4 | HC-SR04 ultrasonic distance sensor | 1 | 5 V supply, 2–400 cm range | Proximity/fall detection and occupancy analytics. |
| 5 | DS3231 RTC module | 1 | I²C, battery-backed | Keeps stable time source for on-device schedules even if BLE link drops. |
| 5a | 20×4 Character LCD Display (Yellow/Green) | 1 | I²C backpack, 5V | Shows connection status (Connected/Pending) and system information. |
| 6 | 12 V brushless DC fan (120 mm or similar) | 1 | PWM-controllable | Environmental actuator driven by `FanController` via PWM. |
| 7 | Logic-level N-channel MOSFET + flyback diode | 1 | 30 V / ≥10 A, e.g., IRLZ44N + 1N5819 | Switches the 12 V fan from the ESP32's 3.3 V PWM output safely. |
| 8 | 12 V LED strip segment (e.g., 30 cm warm white) | 1 | 12 V @ ≤1 A | Ambient/safety lighting managed via LED PWM channel. |
| 9 | Logic-level MOSFET driver for LED strip | 1 | e.g., AO3400A breakout | Lets the ESP32 dim the LED strip without overloading GPIO. |
|10 | Active buzzer module | 1 | 3.3 V–5 V | Provides audible SOS/alarm feedback triggered by `AlarmSystem`. |
|11 | Status RGB/white indicator LED + 330 Ω resistor | 1 | 3.3 V compatible | Mirrors system states for quick visual diagnostics (optional but recommended). |
|12 | 12 V DC power adapter | 1 | ≥2 A, barrel jack | Primary supply rail for fan/LED. |
|13 | Buck converter (step-down) | 1 | 12 V → 5 V/3 A (e.g., MP1584) | Powers ESP32 and sensors off the 12 V rail. |
|14 | USB-A to micro-USB cable | 1 | Data-capable | Firmware flashing, serial debugging, and USB power when bench testing. |
|15 | Solderless breadboard or protoboard | 1 | 400+ tie points | Quick assembly of the prototype wiring harness. |
|16 | Dupont jumper wires (M–M/M–F/F–F) | 30 | 22 AWG mixed lengths | Connects modules during prototyping; include color-coded sets. |
|17 | Screw terminal blocks / JST-VH connectors | 4 | 2-pin | Secure fan/LED/power connections, reduce accidental disconnects. |

## Integration Notes

- **Power budgeting:** With the fan and LED at full load, expect ≈1.5 A on the 12 V rail. Leave ≥25 % headroom in the adapter spec and ensure the buck converter can deliver a clean 5 V/1 A for the ESP32 plus sensors.
- **Level shifting:** The HC-SR04 echo line outputs 5 V. Use a simple resistor divider (1 × 10 kΩ + 1 × 15 kΩ) or a logic-level shifter to protect the ESP32 GPIO.
- **EMI & safety:** Keep fan/LED high-current traces short and twisted where possible. Add a 100 µF electrolytic capacitor across the 12 V rail near the MOSFETs to smooth surges.
- **Prototype vs. production:** The list focuses on a bench-ready build. For field pilots, replace breadboards with a custom PCB (see `docs/hardware/pcb-design.kicad`) and swap discrete MOSFETs with dedicated low-side driver modules for robustness.

Refer to `docs/hardware/bom.xlsx` if you need vendor-specific part numbers or aggregated pricing before procurement.
