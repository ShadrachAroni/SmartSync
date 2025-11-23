# SmartSync Prototype Wiring Guide - Complete Detailed Instructions

This document provides **exhaustive, step-by-step wiring instructions** for assembling the SmartSync hardware prototype. Every connection, wire type, pin number, and component placement is specified in detail. All pin references align with `firmware/SmartSync_ESP32/include/config.h`.

> **⚠️ Safety First:**  
> - Always disconnect power before making connections
> - Double-check all connections before applying power
> - Use appropriate wire gauges for current ratings
> - Verify voltage levels before connecting to ESP32 GPIO pins

---

## Table of Contents

1. [Power Distribution System](#1-power-distribution-system)
2. [ESP32 DevKitC Pinout & Connections](#2-esp32-devkitc-pinout--connections)
3. [Sensor Wiring - Complete Details](#3-sensor-wiring---complete-details)
4. [Actuator Wiring - Complete Details](#4-actuator-wiring---complete-details)
5. [Indicator & Status Components](#5-indicator--status-components)
6. [I²C Bus Wiring](#6-i²c-bus-wiring)
7. [Wire Specifications & Recommendations](#7-wire-specifications--recommendations)
8. [Connector Specifications](#8-connector-specifications)
9. [Step-by-Step Assembly Sequence](#9-step-by-step-assembly-sequence)
10. [Verification & Testing](#10-verification--testing)

---

## 1. Power Distribution System

### 1.1 Primary 12V Power Supply

**Component:** 12V DC Power Adapter (Barrel Jack, ≥2A)

| Connection Point | Wire Type | Wire Gauge | Color | Destination | Notes |
|----------------|-----------|------------|-------|-------------|-------|
| Barrel Jack **Center Pin (+)** | Stranded copper | 18 AWG | **Red** | Terminal Block #1 (Input) | Positive rail |
| Barrel Jack **Outer Sleeve (-)** | Stranded copper | 18 AWG | **Black** | Common Ground Bus | System ground reference |

**Terminal Block #1 (12V Distribution):**
- **Input:** Barrel jack center pin (+) via **Red 18 AWG wire**
- **Output 1:** Buck converter IN+ terminal via **Red 18 AWG wire** (12-15 cm length)
- **Output 2:** Fan positive terminal via **Red 18 AWG wire** (20-30 cm length)
- **Output 3:** LED strip positive terminal via **Red 18 AWG wire** (20-30 cm length)

**Common Ground Bus (Star Ground Point):**
- **Input:** Barrel jack outer sleeve (-) via **Black 18 AWG wire**
- **Outputs:** Connect to all component grounds (see individual sections)

### 1.2 Buck Converter (12V → 5V)

**Component:** MP1584 or similar step-down converter (12V IN, 5V OUT, ≥3A)

**Input Connections:**
- **IN+ Terminal:** Connect to Terminal Block #1 Output 1 via **Red 18 AWG wire** (12-15 cm)
- **IN- Terminal:** Connect to Common Ground Bus via **Black 18 AWG wire** (12-15 cm)

**Output Connections (5V Rail):**
- **OUT+ Terminal:** Connect to Terminal Block #2 (5V Distribution) via **Red 20 AWG wire** (10-12 cm)
- **OUT- Terminal:** Connect to Common Ground Bus via **Black 20 AWG wire** (10-12 cm)

**Terminal Block #2 (5V Distribution):**
- **Input:** Buck converter OUT+ via **Red 20 AWG wire**
- **Output 1:** ESP32 VIN pin via **Red 22 AWG wire** (8-10 cm)
- **Output 2:** PIR sensor VCC pin via **Red 22 AWG wire** (15-20 cm)
- **Output 3:** HC-SR04 VCC pin via **Red 22 AWG wire** (15-20 cm)
- **Output 4:** DS3231 RTC VCC pin via **Red 22 AWG wire** (10-15 cm)
- **Output 5:** LCD I²C backpack VCC pin via **Red 22 AWG wire** (10-15 cm)
- **Output 6:** Active buzzer VCC pin via **Red 22 AWG wire** (10-15 cm)

**3.3V Rail (ESP32 Internal Regulator):**
- **ESP32 3V3 Pin:** Provides 3.3V logic power
- **Output 1:** DHT22 VCC pin via **Red 22 AWG wire** (15-20 cm)
- **Output 2:** I²C pull-up resistors (SDA/SCL to 3.3V) via **Red 22 AWG wire** (5-8 cm)
- **Output 3:** Status LED anode (via 330Ω resistor) via **Red 22 AWG wire** (8-10 cm)

---

## 2. ESP32 DevKitC Pinout & Connections

### 2.1 Power Pins

| ESP32 Pin | Physical Location | Wire Type | Wire Gauge | Color | Connects To | Length | Notes |
|-----------|-------------------|-----------|------------|-------|-------------|--------|-------|
| **VIN** | Pin 2 (Left side, 2nd from top) | Stranded | 22 AWG | **Red** | Terminal Block #2 Output 1 (5V) | 8-10 cm | Main power input |
| **3V3** | Pin 1 (Left side, top) | Stranded | 22 AWG | **Red** | DHT22 VCC, I²C pull-ups, Status LED | See sections 3.1, 5.1, 6.1 | 3.3V logic supply |
| **GND** | Pin 3, 15, or any GND | Stranded | 22 AWG | **Black** | Common Ground Bus | 8-10 cm | Use multiple GND pins for distribution |

### 2.2 GPIO Pin Assignments (from config.h)

| GPIO Pin | ESP32 Physical Pin | Function | Wire Type | Wire Gauge | Color | Destination | Length | Notes |
|----------|-------------------|----------|-----------|------------|-------|-------------|--------|-------|
| **GPIO2** | Pin 4 (Left side) | STATUS_LED_PIN | Stranded | 22 AWG | **Yellow** | Status LED anode (via 330Ω) | 8-10 cm | Built-in LED alternative |
| **GPIO13** | Pin 12 (Left side) | BUZZER_PIN | Stranded | 22 AWG | **Orange** | Active buzzer IN/SIG pin | 10-15 cm | Digital output |
| **GPIO14** | Pin 13 (Left side) | LED_PIN | Stranded | 22 AWG | **Green** | LED MOSFET gate (via 100Ω) | 15-20 cm | PWM output |
| **GPIO21** | Pin 17 (Left side) | RTC_SDA_PIN | Stranded | 22 AWG | **Blue** | I²C SDA bus (shared) | 10-15 cm | I²C data line |
| **GPIO22** | Pin 18 (Left side) | RTC_SCL_PIN | Stranded | 22 AWG | **Purple** | I²C SCL bus (shared) | 10-15 cm | I²C clock line |
| **GPIO25** | Pin 21 (Left side) | PIR_PIN | Stranded | 22 AWG | **White** | PIR sensor OUT pin | 15-20 cm | Digital input |
| **GPIO26** | Pin 22 (Left side) | FAN_PIN | Stranded | 22 AWG | **Brown** | Fan MOSFET gate (via 100Ω) | 15-20 cm | PWM output |
| **GPIO27** | Pin 23 (Left side) | DHT_PIN | Stranded | 22 AWG | **Gray** | DHT22 DATA pin | 15-20 cm | One-wire data |
| **GPIO32** | Pin 28 (Right side) | ULTRASONIC_TRIG_PIN | Stranded | 22 AWG | **Pink** | HC-SR04 TRIG pin | 15-20 cm | Digital output |
| **GPIO33** | Pin 29 (Right side) | ULTRASONIC_ECHO_PIN | Stranded | 22 AWG | **Cyan** | HC-SR04 ECHO (via divider) | 15-20 cm | Digital input (5V→3.3V) |

---

## 3. Sensor Wiring - Complete Details

### 3.1 DHT22 Temperature & Humidity Sensor

**Component:** DHT22 (AM2302) with 3-pin header

**Pin Connections:**

| DHT22 Pin | Wire Type | Wire Gauge | Color | ESP32 Connection | Length | Notes |
|-----------|-----------|------------|-------|------------------|--------|-------|
| **VCC (Pin 1, Left)** | Stranded | 22 AWG | **Red** | ESP32 **3V3** pin | 15-20 cm | 3.3V power |
| **DATA (Pin 2, Center)** | Stranded | 22 AWG | **Gray** | ESP32 **GPIO27** | 15-20 cm | Data line |
| **GND (Pin 3, Right)** | Stranded | 22 AWG | **Black** | Common Ground Bus | 15-20 cm | Ground |

**Required Resistor:**
- **10 kΩ pull-up resistor** (1/4W, 5% tolerance)
- **Placement:** Between DHT22 DATA pin and ESP32 3V3 pin
- **Connection:** 
  - Resistor leg 1 → DHT22 DATA pin (solder or breadboard)
  - Resistor leg 2 → ESP32 3V3 pin (via **Red 22 AWG wire**, 5-8 cm)
- **Physical location:** As close as possible to DHT22 sensor (within 5 cm)

**Wire Routing:**
- Keep DATA wire away from power lines to reduce noise
- Use twisted pair for VCC and GND if running >20 cm

---

### 3.2 PIR Motion Sensor (HC-SR501)

**Component:** HC-SR501 PIR motion sensor module

**Pin Connections:**

| HC-SR501 Pin | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|--------------|-----------|------------|-------|------------|--------|-------|
| **VCC (Left pin)** | Stranded | 22 AWG | **Red** | Terminal Block #2 Output 2 (5V) | 15-20 cm | 5V power supply |
| **OUT (Center pin)** | Stranded | 22 AWG | **White** | ESP32 **GPIO25** | 15-20 cm | Digital output (3.3V/5V tolerant) |
| **GND (Right pin)** | Stranded | 22 AWG | **Black** | Common Ground Bus | 15-20 cm | Ground |

**Configuration:**
- **Sensitivity Potentiometer:** Leave accessible for adjustment (typically 3-7 meters range)
- **Time Delay Potentiometer:** Leave accessible (adjusts how long output stays HIGH)
- **Jumper Settings:** 
  - Single trigger mode: Jumper on "H" position
  - Repeatable trigger: Jumper on "L" position (recommended for motion detection)

**Wire Routing:**
- Keep OUT signal wire separate from power lines
- Sensor should be mounted facing the detection area

---

### 3.3 Ultrasonic Distance Sensor (HC-SR04)

**Component:** HC-SR04 ultrasonic distance sensor

**Pin Connections:**

| HC-SR04 Pin | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|-------------|-----------|------------|-------|------------|--------|-------|
| **VCC (Left pin)** | Stranded | 22 AWG | **Red** | Terminal Block #2 Output 3 (5V) | 15-20 cm | 5V power supply |
| **TRIG (2nd pin)** | Stranded | 22 AWG | **Pink** | ESP32 **GPIO32** | 15-20 cm | Trigger input (3.3V logic) |
| **ECHO (3rd pin)** | Stranded | 22 AWG | **Cyan** | Voltage divider input | 15-20 cm | Echo output (5V → needs level shift) |
| **GND (Right pin)** | Stranded | 22 AWG | **Black** | Common Ground Bus | 15-20 cm | Ground |

**Required Voltage Divider Circuit (5V → 3.3V):**

The HC-SR04 ECHO pin outputs 5V logic, which will damage ESP32 GPIO33. A resistor divider is **ESSENTIAL**.

**Components:**
- **R1:** 15 kΩ resistor (1/4W, 5% tolerance)
- **R2:** 10 kΩ resistor (1/4W, 5% tolerance)

**Circuit Connections:**
1. **R1 (15 kΩ):**
   - Leg 1 → HC-SR04 ECHO pin (via **Cyan 22 AWG wire**, 5-8 cm)
   - Leg 2 → ESP32 GPIO33 pin (via **Cyan 22 AWG wire**, 15-20 cm) AND to R2 leg 1 (junction point)

2. **R2 (10 kΩ):**
   - Leg 1 → Junction with R1 leg 2 and ESP32 GPIO33 (connect all three together)
   - Leg 2 → Common Ground Bus (via **Black 22 AWG wire**, 5-8 cm)

**Calculation:** 
- Output voltage = 5V × (R2 / (R1 + R2)) = 5V × (10k / 25k) = 2.0V (safe for 3.3V ESP32)

**Physical Layout:**
- Place resistors on breadboard or protoboard near HC-SR04
- Keep divider circuit within 10 cm of sensor

---

### 3.4 DS3231 Real-Time Clock (RTC) Module

**Component:** DS3231 RTC module with I²C interface

**Pin Connections:**

| DS3231 Pin | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|------------|-----------|------------|-------|------------|--------|-------|
| **VCC** | Stranded | 22 AWG | **Red** | Terminal Block #2 Output 4 (5V) | 10-15 cm | 5V power (module has onboard 3.3V regulator) |
| **GND** | Stranded | 22 AWG | **Black** | Common Ground Bus | 10-15 cm | Ground |
| **SDA** | Stranded | 22 AWG | **Blue** | I²C SDA bus (see section 6) | 10-15 cm | I²C data line |
| **SCL** | Stranded | 22 AWG | **Purple** | I²C SCL bus (see section 6) | 10-15 cm | I²C clock line |

**Battery Backup:**
- DS3231 module includes CR2032 battery holder
- **Install CR2032 battery** before first use for time retention during power loss
- Battery is optional but **highly recommended** for schedule functionality

**I²C Address:** 0x68 (hardware fixed, cannot be changed)

---

### 3.5 20×4 Character LCD Display (I²C Backpack)

**Component:** 20×4 Character LCD with I²C backpack module (PCF8574 or similar)

**Pin Connections:**

| LCD I²C Backpack Pin | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|---------------------|-----------|------------|-------|------------|--------|-------|
| **VCC** | Stranded | 22 AWG | **Red** | Terminal Block #2 Output 5 (5V) | 10-15 cm | 5V power supply |
| **GND** | Stranded | 22 AWG | **Black** | Common Ground Bus | 10-15 cm | Ground |
| **SDA** | Stranded | 22 AWG | **Blue** | I²C SDA bus (shared with RTC) | 10-15 cm | I²C data line |
| **SCL** | Stranded | 22 AWG | **Purple** | I²C SCL bus (shared with RTC) | 10-15 cm | I²C clock line |

**I²C Address:** 
- Default: **0x27** (most common)
- Alternative addresses: 0x3F, 0x20 (check with I²C scanner if LCD doesn't respond)
- Some backpacks have address jumpers - verify address matches firmware

**Backpack Pull-up Resistors:**
- Most I²C backpacks include onboard pull-up resistors
- **Verify:** Check if pull-ups are 4.7 kΩ to 3.3V (ESP32 compatible)
- If pull-ups are to 5V or wrong value, disable onboard pull-ups and use external 4.7 kΩ to 3.3V (see section 6.1)

---

## 4. Actuator Wiring - Complete Details

### 4.1 12V Brushless DC Fan via MOSFET

**Component:** 12V DC brushless fan (120mm, PWM-controllable)

**Fan Power Connections:**

| Fan Terminal | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|--------------|-----------|------------|-------|------------|--------|-------|
| **Fan + (Red wire)** | Stranded | 18 AWG | **Red** | Terminal Block #1 Output 2 (12V) | 20-30 cm | Positive supply |
| **Fan - (Black wire)** | Stranded | 18 AWG | **Black** | MOSFET drain terminal | 15-20 cm | Negative (switched) |

**MOSFET Circuit (IRLZ44N or similar N-channel logic-level MOSFET):**

**MOSFET Pin Connections:**

| MOSFET Terminal | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|-----------------|-----------|------------|-------|------------|--------|-------|
| **Drain (D)** | Stranded | 18 AWG | **Black** | Fan negative terminal | 15-20 cm | High-current path |
| **Source (S)** | Stranded | 18 AWG | **Black** | Common Ground Bus | 10-15 cm | Ground reference |
| **Gate (G)** | Stranded | 22 AWG | **Brown** | Gate resistor (100Ω) | 5-8 cm | Control input |

**Required Resistors:**

1. **Gate Series Resistor (100Ω):**
   - **Purpose:** Limits gate current, reduces EMI, protects ESP32 GPIO
   - **Type:** 1/4W, 5% tolerance carbon film or metal film
   - **Connections:**
     - Leg 1 → ESP32 **GPIO26** (via **Brown 22 AWG wire**, 15-20 cm)
     - Leg 2 → MOSFET Gate (G) terminal (via **Brown 22 AWG wire**, 5-8 cm)
   - **Physical placement:** As close as possible to MOSFET gate

2. **Gate Pull-down Resistor (100 kΩ):**
   - **Purpose:** Keeps MOSFET OFF during ESP32 boot/reset (prevents fan from turning on unexpectedly)
   - **Type:** 1/4W, 5% tolerance
   - **Connections:**
     - Leg 1 → MOSFET Gate (G) terminal (same point as 100Ω resistor leg 2)
     - Leg 2 → Common Ground Bus (via **Black 22 AWG wire**, 5-8 cm)

**Flyback Diode (1N5819 Schottky):**

| Diode Terminal | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|----------------|-----------|------------|-------|------------|--------|-------|
| **Cathode (banded end)** | Stranded | 18 AWG | **Red** | Terminal Block #1 (12V positive) | 10-15 cm | Positive rail |
| **Anode (non-banded end)** | Stranded | 18 AWG | **Black** | MOSFET Drain (D) terminal | 5-8 cm | Same point as fan negative |

**Purpose:** Protects MOSFET from inductive kickback when fan turns off

**Complete Fan Circuit Path:**
1. 12V+ → Fan+ → Fan- → MOSFET Drain → MOSFET Source → Ground
2. ESP32 GPIO26 → 100Ω resistor → MOSFET Gate
3. MOSFET Gate → 100kΩ resistor → Ground
4. 12V+ → Flyback diode cathode → Flyback diode anode → MOSFET Drain

---

### 4.2 12V LED Strip via MOSFET

**Component:** 12V LED strip (30cm segment, warm white, ≤1A current draw)

**LED Strip Power Connections:**

| LED Strip Terminal | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|-------------------|-----------|------------|-------|------------|--------|-------|
| **LED + (Red wire)** | Stranded | 18 AWG | **Red** | Terminal Block #1 Output 3 (12V) | 20-30 cm | Positive supply |
| **LED - (Black wire)** | Stranded | 18 AWG | **Black** | MOSFET drain terminal | 15-20 cm | Negative (switched) |

**MOSFET Circuit (AO3400A or similar N-channel logic-level MOSFET):**

**MOSFET Pin Connections:**

| MOSFET Terminal | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|-----------------|-----------|------------|-------|------------|--------|-------|
| **Drain (D)** | Stranded | 18 AWG | **Black** | LED strip negative terminal | 15-20 cm | High-current path |
| **Source (S)** | Stranded | 18 AWG | **Black** | Common Ground Bus | 10-15 cm | Ground reference |
| **Gate (G)** | Stranded | 22 AWG | **Green** | Gate resistor (100Ω) | 5-8 cm | Control input |

**Required Resistors:**

1. **Gate Series Resistor (100Ω):**
   - **Purpose:** Limits gate current, reduces EMI, protects ESP32 GPIO
   - **Type:** 1/4W, 5% tolerance
   - **Connections:**
     - Leg 1 → ESP32 **GPIO14** (via **Green 22 AWG wire**, 15-20 cm)
     - Leg 2 → MOSFET Gate (G) terminal (via **Green 22 AWG wire**, 5-8 cm)

2. **Gate Pull-down Resistor (100 kΩ):**
   - **Purpose:** Keeps MOSFET OFF during ESP32 boot/reset
   - **Type:** 1/4W, 5% tolerance
   - **Connections:**
     - Leg 1 → MOSFET Gate (G) terminal
     - Leg 2 → Common Ground Bus (via **Black 22 AWG wire**, 5-8 cm)

**Optional Smoothing Capacitor:**

| Component | Wire Type | Wire Gauge | Color | Connection | Notes |
|-----------|-----------|------------|-------|------------|-------|
| **100 µF Electrolytic Capacitor** | Stranded | 18 AWG | **Red/Black** | Across LED + and LED - terminals | Smooths PWM ripple, reduces flicker |

**Capacitor Connections:**
- **Positive leg (+)** → LED strip positive terminal (via **Red 18 AWG wire**, 5-8 cm)
- **Negative leg (-)** → LED strip negative terminal (via **Black 18 AWG wire**, 5-8 cm)
- **Polarity:** **CRITICAL** - ensure positive leg connects to positive rail

**Complete LED Circuit Path:**
1. 12V+ → LED+ → LED- → MOSFET Drain → MOSFET Source → Ground
2. ESP32 GPIO14 → 100Ω resistor → MOSFET Gate
3. MOSFET Gate → 100kΩ resistor → Ground

---

### 4.3 Active Buzzer Module

**Component:** Active buzzer module (3.3V-5V compatible)

**Pin Connections:**

| Buzzer Pin | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|------------|-----------|------------|-------|------------|--------|-------|
| **VCC (+)** | Stranded | 22 AWG | **Red** | Terminal Block #2 Output 6 (5V) | 10-15 cm | Power supply |
| **GND (-)** | Stranded | 22 AWG | **Black** | Common Ground Bus | 10-15 cm | Ground |
| **IN/SIG** | Stranded | 22 AWG | **Orange** | ESP32 **GPIO13** | 10-15 cm | Control signal |

**Current Draw Considerations:**
- **If buzzer draws ≤20 mA:** Direct connection to GPIO13 is safe (ESP32 GPIO can source up to 40 mA)
- **If buzzer draws >20 mA:** Use NPN transistor or MOSFET driver circuit:

**Optional Transistor Driver (if needed):**

| Component | Connection | Notes |
|-----------|-----------|-------|
| **NPN Transistor (2N2222 or BC547)** | Base → GPIO13 via 1 kΩ resistor | Current amplification |
| | Collector → Buzzer IN pin | High-side connection |
| | Emitter → Ground | Common emitter configuration |
| **1 kΩ Base Resistor** | Between GPIO13 and transistor base | Limits base current |
| **Flyback Diode (1N4148)** | Across buzzer terminals (cathode to +, anode to -) | Protects from inductive spikes |

---

## 5. Indicator & Status Components

### 5.1 Status LED

**Component:** 3mm or 5mm LED (any color, 3.3V compatible)

**Pin Connections:**

| LED Terminal | Wire Type | Wire Gauge | Color | Connection | Length | Notes |
|--------------|-----------|------------|-------|------------|--------|-------|
| **Anode (Long leg, +)** | Stranded | 22 AWG | **Yellow** | Current limiting resistor (330Ω) | 5-8 cm | Positive side |
| **Cathode (Short leg, -)** | Stranded | 22 AWG | **Black** | Common Ground Bus | 8-10 cm | Negative side |

**Required Resistor:**

| Component | Wire Type | Wire Gauge | Color | Connection | Notes |
|-----------|-----------|------------|-------|------------|-------|
| **330Ω Current Limiting Resistor** | Stranded | 22 AWG | **Yellow/Red** | Between ESP32 3V3 and LED anode | Limits current to ~10 mA |

**Resistor Connections:**
- **Leg 1:** ESP32 **3V3** pin (via **Red 22 AWG wire**, 8-10 cm)
- **Leg 2:** LED anode (via **Yellow 22 AWG wire**, 5-8 cm)
- **LED cathode:** Common Ground Bus (via **Black 22 AWG wire**, 8-10 cm)

**Alternative Configuration (GPIO-driven):**
- If using ESP32 **GPIO2** directly:
  - **GPIO2** → 330Ω resistor → LED anode
  - LED cathode → Ground
- This allows software control of LED on/off state

---

## 6. I²C Bus Wiring

### 6.1 Shared I²C Bus (DS3231 RTC + LCD Display)

The DS3231 RTC and LCD display share the same I²C bus using different addresses.

**I²C Bus Connections:**

| Component | Pin | Wire Type | Wire Gauge | Color | ESP32 Connection | Length |
|-----------|-----|-----------|------------|-------|------------------|--------|
| **SDA Bus** | - | Stranded | 22 AWG | **Blue** | ESP32 **GPIO21** | - |
| **SCL Bus** | - | Stranded | 22 AWG | **Purple** | ESP32 **GPIO22** | - |

**Bus Topology (Daisy Chain):**

1. **ESP32 GPIO21 (SDA):**
   - Connect to DS3231 SDA pin (via **Blue 22 AWG wire**, 10-15 cm)
   - Continue from DS3231 SDA to LCD I²C backpack SDA (via **Blue 22 AWG wire**, 10-15 cm)

2. **ESP32 GPIO22 (SCL):**
   - Connect to DS3231 SCL pin (via **Purple 22 AWG wire**, 10-15 cm)
   - Continue from DS3231 SCL to LCD I²C backpack SCL (via **Purple 22 AWG wire**, 10-15 cm)

**Required Pull-up Resistors:**

| Component | Value | Wire Type | Wire Gauge | Color | Connection | Notes |
|-----------|-------|-----------|------------|-------|------------|-------|
| **SDA Pull-up** | 4.7 kΩ | Stranded | 22 AWG | **Red** | Between SDA bus and ESP32 3V3 | **CRITICAL** - I²C requires pull-ups |
| **SCL Pull-up** | 4.7 kΩ | Stranded | 22 AWG | **Red** | Between SCL bus and ESP32 3V3 | **CRITICAL** - I²C requires pull-ups |

**Pull-up Resistor Connections:**

**SDA Pull-up (4.7 kΩ):**
- **Leg 1:** I²C SDA bus (any point along the bus, typically near ESP32)
- **Leg 2:** ESP32 **3V3** pin (via **Red 22 AWG wire**, 5-8 cm)

**SCL Pull-up (4.7 kΩ):**
- **Leg 1:** I²C SCL bus (any point along the bus, typically near ESP32)
- **Leg 2:** ESP32 **3V3** pin (via **Red 22 AWG wire**, 5-8 cm)

**Important Notes:**
- Pull-ups **MUST** be to **3.3V** (not 5V) for ESP32 compatibility
- If LCD I²C backpack has onboard pull-ups to 5V, disable them or verify they're 4.7 kΩ to 3.3V
- Only **one set** of pull-ups is needed for the entire bus (typically placed near ESP32)

**I²C Device Addresses:**
- **DS3231 RTC:** 0x68 (fixed, cannot be changed)
- **LCD I²C Backpack:** 0x27 (default, may vary - check with I²C scanner)

---

## 7. Wire Specifications & Recommendations

### 7.1 Wire Gauge Selection

| Application | Current Rating | Wire Gauge | Wire Type | Color Coding |
|-------------|----------------|------------|-----------|--------------|
| **12V Power (Fan, LED)** | 1-2 A | **18 AWG** | Stranded copper | Red (+), Black (-) |
| **5V Power Distribution** | 0.5-1 A | **20 AWG** | Stranded copper | Red (+), Black (-) |
| **3.3V Logic Power** | <100 mA | **22 AWG** | Stranded copper | Red (+), Black (-) |
| **GPIO Signals** | <40 mA | **22 AWG** | Stranded copper | Color-coded by function |
| **I²C Bus** | <10 mA | **22 AWG** | Stranded copper | Blue (SDA), Purple (SCL) |

### 7.2 Wire Type Recommendations

**Stranded vs. Solid:**
- **Use stranded wire** for all connections (more flexible, less prone to breakage)
- Stranded wire is easier to work with in breadboard/protoboard applications

**Insulation:**
- **PVC insulation** is sufficient for low-voltage applications
- **Temperature rating:** 60°C minimum (80°C recommended for reliability)
- **Voltage rating:** 300V minimum (standard for low-voltage applications)

### 7.3 Wire Color Coding Scheme

| Color | Purpose | Examples |
|-------|---------|----------|
| **Red** | Positive power rails | 12V+, 5V+, 3.3V+ |
| **Black** | Ground/negative | All GND connections |
| **Blue** | I²C SDA | GPIO21, DS3231 SDA, LCD SDA |
| **Purple** | I²C SCL | GPIO22, DS3231 SCL, LCD SCL |
| **Yellow** | Status/indicator | Status LED, GPIO2 |
| **Orange** | Buzzer/alarm | GPIO13, Buzzer IN |
| **Green** | LED control | GPIO14, LED MOSFET gate |
| **Brown** | Fan control | GPIO26, Fan MOSFET gate |
| **White** | PIR sensor | GPIO25, PIR OUT |
| **Gray** | DHT22 data | GPIO27, DHT22 DATA |
| **Pink** | Ultrasonic trigger | GPIO32, HC-SR04 TRIG |
| **Cyan** | Ultrasonic echo | GPIO33, HC-SR04 ECHO (via divider) |

**Benefits of Color Coding:**
- Faster troubleshooting
- Reduced wiring errors
- Easier maintenance and modifications

---

## 8. Connector Specifications

### 8.1 Terminal Blocks

**Type:** Screw terminal blocks, 2-pin or 4-pin

**Applications:**
- **Terminal Block #1:** 12V power distribution (4-pin recommended)
- **Terminal Block #2:** 5V power distribution (6-pin or multiple 2-pin blocks)
- **Common Ground Bus:** Single large terminal block or bus bar

**Wire Compatibility:**
- Accepts 18-22 AWG stranded wire
- Secure with screw terminals (tighten firmly but don't strip threads)

### 8.2 Dupont Connectors

**Type:** Dupont-style jumper wire connectors (M-M, M-F, F-F)

**Applications:**
- Sensor connections to ESP32 GPIO pins
- I²C bus connections
- Low-current signal connections

**Pin Compatibility:**
- Standard 0.1" (2.54mm) pitch
- Compatible with ESP32 DevKitC headers
- Compatible with most sensor module headers

### 8.3 JST Connectors (Optional, for Production)

**Type:** JST-VH or JST-XH series

**Applications:**
- Fan power connections (more secure than terminal blocks)
- LED strip connections
- High-current applications

**Specifications:**
- **JST-VH:** 3.96mm pitch, rated for 10A
- **JST-XH:** 2.50mm pitch, rated for 3A

---

## 9. Step-by-Step Assembly Sequence

### Phase 1: Power Distribution Setup

1. **Install Terminal Blocks:**
   - Mount Terminal Block #1 (12V distribution) on breadboard/protoboard
   - Mount Terminal Block #2 (5V distribution) on breadboard/protoboard
   - Mount Common Ground Bus (large terminal block or bus bar)

2. **Connect 12V Power Supply:**
   - Connect barrel jack center pin (+) to Terminal Block #1 input via **Red 18 AWG wire**
   - Connect barrel jack outer sleeve (-) to Common Ground Bus via **Black 18 AWG wire**

3. **Install and Wire Buck Converter:**
   - Mount buck converter on breadboard/protoboard
   - Connect Terminal Block #1 output to buck converter IN+ via **Red 18 AWG wire**
   - Connect Common Ground Bus to buck converter IN- via **Black 18 AWG wire**
   - Connect buck converter OUT+ to Terminal Block #2 input via **Red 20 AWG wire**
   - Connect buck converter OUT- to Common Ground Bus via **Black 20 AWG wire**
   - **Adjust buck converter output to 5.0V** using multimeter and trim pot (if available)

4. **Verify Power Rails:**
   - **DO NOT CONNECT ESP32 YET**
   - Measure Terminal Block #1: Should read 12V
   - Measure Terminal Block #2: Should read 5.0V
   - Measure Common Ground Bus: Should read 0V (reference)

### Phase 2: ESP32 Core Connections

5. **Mount ESP32 DevKitC:**
   - Place ESP32 on breadboard or mount securely
   - Ensure proper orientation (USB port accessible)

6. **Connect ESP32 Power:**
   - Connect Terminal Block #2 (5V) to ESP32 **VIN** pin via **Red 22 AWG wire**
   - Connect Common Ground Bus to ESP32 **GND** pin (use multiple GND pins if available) via **Black 22 AWG wire**

7. **Connect ESP32 3.3V Outputs:**
   - Leave ESP32 3V3 pin accessible for sensor connections (see Phase 3)

### Phase 3: Sensor Connections

8. **Connect DHT22 Sensor:**
   - DHT22 VCC → ESP32 3V3 via **Red 22 AWG wire**
   - DHT22 GND → Common Ground Bus via **Black 22 AWG wire**
   - DHT22 DATA → ESP32 GPIO27 via **Gray 22 AWG wire**
   - Install 10 kΩ pull-up resistor: DHT22 DATA to ESP32 3V3

9. **Connect PIR Sensor:**
   - PIR VCC → Terminal Block #2 (5V) via **Red 22 AWG wire**
   - PIR GND → Common Ground Bus via **Black 22 AWG wire**
   - PIR OUT → ESP32 GPIO25 via **White 22 AWG wire**

10. **Connect HC-SR04 Ultrasonic Sensor:**
    - HC-SR04 VCC → Terminal Block #2 (5V) via **Red 22 AWG wire**
    - HC-SR04 GND → Common Ground Bus via **Black 22 AWG wire**
    - HC-SR04 TRIG → ESP32 GPIO32 via **Pink 22 AWG wire**
    - **Install voltage divider for ECHO:**
      - R1 (15 kΩ): HC-SR04 ECHO to junction point
      - R2 (10 kΩ): Junction point to Ground
      - Junction point → ESP32 GPIO33 via **Cyan 22 AWG wire**

11. **Connect DS3231 RTC:**
    - DS3231 VCC → Terminal Block #2 (5V) via **Red 22 AWG wire**
    - DS3231 GND → Common Ground Bus via **Black 22 AWG wire**
    - DS3231 SDA → ESP32 GPIO21 via **Blue 22 AWG wire**
    - DS3231 SCL → ESP32 GPIO22 via **Purple 22 AWG wire**
    - **Install CR2032 battery** in DS3231 module

12. **Connect LCD Display:**
    - LCD VCC → Terminal Block #2 (5V) via **Red 22 AWG wire**
    - LCD GND → Common Ground Bus via **Black 22 AWG wire**
    - LCD SDA → DS3231 SDA (daisy chain) via **Blue 22 AWG wire**
    - LCD SCL → DS3231 SCL (daisy chain) via **Purple 22 AWG wire**

13. **Install I²C Pull-up Resistors:**
    - SDA pull-up (4.7 kΩ): I²C SDA bus to ESP32 3V3 via **Red 22 AWG wire**
    - SCL pull-up (4.7 kΩ): I²C SCL bus to ESP32 3V3 via **Red 22 AWG wire**

### Phase 4: Actuator Connections

14. **Connect 12V Fan via MOSFET:**
    - Fan + → Terminal Block #1 (12V) via **Red 18 AWG wire**
    - Fan - → MOSFET Drain via **Black 18 AWG wire**
    - MOSFET Source → Common Ground Bus via **Black 18 AWG wire**
    - **Install gate resistors:**
      - 100Ω series: ESP32 GPIO26 to MOSFET Gate via **Brown 22 AWG wire**
      - 100 kΩ pull-down: MOSFET Gate to Ground via **Black 22 AWG wire**
    - **Install flyback diode:**
      - 1N5819 cathode → Terminal Block #1 (12V) via **Red 18 AWG wire**
      - 1N5819 anode → MOSFET Drain via **Black 18 AWG wire**

15. **Connect 12V LED Strip via MOSFET:**
    - LED + → Terminal Block #1 (12V) via **Red 18 AWG wire**
    - LED - → MOSFET Drain via **Black 18 AWG wire**
    - MOSFET Source → Common Ground Bus via **Black 18 AWG wire**
    - **Install gate resistors:**
      - 100Ω series: ESP32 GPIO14 to MOSFET Gate via **Green 22 AWG wire**
      - 100 kΩ pull-down: MOSFET Gate to Ground via **Black 22 AWG wire**
    - **Optional:** Install 100 µF capacitor across LED + and LED - terminals

16. **Connect Active Buzzer:**
    - Buzzer VCC → Terminal Block #2 (5V) via **Red 22 AWG wire**
    - Buzzer GND → Common Ground Bus via **Black 22 AWG wire**
    - Buzzer IN → ESP32 GPIO13 via **Orange 22 AWG wire**
    - **If buzzer draws >20 mA:** Install transistor driver circuit (see section 4.3)

### Phase 5: Indicator Connections

17. **Connect Status LED:**
    - 330Ω resistor: ESP32 3V3 to resistor leg 1 via **Red 22 AWG wire**
    - Resistor leg 2 to LED anode via **Yellow 22 AWG wire**
    - LED cathode → Common Ground Bus via **Black 22 AWG wire**
    - **Alternative:** Connect LED to ESP32 GPIO2 for software control

### Phase 6: Final Verification

18. **Visual Inspection:**
    - Check all connections for proper wire gauge
    - Verify color coding matches documentation
    - Ensure no loose connections
    - Check resistor values and placements
    - Verify MOSFET orientations (drain/source/gate)

19. **Continuity Testing (Power OFF):**
    - Test all ground connections (should show continuity)
    - Test power rails (should show no shorts to ground)
    - Verify GPIO connections (check for correct pin assignments)

20. **Power-On Testing:**
    - **Connect 12V power supply**
    - Measure Terminal Block #1: Should read 12V
    - Measure Terminal Block #2: Should read 5.0V
    - Measure ESP32 VIN: Should read 5.0V
    - Measure ESP32 3V3: Should read 3.3V
    - **If all voltages are correct, proceed to firmware upload**

---

## 10. Verification & Testing

### 10.1 Pre-Firmware Verification Checklist

- [ ] All power rails measure correct voltages (12V, 5V, 3.3V)
- [ ] All ground connections show continuity
- [ ] No shorts between power rails and ground
- [ ] All GPIO connections verified with multimeter continuity test
- [ ] Resistor values verified with multimeter
- [ ] MOSFET orientations correct (drain/source/gate)
- [ ] Flyback diodes installed with correct polarity
- [ ] I²C pull-up resistors installed (4.7 kΩ to 3.3V)
- [ ] HC-SR04 voltage divider installed correctly
- [ ] DHT22 pull-up resistor installed (10 kΩ)

### 10.2 Post-Firmware Testing

1. **Upload Firmware:**
   - Connect ESP32 via USB cable
   - Upload firmware using PlatformIO or Arduino IDE
   - Monitor serial output at 115200 baud

2. **Sensor Testing:**
   - Verify DHT22 readings appear in serial monitor
   - Test PIR sensor (wave hand in front, check for motion detection)
   - Test HC-SR04 (measure distance, verify readings)
   - Verify DS3231 RTC time is correct
   - Check LCD display shows connection status

3. **Actuator Testing:**
   - Test fan control (should respond to PWM commands)
   - Test LED strip dimming (should respond to PWM commands)
   - Test buzzer (should sound on alarm/SOS)

4. **BLE Testing:**
   - Scan for "SmartSync" device with mobile app
   - Verify connection establishes successfully
   - Test sensor data transmission
   - Test actuator control from mobile app

### 10.3 Troubleshooting Common Issues

**Problem: ESP32 doesn't power on**
- Check VIN connection (should read 5V)
- Verify ground connection
- Check for shorts on power rails

**Problem: Sensors not responding**
- Verify power connections (VCC and GND)
- Check signal wire connections to correct GPIO pins
- Verify pull-up resistors installed (DHT22, I²C)
- Check HC-SR04 voltage divider circuit

**Problem: Fan/LED not working**
- Verify MOSFET gate connections
- Check gate resistors (100Ω series, 100kΩ pull-down)
- Verify flyback diode polarity
- Test MOSFET with multimeter (check for damage)

**Problem: I²C devices not detected**
- Verify pull-up resistors (4.7 kΩ to 3.3V, not 5V)
- Check SDA/SCL connections (GPIO21/GPIO22)
- Verify device addresses (DS3231: 0x68, LCD: 0x27)
- Use I²C scanner to detect devices

**Problem: HC-SR04 gives incorrect readings**
- Verify voltage divider circuit (15kΩ + 10kΩ)
- Check ECHO pin connection to GPIO33
- Ensure TRIG pin connected to GPIO32

---

## Appendix A: Complete Pin Reference Table

| ESP32 Pin | GPIO | Function | Wire Color | Destination | Notes |
|-----------|------|----------|------------|-------------|-------|
| Pin 1 | 3V3 | 3.3V Output | Red | DHT22 VCC, I²C pull-ups, Status LED | Power supply |
| Pin 2 | VIN | 5V Input | Red | Terminal Block #2 (5V) | Main power |
| Pin 3 | GND | Ground | Black | Common Ground Bus | Ground reference |
| Pin 4 | GPIO2 | STATUS_LED_PIN | Yellow | Status LED (via 330Ω) | Optional |
| Pin 12 | GPIO13 | BUZZER_PIN | Orange | Active buzzer IN | Digital output |
| Pin 13 | GPIO14 | LED_PIN | Green | LED MOSFET gate (via 100Ω) | PWM output |
| Pin 15 | GND | Ground | Black | Common Ground Bus | Additional ground |
| Pin 17 | GPIO21 | RTC_SDA_PIN | Blue | I²C SDA bus | I²C data |
| Pin 18 | GPIO22 | RTC_SCL_PIN | Purple | I²C SCL bus | I²C clock |
| Pin 21 | GPIO25 | PIR_PIN | White | PIR sensor OUT | Digital input |
| Pin 22 | GPIO26 | FAN_PIN | Brown | Fan MOSFET gate (via 100Ω) | PWM output |
| Pin 23 | GPIO27 | DHT_PIN | Gray | DHT22 DATA | One-wire data |
| Pin 28 | GPIO32 | ULTRASONIC_TRIG_PIN | Pink | HC-SR04 TRIG | Digital output |
| Pin 29 | GPIO33 | ULTRASONIC_ECHO_PIN | Cyan | HC-SR04 ECHO (via divider) | Digital input |

---

## Appendix B: Resistor Summary

| Resistor | Value | Purpose | Location | Connections |
|----------|-------|---------|----------|-------------|
| R1 | 10 kΩ | DHT22 pull-up | Near DHT22 | DATA pin to 3V3 |
| R2 | 15 kΩ | HC-SR04 voltage divider | Near HC-SR04 | ECHO to junction |
| R3 | 10 kΩ | HC-SR04 voltage divider | Near HC-SR04 | Junction to ground |
| R4 | 4.7 kΩ | I²C SDA pull-up | Near ESP32 | SDA bus to 3V3 |
| R5 | 4.7 kΩ | I²C SCL pull-up | Near ESP32 | SCL bus to 3V3 |
| R6 | 100Ω | Fan MOSFET gate series | Near MOSFET | GPIO26 to gate |
| R7 | 100 kΩ | Fan MOSFET gate pull-down | Near MOSFET | Gate to ground |
| R8 | 100Ω | LED MOSFET gate series | Near MOSFET | GPIO14 to gate |
| R9 | 100 kΩ | LED MOSFET gate pull-down | Near MOSFET | Gate to ground |
| R10 | 330Ω | Status LED current limit | Near LED | 3V3 to LED anode |

---

## Appendix C: Component Placement Recommendations

**Power Section (Left side of breadboard):**
- Terminal Block #1 (12V distribution)
- Buck converter
- Terminal Block #2 (5V distribution)
- Common Ground Bus

**ESP32 Section (Center):**
- ESP32 DevKitC mounted securely
- Easy access to all GPIO pins

**Sensor Section (Right side, top):**
- DHT22 sensor
- PIR sensor
- HC-SR04 sensor
- DS3231 RTC module

**I²C Section (Right side, middle):**
- LCD display
- I²C pull-up resistors

**Actuator Section (Right side, bottom):**
- Fan MOSFET circuit
- LED MOSFET circuit
- Buzzer module

**Indicator Section (Near ESP32):**
- Status LED with resistor

**Wiring Organization:**
- Bundle power wires together (Red/Black)
- Keep signal wires separate from power wires
- Use cable ties or heat shrink for wire management
- Label wires with heat-shrink labels or masking tape

---

## Conclusion

This wiring guide provides complete, detailed instructions for assembling the SmartSync prototype. Every connection, wire type, pin number, and component has been specified to ensure successful assembly and operation.

**Key Reminders:**
- Always verify connections before applying power
- Use appropriate wire gauges for current ratings
- Install all required resistors and protection components
- Follow the step-by-step assembly sequence
- Test each phase before proceeding to the next

For firmware configuration and programming instructions, refer to `firmware/SmartSync_ESP32/README.md`.

For hardware component specifications, refer to `docs/hardware/hardware.md`.

---

**Document Version:** 2.0  
**Last Updated:** 2024  
**Compatible Firmware:** SmartSync_ESP32 v1.0.0  
**Compatible Hardware:** ESP32 DevKitC, components listed in hardware.md
