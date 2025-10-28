#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ============================================================================
// DEVICE INFORMATION
// ============================================================================
#define DEVICE_NAME "SmartSync"
#define FIRMWARE_VERSION "1.0.0"
#define HARDWARE_VERSION "1.0"

// ============================================================================
// PIN DEFINITIONS
// ============================================================================

// DHT22 Temperature & Humidity Sensor
#define DHT_PIN 27
#define DHT_TYPE DHT22

// PIR Motion Sensor
#define PIR_PIN 25

// HC-SR04 Ultrasonic Sensor
#define ULTRASONIC_TRIG_PIN 32
#define ULTRASONIC_ECHO_PIN 33

// Fan Control (PWM)
#define FAN_PIN 26
#define FAN_PWM_CHANNEL 0
#define FAN_PWM_FREQ 25000
#define FAN_PWM_RESOLUTION 8

// LED Control (PWM)
#define LED_PIN 14
#define LED_PWM_CHANNEL 1
#define LED_PWM_FREQ 5000
#define LED_PWM_RESOLUTION 8

// Buzzer
#define BUZZER_PIN 13

// RTC I2C (DS3231)
#define RTC_SDA_PIN 21
#define RTC_SCL_PIN 22

// Status LED (built-in)
#define STATUS_LED_PIN 2

// ============================================================================
// BLE CONFIGURATION
// ============================================================================
#define BLE_DEVICE_NAME "SmartSync"
#define BLE_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHARACTERISTIC_UUID_RX "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_CHARACTERISTIC_UUID_TX "beb5483f-36e1-4688-b7f5-ea07361b26a8"

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
#define PROXIMITY_THRESHOLD 50

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
#define SENSOR_READ_INTERVAL 10000   // 10 seconds
#define BLE_UPDATE_INTERVAL 5000     // 5 seconds
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