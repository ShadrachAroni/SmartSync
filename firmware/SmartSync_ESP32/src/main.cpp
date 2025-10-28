#include <Arduino.h>
#include <Wire.h>
#include <DHT.h>
#include <Preferences.h>
#include "../include/config.h"
#include "ble/BLEService.h"

// ============================================================================
// GLOBAL OBJECTS
// ============================================================================
DHT dht(DHT_PIN, DHT_TYPE);
Preferences preferences;
BLEServiceManager bleManager;

// ============================================================================
// GLOBAL VARIABLES
// ============================================================================
struct SensorData {
    float temperature;
    float humidity;
    bool motionDetected;
    float distance;
    unsigned long lastMotionTime;
};

SensorData sensorData;
bool autoMode = false;
uint8_t currentFanSpeed = 0;
uint8_t currentLEDBrightness = 0;

unsigned long lastSensorRead = 0;
unsigned long lastBLEUpdate = 0;

// ============================================================================
// CALLBACK FUNCTIONS
// ============================================================================
void onFanSpeedChanged(uint8_t speed) {
    setFanSpeed(speed);
}

void onLEDBrightnessChanged(uint8_t brightness) {
    setLEDBrightness(brightness);
}

void onAutoModeChanged(bool enabled) {
    autoMode = enabled;
    preferences.putBool(PREF_AUTO_MODE, enabled);
    DEBUG_PRINTF("Auto mode %s\n", enabled ? "ENABLED" : "DISABLED");
}

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
void setupPins();
void setupSensors();
void setupPWM();
void setupBLE();
void readSensors();
void updateAutoMode();
void setFanSpeed(uint8_t speed);
void setLEDBrightness(uint8_t brightness);
void checkMotionTimeout();

