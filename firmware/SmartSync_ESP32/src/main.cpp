#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <ESP.h>
#include "../include/config.h"
#include "ble/BLEService.h"
#include "actuators/FanController.h"
#include "actuators/RGBStatusLED.h"
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
RGBStatusLED statusIndicator;

// ============================================================================
// GLOBAL VARIABLES
// ============================================================================
struct SensorData {
    float temperature;
    float humidity;
    float heatIndex;
    bool motionDetected;
    float distance;
    unsigned long lastMotionTime;
};

SensorData sensorData;
bool autoMode = false;
bool securityEnabled = true;
unsigned long securityArmedAt = 0; // Timestamp when security was last armed (for grace period)
uint8_t currentFanSpeed = 0;
uint8_t currentLEDBrightness = 0;

unsigned long lastSensorRead = 0;
unsigned long lastBLEUpdate = 0;
unsigned long lastBleHealthLog = 0;
String serialCommandBuffer;
constexpr size_t SERIAL_CMD_MAX_LEN = 128;

// ============================================================================
// FUNCTION DECLARATIONS
// ============================================================================
void setupPins();
void setupSensors();
void setupPWM();
void setupBLE();
void setupLCD();
void updateStatusIndicatorState();
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
void handleBleConnectionChanged(bool connected);
void monitorBleLinkHealth();
void handleSerialInput();
void processSerialCommand(const String& command);
void printSerialHelp();
void printBleWelcomeBanner();
void pulseStatusLed(uint8_t pulses = 3, uint16_t onMs = 80, uint16_t offMs = 80);
void flashStatusIndicator(bool connected);
uint8_t clampToByte(int value);
uint8_t percentToByte(int percent);
void performFactoryReset();

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
// SETUP
// ============================================================================
void setup() {
    #if DEBUG_SERIAL
    Serial.begin(DEBUG_BAUD_RATE);
    const unsigned long serialWaitStart = millis();
    while (!Serial && (millis() - serialWaitStart) < 2000) {
        delay(10);
    }
    DEBUG_PRINTF("SmartSync v%s starting...\n", FIRMWARE_VERSION);
    printSerialHelp();
    #endif

    storage.begin(PREF_NAMESPACE);

    setupPins();
    statusIndicator.begin(
        RGB_LED_RED_PIN,
        RGB_LED_GREEN_PIN,
        RGB_LED_BLUE_PIN,
        RGB_LED_RED_CHANNEL,
        RGB_LED_GREEN_CHANNEL,
        RGB_LED_BLUE_CHANNEL,
        false  // Common cathode, not anode
    );
    setupPWM();
    setupSensors();
    setupLCD();
    alarmSystem.begin(BUZZER_PIN, 255);
    alarmSystem.enableManualAlarm(false);
    setupBLE();

    // Load persisted settings
    autoMode = storage.loadAutoMode(false);
    securityEnabled = storage.loadSecurityEnabled(false);
    if (!securityEnabled) {
        alarmSystem.silence();
    }
    currentFanSpeed = storage.loadFanSpeed(0);
    currentLEDBrightness = 0;
    storage.saveLedBrightness(0);
    
    // Load hub configuration (room name and primary status)
    String roomName = storage.loadRoomName("");
    bool isPrimaryHub = storage.loadIsPrimaryHub(false);
    if (roomName.length() > 0) {
        lcdDisplay.setRoomName(roomName.c_str());
    }
    lcdDisplay.setIsPrimaryHub(isPrimaryHub);
    
    scheduleManager.begin(&storage);
    scheduleManager.onExecute(handleScheduleExecution);

    // Apply saved settings
    setFanSpeed(currentFanSpeed);
    setLEDBrightness(currentLEDBrightness);

    bleManager.onCommand(handleBleCommand);
    bleManager.onConnectionChange(handleBleConnectionChanged);

    updateStatusIndicatorState();
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop() {
    unsigned long currentMillis = millis();

    handleSerialInput();

    // Update BLE connection status
    bleManager.update();
    monitorBleLinkHealth();
    fanController.loop();
    scheduleManager.loop();
    statusIndicator.update();
    
    // Always update alarm system every loop iteration (for buzzer pattern timing)
    // When security enabled: use sensor data; when disabled: no sensor triggers (but manual SOS still works)
    if (securityEnabled) {
        // Only trigger alarms if security has been armed for at least 3 seconds (grace period)
        bool allowAlarmTrigger = (securityArmedAt == 0 || (millis() - securityArmedAt) >= 3000);
        if (allowAlarmTrigger) {
            alarmSystem.update(sensorData.motionDetected, sensorData.distance, sensorData.temperature);
        } else {
            // During grace period, update alarm system but don't allow new triggers
            alarmSystem.update(false, 0.0f, sensorData.temperature);
        }
    } else {
        // Security disabled - no sensor triggers, but manual SOS alarms still work
        alarmSystem.update(false, 0.0f, sensorData.temperature);
    }
    
    // Update LCD display
    lcdDisplay.update();
    // CRITICAL: Continuously update connection status to ensure LCD reflects current state
    // This ensures that if connection state changes outside of callback, LCD is still updated
    // The LCD will maintain disconnected state until isConnected() returns true
    bool currentConnectionState = bleManager.isConnected();
    lcdDisplay.setConnectionStatus(currentConnectionState);

    // Read sensors periodically
    if (currentMillis - lastSensorRead >= SENSOR_READ_INTERVAL) {
        lastSensorRead = currentMillis;
        readSensors();

        if (autoMode) {
            updateAutoMode();
        }

        checkMotionTimeout();
    }

    // Send BLE updates (reduced frequency to prevent connection drops)
    // Only send if connected and enough time has passed
    if (bleManager.isConnected() && 
        (currentMillis - lastBLEUpdate >= BLE_UPDATE_INTERVAL)) {
        lastBLEUpdate = currentMillis;
        
        // Only send if we have subscribers (client has subscribed to notifications)
        bleManager.sendSensorData(
            sensorData.temperature,
            sensorData.humidity,
            sensorData.heatIndex,
            currentFanSpeed,
            currentLEDBrightness,
            sensorData.motionDetected,
            sensorData.distance,
            securityEnabled
        );
    }

    updateStatusIndicatorState();
    delay(10);
}

// ============================================================================
// LCD SETUP
// ============================================================================
void setupLCD() {
    lcdDisplay.begin(LCD_I2C_ADDRESS, LCD_COLS, LCD_ROWS);
}

// ============================================================================
// BLE SETUP
// ============================================================================
void setupBLE() {
    // Small delay to ensure other systems are stable before BLE init
    delay(200);
    
    if (!bleManager.begin()) {
        DEBUG_PRINTLN("BLE init failed!");
        return;
    }
    
    // Additional delay after BLE init to ensure stack is ready
    delay(100);

    bleManager.onFanSpeedChange(onFanSpeedChanged);
    bleManager.onLEDBrightnessChange(onLEDBrightnessChanged);
    bleManager.onAutoModeChange(onAutoModeChanged);
    
    lcdDisplay.setConnectionStatus(false);
}

// ============================================================================
// PIN SETUP
// ============================================================================
void setupPins() {
    pinMode(PIR_PIN, INPUT);
    pinMode(ULTRASONIC_ECHO_PIN, INPUT);
    pinMode(STATUS_LED_PIN, OUTPUT);
    pinMode(ULTRASONIC_TRIG_PIN, OUTPUT);
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(FAN_PIN, OUTPUT);
    pinMode(GREEN_LED_1_PIN, OUTPUT);
    pinMode(GREEN_LED_2_PIN, OUTPUT);
    pinMode(GREEN_LED_3_PIN, OUTPUT);
    digitalWrite(STATUS_LED_PIN, LOW);
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
    digitalWrite(FAN_PIN, LOW);
    digitalWrite(GREEN_LED_1_PIN, HIGH);
    digitalWrite(GREEN_LED_2_PIN, HIGH);
    digitalWrite(GREEN_LED_3_PIN, HIGH);
}

// ============================================================================
// PWM SETUP
// ============================================================================
void setupPWM() {
    fanController.begin(FAN_PIN, FAN_PWM_CHANNEL, FAN_PWM_FREQ, FAN_PWM_RESOLUTION);
    ledcSetup(GREEN_LED_PWM_CHANNEL_1, GREEN_LED_PWM_FREQ, GREEN_LED_PWM_RESOLUTION);
    ledcSetup(GREEN_LED_PWM_CHANNEL_2, GREEN_LED_PWM_FREQ, GREEN_LED_PWM_RESOLUTION);
    ledcSetup(GREEN_LED_PWM_CHANNEL_3, GREEN_LED_PWM_FREQ, GREEN_LED_PWM_RESOLUTION);
    ledcAttachPin(GREEN_LED_1_PIN, GREEN_LED_PWM_CHANNEL_1);
    ledcAttachPin(GREEN_LED_2_PIN, GREEN_LED_PWM_CHANNEL_2);
    ledcAttachPin(GREEN_LED_3_PIN, GREEN_LED_PWM_CHANNEL_3);
    ledcWrite(GREEN_LED_PWM_CHANNEL_1, 255);
    ledcWrite(GREEN_LED_PWM_CHANNEL_2, 255);
    ledcWrite(GREEN_LED_PWM_CHANNEL_3, 255);
}

// ============================================================================
// SENSOR SETUP
// ============================================================================
void setupSensors() {
    dhtSensor.begin();
    Wire.begin(RTC_SDA_PIN, RTC_SCL_PIN);
    sensorData.temperature = 0.0f;
    sensorData.humidity = 0.0f;
    sensorData.heatIndex = 0.0f;
    sensorData.motionDetected = false;
    sensorData.distance = 0.0f;
    sensorData.lastMotionTime = 0;
}

// ============================================================================
// READ SENSORS
// ============================================================================
void readSensors() {
    EnvironmentalReading env = dhtSensor.read();

    if (env.valid) {
            sensorData.temperature = env.temperature;
            sensorData.humidity = env.humidity;
            sensorData.heatIndex = env.heatIndex;
        }

    // Only read motion and ultrasonic sensors when security is enabled
    if (securityEnabled) {
        bool motion = digitalRead(PIR_PIN);
        // Only set motion detected if PIR pin is HIGH (motion detected)
        // Clear motion if PIR pin is LOW (no motion)
        if (motion) {
            if (!sensorData.motionDetected) {
                sensorData.motionDetected = true;
                sensorData.lastMotionTime = millis();
            }
        } else {
            // No motion detected - clear the flag
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
        } else {
            sensorData.distance = 0.0f;
        }

        // Sensor data updated - alarm system will be updated in main loop
    } else {
        // Security disabled - turn off motion detection and clear sensors
        sensorData.motionDetected = false;
        sensorData.distance = 0.0f;
        // Alarm system will be updated in main loop (for manual SOS alarms)
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

    if (enabled) {
        // Record when security was armed (for grace period to prevent immediate alarms)
        securityArmedAt = millis();
        // Clear any existing alarm state when arming
        if (alarmSystem.isActive() && !alarmSystem.isManualAlarmLatched() && !alarmSystem.isManualAlarmActive()) {
            alarmSystem.silence();
        }
    } else {
        // When disabling security, only silence security alarms, not manual SOS alarms
        if (alarmSystem.isActive() && !alarmSystem.isManualAlarmLatched() && !alarmSystem.isManualAlarmActive()) {
            alarmSystem.silence();
        }
        securityArmedAt = 0;
    }

    sendImmediateStatus();
    updateStatusIndicatorState();
}

void triggerAlarm(uint16_t durationMs) {
    alarmSystem.triggerManualAlarm(durationMs);
    sendImmediateStatus();
}

void handleBleConnectionChanged(bool connected) {
    // CRITICAL: Update LCD immediately when connection state changes
    // This ensures LCD shows disconnected state immediately and maintains it until reconnection
    lcdDisplay.setConnectionStatus(connected);
    updateStatusIndicatorState();

    if (connected) {
        lastBleHealthLog = millis();
        pulseStatusLed(3, 80, 80);
        flashStatusIndicator(true);
        sendImmediateStatus();
        DEBUG_PRINTLN("BLE: Connected - LCD updated to CONNECTED state");
    } else {
        pulseStatusLed(2, 50, 100);
        flashStatusIndicator(false);
        lastBleHealthLog = 0;
        DEBUG_PRINTLN("BLE: Disconnected - LCD updated to DISCONNECTED state");
        // Ensure LCD shows disconnected state immediately
        // The LCD will maintain this state until setConnectionStatus(true) is called on reconnection
    }
}

void monitorBleLinkHealth() {
    if (!bleManager.isConnected()) {
        lastBleHealthLog = 0;
        bleManager.ensureAdvertising();
        return;
    }

    unsigned long now = millis();
    if (now - lastBleHealthLog >= BLEServiceManager::HEARTBEAT_INTERVAL_MS) {
        sendImmediateStatus();
        lastBleHealthLog = now;
    }
}

void handleSerialInput() {
    while (Serial.available() > 0) {
        char incoming = Serial.read();
        if (incoming == '\r') {
            continue;
        }

        if (incoming == '\n') {
            serialCommandBuffer.trim();
            if (serialCommandBuffer.length() > 0) {
                processSerialCommand(serialCommandBuffer);
            }
            serialCommandBuffer = "";
        } else if (serialCommandBuffer.length() < SERIAL_CMD_MAX_LEN - 1) {
            serialCommandBuffer += incoming;
        }
    }
}

void processSerialCommand(const String& rawCommand) {
    String command = rawCommand;
    command.trim();
    if (command.isEmpty()) {
        return;
    }

    String upper = command;
    upper.toUpperCase();

    DEBUG_PRINTF("[SERIAL CMD] %s\n", command.c_str());

    if (upper == "HELP" || upper == "?") {
        printSerialHelp();
        return;
    }

    if (upper.startsWith("FANP ")) {
        int percent = command.substring(5).toInt();
        percent = constrain(percent, 0, 100);
        uint8_t value = percentToByte(percent);
        setFanSpeed(value);
        Serial.printf("Fan speed set to %d%% (%d)\n", percent, value);
        return;
    }

    if (upper.startsWith("FAN ")) {
        int raw = command.substring(4).toInt();
        uint8_t value = clampToByte(raw);
        setFanSpeed(value);
        Serial.printf("Fan speed set to raw value %d\n", value);
        return;
    }

    if (upper.startsWith("LEDP ")) {
        int percent = command.substring(5).toInt();
        percent = constrain(percent, 0, 100);
        uint8_t value = percentToByte(percent);
        setLEDBrightness(value);
        Serial.printf("LED brightness set to %d%% (%d)\n", percent, value);
        return;
    }

    if (upper.startsWith("LED ")) {
        int raw = command.substring(4).toInt();
        uint8_t value = clampToByte(raw);
        setLEDBrightness(value);
        Serial.printf("LED brightness set to raw value %d\n", value);
        return;
    }

    if (upper.startsWith("AUTO ")) {
        String arg = upper.substring(5);
        arg.trim();
        bool enable = (arg == "ON" || arg == "1" || arg == "TRUE");
        autoMode = enable;
        storage.saveAutoMode(enable);
        Serial.printf("Auto mode %s\n", enable ? "ENABLED" : "DISABLED");
        sendImmediateStatus();
        return;
    }

    if (upper.startsWith("SECURITY ")) {
        String arg = upper.substring(9);
        arg.trim();
        bool enable = (arg == "ON" || arg == "1" || arg == "TRUE" || arg == "ARM");
        bool previousState = securityEnabled;
        setSecurityEnabled(enable);
        if (previousState != enable) {
            Serial.printf("Security %s\n", enable ? "ARMED" : "DISARMED");
        } else {
            Serial.printf("Security already %s\n", enable ? "ARMED" : "DISARMED");
        }
        return;
    }

    if (upper.startsWith("BUZZER ")) {
        String arg = upper.substring(7);
        arg.trim();
        bool enable = (arg == "ON" || arg == "1" || arg == "TRUE" || arg == "START");
        if (enable) {
            alarmSystem.enableManualAlarm(true);
            Serial.println("Buzzer latched ON (smoke alarm pattern). Use BUZZER OFF to silence.");
        } else {
            alarmSystem.enableManualAlarm(false);
            Serial.println("Buzzer silenced.");
        }
        sendImmediateStatus();
        return;
    }

    if (upper == "STATUS") {
        sendImmediateStatus();
        Serial.println("Status broadcast triggered.");
        return;
    }

    if (upper.startsWith("SOS ") || upper.startsWith("ALARM ")) {
        int duration = upper.startsWith("SOS ") ? upper.substring(4).toInt()
                                               : upper.substring(6).toInt();
        duration = constrain(duration, 200, 60000);
        triggerAlarm(duration);
        Serial.printf("Alarm triggered for %d ms\n", duration);
        return;
    }

    if (upper == "INFO") {
        Serial.printf("Temp: %.1fC, Humidity: %.1f%%, Fan: %d, LED: %d, Auto: %s, Security: %s\n",
            sensorData.temperature,
            sensorData.humidity,
            currentFanSpeed,
            currentLEDBrightness,
            autoMode ? "ON" : "OFF",
            securityEnabled ? "ARMED" : "DISARMED");
        return;
    }

    if (upper == "RESET" || upper == "FACTORY_RESET" || upper == "CLEAR") {
        Serial.println("Factory reset requested. This will clear all stored settings.");
        Serial.println("Type 'RESET CONFIRM' within 5 seconds to proceed...");
        
        // Wait for confirmation
        unsigned long startTime = millis();
        String confirmBuffer = "";
        bool confirmed = false;
        
        while (millis() - startTime < 5000) {
            if (Serial.available() > 0) {
                char c = Serial.read();
                if (c == '\n' || c == '\r') {
                    confirmBuffer.trim();
                    confirmBuffer.toUpperCase();
                    if (confirmBuffer == "RESET CONFIRM" || confirmBuffer == "CONFIRM") {
                        confirmed = true;
                        break;
                    }
                    confirmBuffer = "";
                } else if (c != '\r') {
                    if (confirmBuffer.length() < 50) {
                        confirmBuffer += c;
                    }
                }
            }
            delay(10);
        }
        
        if (confirmed) {
            performFactoryReset();
        } else {
            Serial.println("Factory reset cancelled (no confirmation received).");
        }
        return;
    }

    Serial.println("Unknown command. Type HELP to list available commands.");
}

void printSerialHelp() {
    Serial.println(F("SmartSync Serial Command Reference"));
    Serial.println(F("---------------------------------------------------"));
    Serial.println(F("HELP                 - Show this guide"));
    Serial.println(F("STATUS               - Push current telemetry over BLE"));
    Serial.println(F("INFO                 - Print local sensor snapshot"));
    Serial.println(F("FAN <0-255>          - Set fan speed (raw value)"));
    Serial.println(F("FANP <0-100>         - Set fan speed (percent)"));
    Serial.println(F("LED <0-255>          - Set LED brightness (raw value)"));
    Serial.println(F("LEDP <0-100>         - Set LED brightness (percent)"));
    Serial.println(F("AUTO <ON|OFF>        - Toggle adaptive auto mode"));
    Serial.println(F("SECURITY <ON|OFF>    - Arm or disarm security system"));
    Serial.println(F("BUZZER <ON|OFF>      - Latch smoke-alarm buzzer pattern on or off"));
    Serial.println(F("SOS <ms>             - Trigger alarm buzzer for duration"));
    Serial.println(F("ALARM <ms>           - Alias for SOS"));
    Serial.println(F("RESET                - Factory reset (requires confirmation)"));
    Serial.println(F("---------------------------------------------------"));
    Serial.println(F("Commands are case-insensitive. End each line with ENTER."));
}

uint8_t clampToByte(int value) {
    return static_cast<uint8_t>(constrain(value, 0, 255));
}

uint8_t percentToByte(int percent) {
    percent = constrain(percent, 0, 100);
    return static_cast<uint8_t>((percent * 255) / 100);
}

// ============================================================================
// FAN CONTROL
// ============================================================================
void setFanSpeed(uint8_t speed) {
    currentFanSpeed = speed;
    fanController.smoothTo(speed);
    storage.saveFanSpeed(speed);
    sendImmediateStatus();
}

// ============================================================================
// LED CONTROL
// ============================================================================
// Controls all 3 green LEDs simultaneously
// LEDs are common cathode: LOW = ON, HIGH = OFF
// PWM is inverted: 255 = OFF, 0 = ON (full brightness)
void setLEDBrightness(uint8_t brightness) {
    currentLEDBrightness = brightness;
    // Invert brightness for common cathode LEDs (255 - brightness)
    // When brightness = 0 (off), write 255 (HIGH = OFF)
    // When brightness = 255 (full), write 0 (LOW = ON)
    uint8_t invertedBrightness = 255 - brightness;
    ledcWrite(GREEN_LED_PWM_CHANNEL_1, invertedBrightness);
    ledcWrite(GREEN_LED_PWM_CHANNEL_2, invertedBrightness);
    ledcWrite(GREEN_LED_PWM_CHANNEL_3, invertedBrightness);
    storage.saveLedBrightness(brightness);
    sendImmediateStatus();
}

// ============================================================================
// MOTION TIMEOUT CHECK
// ============================================================================
void checkMotionTimeout() {
    if (sensorData.lastMotionTime > 0) {
        unsigned long elapsed = millis() - sensorData.lastMotionTime;
        // Motion timeout check (silent)
    }
}

void handleScheduleExecution(const ScheduleEntry& entry) {
    setFanSpeed(entry.fanSpeed);
    setLEDBrightness(entry.ledBrightness);
    sendImmediateStatus();
}

void sendImmediateStatus() {
    bleManager.sendSensorData(
        sensorData.temperature,
        sensorData.humidity,
        sensorData.heatIndex,
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

        if (entry.id > 0) {
            scheduleManager.update(entry);
        } else {
            scheduleManager.add(entry);
        }
        return;
    }

    if (strcmp(cmd, CMD_DELETE_SCHEDULE) == 0) {
        uint8_t id = data["id"] | 0;
        scheduleManager.remove(id);
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
        DEBUG_PRINTF("Security: %s\n", enabled ? "ARMED" : "DISARMED");
        return;
    }

    if (strcmp(cmd, CMD_SOS) == 0) {
        uint16_t duration = data["duration"] | data["value"] | 5000;
        triggerAlarm(duration);
        DEBUG_PRINTLN("SOS triggered");
        return;
    }

    if (strcmp(cmd, CMD_SET_HUB_CONFIG) == 0) {
        // Update hub configuration (room name and primary status)
        const char* roomName = data["room_name"] | data["roomName"] | "";
        bool isPrimary = data["is_primary"] | data["isPrimary"] | false;
        
        if (strlen(roomName) > 0) {
            storage.saveRoomName(roomName);
            lcdDisplay.setRoomName(roomName);
            DEBUG_PRINTF("Room name set to: %s\n", roomName);
        }
        
        storage.saveIsPrimaryHub(isPrimary);
        lcdDisplay.setIsPrimaryHub(isPrimary);
        DEBUG_PRINTF("Primary hub status: %s\n", isPrimary ? "YES" : "NO");
        
        return;
    }

    if (strcmp(cmd, CMD_FACTORY_RESET) == 0) {
        // Factory reset via BLE command
        bool confirm = data["confirm"] | data["value"] | false;
        if (confirm) {
            DEBUG_PRINTLN("Factory reset requested via BLE");
            performFactoryReset();
        } else {
            DEBUG_PRINTLN("Factory reset requires confirmation (set confirm: true)");
        }
        return;
    }

}

void updateStatusIndicatorState() {
    if (!statusIndicator.isInitialized()) {
        return;
    }

    // Only show ALERT if there's an actual active alarm (security-triggered or manual SOS)
    // Not just when security is armed - only when an alarm condition is detected
    if (alarmSystem.isActive()) {
        statusIndicator.setMode(RGBStatusLED::Mode::ALERT);
        return;
    }

    if (bleManager.isConnected()) {
        statusIndicator.setMode(RGBStatusLED::Mode::CONNECTED);
    } else {
        statusIndicator.setMode(RGBStatusLED::Mode::SCANNING);
    }
}

void printBleWelcomeBanner() {
#if DEBUG_SERIAL
    Serial.println();
    Serial.println(F("╔════════════════════════════════════╗"));
    Serial.println(F("║      SmartSync BLE Connected       ║"));
    Serial.println(F("╚════════════════════════════════════╝"));
    Serial.println(F("Client ready. Mobile app now receiving live data."));
    Serial.println(F("Type HELP over serial for local commands."));
#endif
}

void pulseStatusLed(uint8_t pulses, uint16_t onMs, uint16_t offMs) {
    for (uint8_t i = 0; i < pulses; ++i) {
        digitalWrite(STATUS_LED_PIN, HIGH);
        delay(onMs);
        digitalWrite(STATUS_LED_PIN, LOW);
        delay(offMs);
    }
}

void flashStatusIndicator(bool connected) {
    if (!statusIndicator.isInitialized()) {
        return;
    }
    const uint8_t pulses = connected ? 3 : 2;
    const uint8_t r = connected ? 0 : 255;
    const uint8_t g = connected ? 120 : 80;
    const uint8_t b = connected ? 255 : 0;
    for (uint8_t i = 0; i < pulses; ++i) {
        statusIndicator.flash(r, g, b, 90);
        delay(40);
    }
}

void performFactoryReset() {
    Serial.println("========================================");
    Serial.println("FACTORY RESET IN PROGRESS...");
    Serial.println("========================================");
    
    // Turn off all outputs first
    setFanSpeed(0);
    setLEDBrightness(0);
    alarmSystem.silence();
    alarmSystem.enableManualAlarm(false);
    
    // Clear all stored preferences
    bool resetSuccess = storage.factoryReset();
    
    if (resetSuccess) {
        Serial.println("✓ Preferences cleared successfully");
    } else {
        Serial.println("✗ Error clearing preferences");
    }
    
    // Reset all state variables to defaults
    autoMode = false;
    securityEnabled = false;
    securityArmedAt = 0;
    currentFanSpeed = 0;
    currentLEDBrightness = 0;
    
    // Clear schedules
    scheduleManager.clear();
    
    // Clear room name and primary hub status
    storage.saveRoomName("");
    storage.saveIsPrimaryHub(false);
    lcdDisplay.setRoomName("");
    lcdDisplay.setIsPrimaryHub(false);
    
    // Reset sensor data
    sensorData.temperature = 0.0f;
    sensorData.humidity = 0.0f;
    sensorData.heatIndex = 0.0f;
    sensorData.motionDetected = false;
    sensorData.distance = 0.0f;
    sensorData.lastMotionTime = 0;
    
    // Visual confirmation - flash status LED
    for (int i = 0; i < 5; i++) {
        digitalWrite(STATUS_LED_PIN, HIGH);
        delay(100);
        digitalWrite(STATUS_LED_PIN, LOW);
        delay(100);
    }
    
    // Flash RGB indicator (red flash)
    if (statusIndicator.isInitialized()) {
        statusIndicator.flash(255, 0, 0, 200);
    }
    
    Serial.println("========================================");
    Serial.println("FACTORY RESET COMPLETE");
    Serial.println("All settings have been cleared.");
    Serial.println("Device will restart in 3 seconds...");
    Serial.println("========================================");
    
    delay(3000);
    
    // Restart ESP32
    ESP.restart();
}