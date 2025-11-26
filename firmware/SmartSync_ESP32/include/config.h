#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ============================================================================
// DEVICE INFORMATION
// ============================================================================
#define DEVICE_NAME "SmartSync"
#define FIRMWARE_VERSION "1.1.0"
#define HARDWARE_VERSION "1.1"

// ============================================================================
// PIN DEFINITIONS
// Updated to match wiring diagram (without buck converter)
// ============================================================================

// DHT22 Temperature & Humidity Sensor
// VCC: 3.3V rail, DAT: GPIO4 (with 10kΩ pull-up to 3.3V)
#define DHT_PIN 4
#define DHT_TYPE DHT22

// PIR Motion Sensor
// VCC: 5V rail, OUT: GPIO19
#define PIR_PIN 19

// HY-SRF05 Ultrasonic Sensor
// VCC: 5V rail, TRIG: GPIO5, ECHO: GPIO18 (via voltage divider)
#define ULTRASONIC_TRIG_PIN 5
#define ULTRASONIC_ECHO_PIN 18

// Fan Control (PWM via MOSFET IRFZ44N)
// Gate: GPIO13 (with 330Ω resistor + 10kΩ pull-down)
// Fan powered by 12V adapter directly
#define FAN_PIN 13
#define FAN_PWM_CHANNEL 0
#define FAN_PWM_FREQ 25000
#define FAN_PWM_RESOLUTION 8

// Green LED bank (3 individual LEDs, all controlled together)
// Each LED: Anode → 5V rail via 330Ω, Cathode → GPIO pin
// LED 1: GPIO25, LED 2: GPIO32, LED 3: GPIO33
#define GREEN_LED_1_PIN 25
#define GREEN_LED_2_PIN 32
#define GREEN_LED_3_PIN 33
#define GREEN_LED_PWM_CHANNEL_1 1
#define GREEN_LED_PWM_CHANNEL_2 2
#define GREEN_LED_PWM_CHANNEL_3 3
#define GREEN_LED_PWM_FREQ 5000
#define GREEN_LED_PWM_RESOLUTION 8

// RGB status indicator (common cathode)
// Cathode: Ground, Anodes: GPIO pins via 330Ω each
// Red: GPIO14, Green: GPIO27, Blue: GPIO26
#define RGB_LED_RED_PIN 14
#define RGB_LED_GREEN_PIN 27
#define RGB_LED_BLUE_PIN 26
#define RGB_LED_RED_CHANNEL 4
#define RGB_LED_GREEN_CHANNEL 5
#define RGB_LED_BLUE_CHANNEL 6
#define RGB_LED_PWM_FREQ 5000
#define RGB_LED_PWM_RESOLUTION 8

// Buzzer
// Positive: GPIO23, Negative: Ground (optional 330Ω resistor)
#define BUZZER_PIN 23

// RTC I2C (DS3231) - Shared I2C bus with LCD
#define RTC_SDA_PIN 21
#define RTC_SCL_PIN 22

// LCD Display (20x4 Character LCD with I2C backpack)
// Uses same I2C bus as RTC (SDA/SCL pins above)
#define LCD_I2C_ADDRESS 0x27  // Common I2C address for 20x4 LCD with I2C backpack
#define LCD_COLS 20
#define LCD_ROWS 4

// Status LED (built-in)
#define STATUS_LED_PIN 2

// ============================================================================
// BLE CONFIGURATION
// ============================================================================
#define BLE_DEVICE_NAME "SmartSync"
#define BLE_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHARACTERISTIC_UUID_RX "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_CHARACTERISTIC_UUID_TX "beb5483f-36e1-4688-b7f5-ea07361b26a8"

#define CMD_SET_FAN         "SET_FAN"
#define CMD_SET_LED         "SET_LED"
#define CMD_SET_AUTO        "SET_AUTO"
#define CMD_GET_STATUS      "GET_STATUS"
#define CMD_GET_SENSOR      "GET_SENSOR"
#define CMD_ADD_SCHEDULE    "ADD_SCHEDULE"
#define CMD_DELETE_SCHEDULE "DEL_SCHEDULE"
#define CMD_SOS             "SOS"
#define CMD_SET_SECURITY    "SET_SECURITY"
#define CMD_SET_HUB_CONFIG  "SET_HUB_CONFIG"
#define CMD_FACTORY_RESET   "FACTORY_RESET"

// ============================================================================
// SENSOR THRESHOLDS
// ============================================================================
#define TEMP_MIN_THRESHOLD 18.0f
#define TEMP_MAX_THRESHOLD 32.0f
#define HUMIDITY_MIN_THRESHOLD 30.0f
#define HUMIDITY_MAX_THRESHOLD 70.0f

// Motion detection timeout (milliseconds)
#define MOTION_TIMEOUT 300000  // 5 minutes

// Distance threshold for proximity alert (cm)
#define PROXIMITY_THRESHOLD 20

// ============================================================================
// AUTO MODE SETTINGS
// ============================================================================
struct AutoModeSettings {
    float tempLow = 24.0f;
    float tempHigh = 28.0f;
    uint8_t fanSpeedLow = 77;   // 30%
    uint8_t fanSpeedMed = 128;  // 50%
    uint8_t fanSpeedHigh = 191; // 75%
};

// ============================================================================
// TIMING CONSTANTS
// ============================================================================
#define SENSOR_READ_INTERVAL 2000    // 2 seconds for live data
#define BLE_UPDATE_INTERVAL 1000     // 1 second for minimal delay
#define SCHEDULE_CHECK_INTERVAL 60000 // 1 minute
#define WATCHDOG_TIMEOUT 30000       // 30 seconds

// ============================================================================
// STORAGE KEYS
// ============================================================================
#define PREF_NAMESPACE "smartsync"
#define PREF_DEVICE_ID "device_id"
#define PREF_DEVICE_PIN "device_pin"
#define PREF_AUTO_MODE "auto_mode"
#define PREF_FAN_SPEED "fan_speed"
#define PREF_LED_BRIGHTNESS "led_bright"
#define PREF_SECURITY_ENABLED "security_enabled"

// ============================================================================
// DEBUG SETTINGS
// ============================================================================
#define DEBUG_SERIAL true
#define DEBUG_BAUD_RATE 115200

#if DEBUG_SERIAL
    #define DEBUG_PRINT(x) Serial.print(x)
    #define DEBUG_PRINTLN(x) Serial.println(x)
    #define DEBUG_PRINTF(x, ...) Serial.printf(x, __VA_ARGS__)
#else
    #define DEBUG_PRINT(x)
    #define DEBUG_PRINTLN(x)
    #define DEBUG_PRINTF(x, ...)
#endif

#endif // CONFIG_H