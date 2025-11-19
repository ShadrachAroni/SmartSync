# SmartSync Prototype Wiring Guide

This document describes every connection required to reproduce the SmartSync hardware prototype listed in `docs/hardware/hardware.md`. All pin references align with `firmware/SmartSync_ESP32/include/config.h`.

> **Voltage domains:**  
> - Logic: 3.3 V (ESP32 GPIO, DHT22 data, I²C lines)  
> - Sensor power: 5 V (PIR, HC-SR04, DS3231, buzzer if required)  
> - Actuators: 12 V (fan, LED strip)  
> Use a common ground for all rails.

## 1. Power Distribution

| Connection | From | To | Notes |
|------------|------|----|-------|
| 12 V supply + | Barrel jack + | Fan +, LED strip +, buck converter IN+ | Split using terminal block. |
| 12 V supply − | Barrel jack − | Fan − (via MOSFET), LED − (via MOSFET), buck converter IN− | Treat as system ground reference. |
| Buck OUT + (5 V) | Buck converter + | ESP32 VIN, PIR VCC, HC-SR04 VCC, DS3231 VCC, buzzer VCC | Ensure ≥1 A capability. |
| Buck OUT − | Buck converter − | ESP32 GND, sensor grounds, MOSFET source, fan return, LED return | Single-star grounding recommended. |

## 2. Microcontroller Core (ESP32 DevKitC)

| ESP32 Pin | Connects To | Signal | Notes |
|-----------|-------------|--------|-------|
| 3V3 | DHT22 VCC, I²C pull-ups, status LED anode | 3.3 V logic | Limited current; keep loads small. |
| VIN (5 V) | Buck 5 V output | Main supply input | Accepts 5 V from regulator. |
| GND (any) | Common ground | Reference | Tie to every module ground. |

## 3. Sensors

### DHT22 (Temperature & Humidity)

- VCC → ESP32 3V3  
- GND → ESP32 GND  
- DATA → `GPIO27` (`DHT_PIN`)  
- 10 kΩ pull-up resistor between DATA and 3V3 (place close to sensor).

### PIR Motion Sensor (HC-SR501)

- VCC → 5 V rail  
- GND → Common ground  
- OUT → `GPIO25` (`PIR_PIN`)  
- Leave sensitivity/delay pots accessible for tuning.

### Ultrasonic Distance Sensor (HC-SR04)

- VCC → 5 V rail  
- GND → Common ground  
- TRIG → `GPIO32` (`ULTRASONIC_TRIG_PIN`)  
- ECHO → `GPIO33` via resistor divider (e.g., 15 kΩ from ECHO to ESP32, 10 kΩ from ESP32 to ground) to drop 5 V signal to ≈3 V.

### DS3231 RTC (I²C)

- VCC → 5 V rail  
- GND → Common ground  
- SDA → `GPIO21` (`RTC_SDA_PIN`)  
- SCL → `GPIO22` (`RTC_SCL_PIN`)  
- Add shared 4.7 kΩ pull-up resistors from SDA/SCL to 3.3 V (not 5 V) to keep logic-level safe.

## 4. Actuators & Indicators

### Fan (12 V Brushless) via MOSFET

- Fan + → 12 V rail.  
- Fan − → MOSFET drain.  
- MOSFET source → System ground.  
- MOSFET gate → `GPIO26` through 100 Ω resistor (`FAN_PIN`).  
- 100 kΩ resistor gate-to-ground to keep fan off during boot.  
- Flyback diode (1N5819) cathode to 12 V, anode to MOSFET drain.

### LED Strip (12 V) via MOSFET

- LED + → 12 V rail.  
- LED − → MOSFET drain.  
- MOSFET source → System ground.  
- MOSFET gate → `GPIO14` via 100 Ω resistor (`LED_PIN`).  
- 100 kΩ gate pulldown to ground.  
- Optional 100 µF electrolytic capacitor across LED supply to smooth PWM ripple.

> You may use a single dual-channel MOSFET breakout if it supports ≥5 A.

### Active Buzzer

- VCC → 5 V rail (check buzzer spec).  
- GND → Common ground.  
- IN → `GPIO13` (`BUZZER_PIN`).  
- If the buzzer draws >20 mA, use an NPN transistor or MOSFET with 1 kΩ base/gate resistor and flyback diode.

### Status LED

- Anode → `GPIO2` (`STATUS_LED_PIN`) via 330 Ω resistor to 3.3 V.  
- Cathode → Ground.

## 5. BLE/USB Connections

- Micro-USB cable from ESP32 to PC for flashing: carries 5 V (can power the board during development) and UART for logs.  
- If powering via USB while 12 V rail is active, tie grounds together but avoid powering actuators from USB.

## 6. Connector & Harness Recommendations

- Use screw terminals or JST-VH connectors for high-current fan/LED wires.  
- Bundle sensor leads with heat-shrink labels identifying destination pins (e.g., “GPIO27/DHT”).  
- Maintain separation between high-current 12 V lines and low-noise sensor wiring to reduce EMI coupling.

With the above mapping, every pin specified in `config.h` is wired to its corresponding peripheral, enabling the firmware to function without code modifications.