// ============================================================================
// SETUP
// ============================================================================
void setup() {
    #if DEBUG_SERIAL
    Serial.begin(DEBUG_BAUD_RATE);
    while (!Serial) delay(10);
    DEBUG_PRINTLN("\n=================================");
    DEBUG_PRINTLN("SmartSync ESP32 Starting...");
    DEBUG_PRINTF("Firmware Version: %s\n", FIRMWARE_VERSION);
    DEBUG_PRINTLN("=================================\n");
    #endif

    setupPins();
    setupPWM();
    setupSensors();
    setupBLE();

    // Load preferences
    preferences.begin(PREF_NAMESPACE, false);
    autoMode = preferences.getBool(PREF_AUTO_MODE, false);
    currentFanSpeed = preferences.getUInt(PREF_FAN_SPEED, 0);
    currentLEDBrightness = preferences.getUInt(PREF_LED_BRIGHTNESS, 128);

    // Apply saved settings
    setFanSpeed(currentFanSpeed);
    setLEDBrightness(currentLEDBrightness);

    DEBUG_PRINTLN("Setup complete. Entering main loop...\n");
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop() {
    unsigned long currentMillis = millis();

    // Update BLE connection status
    bleManager.update();

    // Read sensors periodically
    if (currentMillis - lastSensorRead >= SENSOR_READ_INTERVAL) {
        lastSensorRead = currentMillis;
        readSensors();

        if (autoMode) {
            updateAutoMode();
        }

        checkMotionTimeout();
    }

    // Send BLE updates
    if (bleManager.isConnected() && 
        (currentMillis - lastBLEUpdate >= BLE_UPDATE_INTERVAL)) {
        lastBLEUpdate = currentMillis;
        
        bleManager.sendSensorData(
            sensorData.temperature,
            sensorData.humidity,
            currentFanSpeed,
            currentLEDBrightness,
            sensorData.motionDetected,
            sensorData.distance
        );
    }

    delay(10);
}

// ============================================================================
// BLE SETUP
// ============================================================================
void setupBLE() {
    DEBUG_PRINTLN("Setting up BLE service...");
    
    if (bleManager.begin()) {
        // Register callbacks
        bleManager.onFanSpeedChange(onFanSpeedChanged);
        bleManager.onLEDBrightnessChange(onLEDBrightnessChanged);
        bleManager.onAutoModeChange(onAutoModeChanged);
        
        DEBUG_PRINTLN("BLE service ready.");
    } else {
        DEBUG_PRINTLN("BLE initialization failed!");
    }
}

// ============================================================================
// PIN SETUP
// ============================================================================
void setupPins() {
    DEBUG_PRINTLN("Setting up GPIO pins...");
    pinMode(PIR_PIN, INPUT);
    pinMode(ULTRASONIC_ECHO_PIN, INPUT);
    pinMode(STATUS_LED_PIN, OUTPUT);
    pinMode(ULTRASONIC_TRIG_PIN, OUTPUT);
    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(STATUS_LED_PIN, LOW);
    digitalWrite(BUZZER_PIN, LOW);
    DEBUG_PRINTLN("GPIO pins configured.");
}

// ============================================================================
// PWM SETUP
// ============================================================================
void setupPWM() {
    DEBUG_PRINTLN("Setting up PWM channels...");
    ledcSetup(FAN_PWM_CHANNEL, FAN_PWM_FREQ, FAN_PWM_RESOLUTION);
    ledcAttachPin(FAN_PIN, FAN_PWM_CHANNEL);
    ledcSetup(LED_PWM_CHANNEL, LED_PWM_FREQ, LED_PWM_RESOLUTION);
    ledcAttachPin(LED_PIN, LED_PWM_CHANNEL);
    DEBUG_PRINTLN("PWM channels configured.");
}

// ============================================================================
// SENSOR SETUP
// ============================================================================
void setupSensors() {
    DEBUG_PRINTLN("Initializing sensors...");
    dht.begin();
    Wire.begin(RTC_SDA_PIN, RTC_SCL_PIN);
    sensorData.temperature = 0.0f;
    sensorData.humidity = 0.0f;
    sensorData.motionDetected = false;
    sensorData.distance = 0.0f;
    sensorData.lastMotionTime = 0;
    DEBUG_PRINTLN("Sensors initialized.");
}

// ============================================================================
// READ SENSORS
// ============================================================================
void readSensors() {
    float temp = dht.readTemperature();
    float hum = dht.readHumidity();

    if (!isnan(temp) && !isnan(hum)) {
        sensorData.temperature = temp;
        sensorData.humidity = hum;
        DEBUG_PRINTF("Temp: %.1f°C, Humidity: %.1f%%\n", temp, hum);
    }

    bool motion = digitalRead(PIR_PIN);
    if (motion && !sensorData.motionDetected) {
        sensorData.motionDetected = true;
        sensorData.lastMotionTime = millis();
        DEBUG_PRINTLN("Motion detected!");
        digitalWrite(STATUS_LED_PIN, HIGH);
        delay(100);
        digitalWrite(STATUS_LED_PIN, LOW);
    } else if (!motion) {
        sensorData.motionDetected = false;
    }

    digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(ULTRASONIC_TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(ULTRASONIC_TRIG_PIN, LOW);

    long duration = pulseIn(ULTRASONIC_ECHO_PIN, HIGH, 30000);
    if (duration > 0) {
        sensorData.distance = duration * 0.034 / 2;
    }
}

// ============================================================================
// AUTO MODE LOGIC
// ============================================================================
void updateAutoMode() {
    AutoModeSettings settings;
    uint8_t targetSpeed = 0;
    float temp = sensorData.temperature;

    if (temp < TEMP_MIN_THRESHOLD) {
        targetSpeed = 0;
    } else if (temp < settings.tempLow) {
        targetSpeed = settings.fanSpeedLow;
    } else if (temp < settings.tempHigh) {
        targetSpeed = settings.fanSpeedMed;
    } else if (temp < TEMP_MAX_THRESHOLD) {
        targetSpeed = settings.fanSpeedHigh;
    } else {
        targetSpeed = 255;
    }

    if (targetSpeed != currentFanSpeed) {
        setFanSpeed(targetSpeed);
    }
}

// ============================================================================
// FAN CONTROL
// ============================================================================
void setFanSpeed(uint8_t speed) {
    currentFanSpeed = speed;
    ledcWrite(FAN_PWM_CHANNEL, speed);
    preferences.putUInt(PREF_FAN_SPEED, speed);
    DEBUG_PRINTF("Fan: %d (%.1f%%)\n", speed, (speed / 255.0f) * 100);
}

// ============================================================================
// LED CONTROL
// ============================================================================
void setLEDBrightness(uint8_t brightness) {
    currentLEDBrightness = brightness;
    ledcWrite(LED_PWM_CHANNEL, brightness);
    preferences.putUInt(PREF_LED_BRIGHTNESS, brightness);
    DEBUG_PRINTF("LED: %d (%.1f%%)\n", brightness, (brightness / 255.0f) * 100);
}

// ============================================================================
// MOTION TIMEOUT CHECK
// ============================================================================
void checkMotionTimeout() {
    if (sensorData.lastMotionTime > 0) {
        unsigned long elapsed = millis() - sensorData.lastMotionTime;
        if (elapsed > MOTION_TIMEOUT && !sensorData.motionDetected) {
            DEBUG_PRINTLN("⚠️  No motion for 5 minutes!");
        }
    }
}