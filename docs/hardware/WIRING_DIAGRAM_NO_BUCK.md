# SmartSync Wiring Diagram (Without Buck Converter)

## ⚡ Power Supply Setup - TWO SEPARATE SOURCES

### Source 1: USB-C Cable (5V)
- Powers: ESP32, all sensors, LCD, RTC, buzzer, LEDs
- Connect: USB-C cable → ESP32 USB-C port

### Source 2: 12V Adapter (12V)
- Powers: ONLY the 12V fan
- Connect: 12V adapter → Fan directly (via MOSFET)

### ⚠️ CRITICAL: Common Ground
- **12V adapter negative** → Connect to **breadboard ground rail** using F-F wire
- This ensures both power sources share the same ground reference
- Without this, the MOSFET won't work properly!

---

## 🔌 Breadboard Power Rails Setup

### Left Side Rails:
- **Red rail (+)**: Connect ESP32 `5V` pin → Left red rail using **M-M wire**
- **Blue rail (-)**: This is your **GROUND** rail

### Right Side Rails:
- **Red rail (+)**: Connect ESP32 `3.3V` pin → Right red rail using **M-M wire**
- **Blue rail (-)**: Connect to left blue rail using **M-M wire** (common ground)

### Ground Connection:
- Connect **left ground rail** to **right ground rail** using **M-M wire**
- Connect **ESP32 GND pin** to ground rail using **M-M wire**
- Connect **12V adapter negative** to ground rail using **F-F wire** (or F-M if adapter has a wire)

---

## 📋 Component-by-Component Wiring

