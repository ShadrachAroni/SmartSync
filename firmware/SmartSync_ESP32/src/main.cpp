#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include "../include/config.h"
#include "ble/BLEService.h"
#include "actuators/FanController.h"
#include "sensors/DHT22Sensor.h"
#include "storage/DeviceStorage.h"
#include "scheduler/ScheduleManager.h"
#include "security/AlarmSystem.h"
#include "display/LCDDisplay.h"

// ============================================================================
// GLOBAL OBJECTS
// ============================================================================
DHT22Sensor dhtSensor(DHT_PIN, DHT_TYPE);
DeviceStorage storage;
FanController fanController;
ScheduleManager scheduleManager;
AlarmSystem alarmSystem;
BLEServiceManager bleManager;
LCDDisplay lcdDisplay;

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
bool securityEnabled = true;
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
    storage.saveAutoMode(enabled);
    DEBUG_PRINTF("Auto mode %s\n", enabled ? "ENABLED" : "DISABLED");
}

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
void setupPins();
void setupSensors();
void setupPWM();
void setupBLE();
void setupLCD();
void readSensors();
void updateAutoMode();
void setFanSpeed(uint8_t speed);
void setLEDBrightness(uint8_t brightness);
void checkMotionTimeout();
void sendImmediateStatus();
void handleBleCommand(const char* cmd, JsonVariantConst payload);
void handleScheduleExecution(const ScheduleEntry& entry);
void setSecurityEnabled(bool enabled);
void triggerAlarm(uint16_t durationMs);

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

    storage.begin(PREF_NAMESPACE);

    setupPins();
    setupPWM();
    setupSensors();
    setupLCD();
    alarmSystem.begin(BUZZER_PIN, 255);
    setupBLE();

    // Load persisted settings
    autoMode = storage.loadAutoMode(false);
    securityEnabled = storage.loadSecurityEnabled(true);
    if (!securityEnabled) {
        alarmSystem.silence();
    }
    currentFanSpeed = storage.loadFanSpeed(0);
    currentLEDBrightness = storage.loadLedBrightness(128);
    scheduleManager.begin(&storage);
    scheduleManager.onExecute(handleScheduleExecution);

    // Apply saved settings
    setFanSpeed(currentFanSpeed);
    setLEDBrightness(currentLEDBrightness);

    bleManager.onCommand(handleBleCommand);

    DEBUG_PRINTLN("Setup complete. Entering main loop...\n");
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop() {
    unsigned long currentMillis = millis();

    // Update BLE connection status
    bleManager.update();
    fanController.loop();
    scheduleManager.loop();
    
    // Update LCD display
    lcdDisplay.update();
    lcdDisplay.setConnectionStatus(bleManager.isConnected());

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
            sensorData.distance,
            securityEnabled
        );
    }

    delay(10);
}

// ============================================================================
// LCD SETUP
// ============================================================================
void setupLCD() {
    DEBUG_PRINTLN("Setting up LCD Display...");
    
    if (lcdDisplay.begin(LCD_I2C_ADDRESS, LCD_COLS, LCD_ROWS)) {
        DEBUG_PRINTLN("LCD Display ready.");
    } else {
        DEBUG_PRINTLN("LCD Display initialization failed (continuing without LCD)");
    }
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
        
        // Update LCD to show BLE is ready
        lcdDisplay.setConnectionStatus(false); // Initially pending
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
    fanController.begin(FAN_PIN, FAN_PWM_CHANNEL, FAN_PWM_FREQ, FAN_PWM_RESOLUTION);
    ledcSetup(LED_PWM_CHANNEL, LED_PWM_FREQ, LED_PWM_RESOLUTION);
    ledcAttachPin(LED_PIN, LED_PWM_CHANNEL);
    DEBUG_PRINTLN("PWM channels configured.");
}