### 1. ESP32-32U
**Using M-M wires:**
- `5V` pin → Left red rail (5V power rail)
- `3.3V` pin → Right red rail (3.3V power rail)
- `GND` pin → Ground rail (either left or right, they're connected)
- USB-C cable → Plug into ESP32 (provides 5V power)

---

### 2. 20×4 LCD with I2C Adapter (16-pin module)
**The adapter simplifies wiring from 16 pins to just 4!**

**Using F-M wires** (if adapter has male pins) or **M-M wires** (if adapter is on breadboard):
- `VCC` → Left red rail (5V)
- `GND` → Ground rail
- `SDA` → ESP32 `GPIO21`
- `SCL` → ESP32 `GPIO22`

**Note:** The adapter has a small blue potentiometer on it - you can adjust LCD contrast with a small screwdriver if needed.

---

### 3. DHT22 Temperature/Humidity Sensor
**Using M-M wires:**
- `VCC` → Right red rail (3.3V) - DHT22 works perfectly with 3.3V
- `GND` → Ground rail
- `DAT` → ESP32 `GPIO4`
- **Add 10kΩ resistor**: Connect between `DAT` pin and 3.3V rail (pull-up resistor)

---

### 4. HY-SRF05 Ultrasonic Sensor
**Using F-M wires** (sensor has male header pins):
- `VCC` → Left red rail (5V) - Needs 5V for proper operation
- `GND` → Ground rail
- `TRIG` → ESP32 `GPIO5`
- `ECHO` → **Voltage divider circuit** → ESP32 `GPIO18`

**Voltage Divider Setup (IMPORTANT!):**
- The ECHO pin outputs 5V, but ESP32 GPIO pins are 3.3V tolerant
- Use **two 10kΩ resistors** in series:
  - Connect ECHO pin to top of first 10kΩ resistor
  - Connect junction between the two resistors to ESP32 `GPIO18`
  - Connect bottom of second 10kΩ resistor to ground rail
- This reduces 5V signal to ~2.5V (safe for ESP32)

---

### 5. PIR Motion Sensor
**Using F-M wires** (sensor has male pins):
- `VCC` → Left red rail (5V)
- `GND` → Ground rail
- `OUT` → ESP32 `GPIO19`

---

### 6. DS3231 RTC Module
**Using F-M wires** (module has male pins):
- `VCC` → Left red rail (5V)
- `GND` → Ground rail
- `SDA` → ESP32 `GPIO21` (shared with LCD - I2C bus allows multiple devices)
- `SCL` → ESP32 `GPIO22` (shared with LCD)

**Note:** Make sure the coin cell battery is installed in the RTC module for timekeeping when power is off.

---

### 7. Active Buzzer
**Using M-M wires:**
- **Positive pin** (usually marked with +) → ESP32 `GPIO23`
- **Negative pin** (usually marked with -) → Ground rail
- **Optional:** Add **330Ω resistor** in series between GPIO23 and buzzer positive pin if you want to limit current

---

### 8. RGB LED (Common Anode)
**Using M-M wires:**
- **Anode** (longest pin or common pin) → Left red rail (5V) via **330Ω resistor**
- **Red cathode** → ESP32 `GPIO14` via **330Ω resistor**
- **Green cathode** → ESP32 `GPIO27` via **330Ω resistor**
- **Blue cathode** → ESP32 `GPIO26` via **330Ω resistor**

**How it works:** Common anode means the LED is ON when you set the GPIO pin LOW (0V), and OFF when you set it HIGH (3.3V).

---

### 9. Three Green LEDs
**Using M-M wires** (each LED separately):
- **LED 1**: 
  - Anode → 5V rail via **330Ω resistor**
  - Cathode → ESP32 `GPIO25`
- **LED 2**: 
  - Anode → 5V rail via **330Ω resistor**
  - Cathode → ESP32 `GPIO32`
- **LED 3**: 
  - Anode → 5V rail via **330Ω resistor**
  - Cathode → ESP32 `GPIO33`

**How it works:** LED turns ON when GPIO pin is LOW (sinks current), OFF when GPIO pin is HIGH.

---

### 10. 12V Fan + MOSFET (IRFZ44N) - ⚠️ SPECIAL WIRING

**This is the ONLY component using 12V adapter directly!**

#### Fan Connections:
- **Fan red wire** → **12V adapter positive** (use F-F wire or direct connection)
- **Fan black wire** → **MOSFET Drain pin** (use F-M wire if needed)

#### MOSFET Connections (IRFZ44N):
- **Gate** → ESP32 `GPIO13` via **330Ω resistor** (or use 100Ω if you have one)
- **Source** → **Ground rail** (common ground with ESP32)
- **Drain** → **Fan black wire**
- **Add 10kΩ resistor** from Gate to Ground (pull-down resistor - keeps MOSFET OFF during ESP32 boot)

#### 12V Adapter Ground Connection:
- **12V adapter negative** → **Ground rail** using **F-F wire** or **F-M wire**
- This is CRITICAL - both power sources must share the same ground!

**How it works:** When ESP32 sets GPIO13 HIGH, MOSFET turns ON, completing the circuit and fan spins.

---

## 📊 ESP32 Pin Assignment Summary

| GPIO Pin | Component | Wire Type | Notes |
|----------|-----------|-----------|-------|
| GPIO4 | DHT22 Data | M-M | With 10kΩ pull-up to 3.3V |
| GPIO5 | SRF05 Trig | F-M | Direct connection |
| GPIO18 | SRF05 Echo | F-M | Via voltage divider (2×10kΩ) |
| GPIO19 | PIR Output | F-M | Direct connection |
| GPIO21 | I2C SDA | F-M | Shared: LCD + RTC |
| GPIO22 | I2C SCL | F-M | Shared: LCD + RTC |
| GPIO23 | Active Buzzer | M-M | Optional 330Ω resistor |
| GPIO13 | MOSFET Gate (Fan) | M-M | With 330Ω + 10kΩ pull-down |
| GPIO14 | RGB Red | M-M | With 330Ω resistor |
| GPIO26 | RGB Blue | M-M | With 330Ω resistor |
| GPIO27 | RGB Green | M-M | With 330Ω resistor |
| GPIO25 | Green LED 1 | M-M | With 330Ω resistor |
| GPIO32 | Green LED 2 | M-M | With 330Ω resistor |
| GPIO33 | Green LED 3 | M-M | With 330Ω resistor |
| 5V | Power rail (5V) | M-M | From USB |
| 3.3V | Power rail (3.3V) | M-M | From ESP32 |
| GND | Ground rail | M-M | Common ground |

---

## 🔌 Wire Type Guide

### M-M (Male-to-Male) Wires:
- Use for: ESP32 pins → breadboard, breadboard-to-breadboard connections, component-to-breadboard
- Examples: ESP32 GPIO pins, power rails, ground connections, resistors

### F-M (Female-to-Male) Wires:
- Use for: Connecting sensors/modules with male pins to breadboard
- Examples: DHT22, PIR, Ultrasonic, RTC, LCD adapter (if it has male pins)

### F-F (Female-to-Female) Wires:
- Use for: Extending wires, connecting 12V adapter to fan, connecting adapter ground to breadboard
- Examples: 12V adapter connections, long-distance connections

---

## ⚠️ Important Safety & Functionality Notes

### 1. Common Ground is CRITICAL
- Both USB power (ESP32) and 12V adapter **MUST** share the same ground
- Connect 12V adapter negative to breadboard ground rail
- Without this, the MOSFET won't work and you risk damaging components

### 2. Power Limitations
- USB-C typically provides 5V @ 500mA-1A
- Make sure total current draw doesn't exceed USB port limits
- If you experience issues, use a powered USB hub or USB wall adapter

### 3. Voltage Divider for Ultrasonic
- The SRF05 echo pin outputs 5V, but ESP32 GPIO pins are 3.3V tolerant
- The voltage divider (2×10kΩ resistors) protects the ESP32 from damage
- **DO NOT skip this!**

### 4. MOSFET Gate Protection
- The 10kΩ pull-down resistor on MOSFET gate prevents accidental turn-on during ESP32 boot/reset
- This keeps the fan OFF when ESP32 is starting up

### 5. LED Current Limiting
- Always use 330Ω resistors with LEDs
- Prevents damage to both LEDs and ESP32 GPIO pins
- Without resistors, LEDs will burn out or damage the ESP32

### 6. I2C Bus Sharing
- LCD and RTC share the same I2C bus (SDA/SCL)
- They have different I2C addresses (LCD usually 0x27, RTC is 0x68)
- This is normal and works fine!

---

## ✅ Testing Checklist

1. ✅ Connect ESP32 via USB-C, verify red LED lights up on board
2. ✅ Check all ground connections are common (use multimeter if available)
3. ✅ Verify 5V rail has power (test with multimeter or LED)
4. ✅ Test each sensor individually before connecting all at once
5. ✅ Verify 12V adapter ground is connected to breadboard ground
6. ✅ Test fan MOSFET with low duty cycle PWM first (start slow!)
7. ✅ Check I2C devices (LCD and RTC) are detected

---

## 🎯 Advantages of This Approach (No Buck Converter)

✅ **Simpler Setup**: No buck converter to configure or adjust  
✅ **Safer**: Less risk of overvoltage issues  
✅ **More Reliable**: USB power is well-regulated  
✅ **Easier Debugging**: Clear separation of power domains  
✅ **Lower Cost**: One less component to buy  

## ⚠️ Limitations

⚠️ **Requires USB Connection**: ESP32 must stay connected to USB for power  
⚠️ **Power Limited**: USB port current limits (typically 500mA-1A)  
⚠️ **Two Power Sources**: Need to manage two separate power supplies  
⚠️ **Not Portable**: Can't run standalone without USB connection  

---

## 🔧 Troubleshooting Tips

1. **Fan not working?**
   - Check 12V adapter is connected
   - Verify 12V adapter ground is connected to breadboard ground
   - Check MOSFET gate has 10kΩ pull-down resistor
   - Test MOSFET gate with multimeter (should see 0V when GPIO is LOW, 3.3V when HIGH)

2. **Sensors not responding?**
   - Check power connections (5V or 3.3V as specified)
   - Verify ground connections
   - Check I2C devices with I2C scanner code

3. **ESP32 not powering on?**
   - Check USB-C cable is data-capable (not charge-only)
   - Try different USB port
   - Check USB port provides enough power

4. **LCD not displaying?**
   - Adjust contrast potentiometer on I2C adapter
   - Check I2C address (usually 0x27)
   - Verify SDA/SCL connections

---

## 📝 Final Notes

This wiring setup is **simpler and safer** than using a buck converter, especially for beginners. The main trade-off is that you need to keep the USB-C cable connected for power. If you need a standalone system later, you can always add the buck converter back in.

**Remember:** Always double-check your connections before powering on, especially the ground connections between the two power sources!