// ============================================================================
// SENSOR SETUP
// ============================================================================
void setupSensors() {
    DEBUG_PRINTLN("Initializing sensors...");
    dhtSensor.begin();
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
    EnvironmentalReading env = dhtSensor.read();

    if (env.valid) {
        sensorData.temperature = env.temperature;
        sensorData.humidity = env.humidity;
        DEBUG_PRINTF("Temp: %.1f°C, Humidity: %.1f%%\n", env.temperature, env.humidity);
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

    if (securityEnabled) {
        alarmSystem.update(sensorData.motionDetected, sensorData.distance, sensorData.temperature);
    } else if (alarmSystem.isActive()) {
        alarmSystem.silence();
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

void setSecurityEnabled(bool enabled) {
    securityEnabled = enabled;
    storage.saveSecurityEnabled(enabled);

    if (!enabled && alarmSystem.isActive()) {
        alarmSystem.silence();
    }

    DEBUG_PRINTF("Security system %s\n", enabled ? "ARMED" : "DISARMED");
    sendImmediateStatus();
}

void triggerAlarm(uint16_t durationMs) {
    alarmSystem.triggerManualAlarm(durationMs);
    sendImmediateStatus();
}

// ============================================================================
// FAN CONTROL
// ============================================================================
void setFanSpeed(uint8_t speed) {
    currentFanSpeed = speed;
    fanController.smoothTo(speed);
    storage.saveFanSpeed(speed);
    DEBUG_PRINTF("Fan: %d (%.1f%%)\n", speed, (speed / 255.0f) * 100);
    sendImmediateStatus();
}

// ============================================================================
// LED CONTROL
// ============================================================================
void setLEDBrightness(uint8_t brightness) {
    currentLEDBrightness = brightness;
    ledcWrite(LED_PWM_CHANNEL, brightness);
    storage.saveLedBrightness(brightness);
    DEBUG_PRINTF("LED: %d (%.1f%%)\n", brightness, (brightness / 255.0f) * 100);
    sendImmediateStatus();
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

void handleScheduleExecution(const ScheduleEntry& entry) {
    DEBUG_PRINTF("Executing schedule #%d (%02d:%02d)\n", entry.id, entry.hour, entry.minute);
    setFanSpeed(entry.fanSpeed);
    setLEDBrightness(entry.ledBrightness);
    sendImmediateStatus();
}

void sendImmediateStatus() {
    bleManager.sendSensorData(
        sensorData.temperature,
        sensorData.humidity,
        currentFanSpeed,
        currentLEDBrightness,
        sensorData.motionDetected,
        sensorData.distance,
        securityEnabled
    );
}

void handleBleCommand(const char* cmd, JsonVariantConst payload) {
    JsonVariantConst data = payload["value"];
    if (data.isNull()) {
        data = payload;
    }

    if (strcmp(cmd, CMD_GET_STATUS) == 0 || strcmp(cmd, CMD_GET_SENSOR) == 0) {
        sendImmediateStatus();
        return;
    }

    if (strcmp(cmd, CMD_ADD_SCHEDULE) == 0) {
        ScheduleEntry entry;
        entry.id = data["id"] | 0;
        if (data["time"].is<JsonObjectConst>()) {
            entry.hour = data["time"]["hour"] | 0;
            entry.minute = data["time"]["minute"] | 0;
        } else {
            entry.hour = data["hour"] | 0;
            entry.minute = data["minute"] | 0;
        }
        entry.fanSpeed = data["fan"] | data["fan_speed"] | currentFanSpeed;
        entry.ledBrightness = data["led"] | data["led_brightness"] | currentLEDBrightness;
        entry.enabled = data["enabled"] | true;
        entry.repeatDaily = data["repeat"] | true;

        if (entry.id > 0 && scheduleManager.update(entry)) {
            DEBUG_PRINTF("Updated schedule #%d\n", entry.id);
        } else if (scheduleManager.add(entry)) {
            DEBUG_PRINTF("Added schedule #%d\n", entry.id);
        }
        return;
    }

    if (strcmp(cmd, CMD_DELETE_SCHEDULE) == 0) {
        uint8_t id = data["id"] | 0;
        if (scheduleManager.remove(id)) {
            DEBUG_PRINTF("Deleted schedule #%d\n", id);
        }
        return;
    }

    if (strcmp(cmd, CMD_SET_SECURITY) == 0) {
        bool enabled = securityEnabled;
        if (data.is<bool>()) {
            enabled = data.as<bool>();
        } else if (!data["enabled"].isNull()) {
            enabled = data["enabled"];
        } else if (!data["value"].isNull()) {
            enabled = data["value"];
        }
        setSecurityEnabled(enabled);
        DEBUG_PRINTF("Security command received: %s\n", enabled ? "ARM" : "DISARM");
        return;
    }

    if (strcmp(cmd, CMD_SOS) == 0) {
        uint16_t duration = data["duration"] | data["value"] | 5000;
        triggerAlarm(duration);
        DEBUG_PRINTLN("SOS alarm triggered");
        return;
    }

    DEBUG_PRINT("Unhandled command: ");
    DEBUG_PRINTLN(cmd);
}