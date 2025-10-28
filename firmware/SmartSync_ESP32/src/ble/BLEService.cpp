#include "BLEService.h"
#include <ArduinoJson.h>

// Server callbacks
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) {
        DEBUG_PRINTLN("Client connected");
    }
    
    void onDisconnect(NimBLEServer* pServer) {
        DEBUG_PRINTLN("Client disconnected");
        // Start advertising again
        pServer->startAdvertising();
    }
};

// Characteristic callbacks
class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
private:
    BLEServiceManager* manager;
    
public:
    CharacteristicCallbacks(BLEServiceManager* mgr) : manager(mgr) {}
    
    void onWrite(NimBLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            String command = String(value.c_str());
            DEBUG_PRINT("Received command: ");
            DEBUG_PRINTLN(command);
            manager->handleCommand(command);
        }
    }
};

BLEServiceManager::BLEServiceManager() 
    : deviceConnected(false), 
      oldDeviceConnected(false),
      fanSpeedCallback(nullptr),
      ledBrightnessCallback(nullptr),
      autoModeCallback(nullptr) {
}

BLEServiceManager::~BLEServiceManager() {
    if (pServer) {
        NimBLEDevice::deinit(true);
    }
}

bool BLEServiceManager::begin() {
    DEBUG_PRINTLN("Initializing BLE...");
    
    // Initialize NimBLE
    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9); // Maximum power
    
    // Create BLE Server
    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    // Create BLE Service
    pService = pServer->createService(BLE_SERVICE_UUID);
    
    // Create TX Characteristic (Server → Client notifications)
    pTxCharacteristic = pService->createCharacteristic(
        BLE_CHARACTERISTIC_UUID_TX,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    
    // Create RX Characteristic (Client → Server writes)
    pRxCharacteristic = pService->createCharacteristic(
        BLE_CHARACTERISTIC_UUID_RX,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    pRxCharacteristic->setCallbacks(new CharacteristicCallbacks(this));
    
    // Start the service
    pService->start();
    
    // Start advertising
    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMaxPreferred(0x12);
    NimBLEDevice::startAdvertising();
    
    DEBUG_PRINTLN("BLE Service started. Waiting for connections...");
    return true;
}

void BLEServiceManager::update() {
    // Check connection status changes
    deviceConnected = (pServer->getConnectedCount() > 0);
    
    if (deviceConnected != oldDeviceConnected) {
        if (deviceConnected) {
            DEBUG_PRINTLN("✓ Device connected");
            digitalWrite(STATUS_LED_PIN, HIGH);
        } else {
            DEBUG_PRINTLN("✗ Device disconnected");
            digitalWrite(STATUS_LED_PIN, LOW);
        }
        oldDeviceConnected = deviceConnected;
    }
}

bool BLEServiceManager::isConnected() {
    return deviceConnected;
}

void BLEServiceManager::sendSensorData(float temp, float humidity, int fanSpeed, 
                                       int ledBright, bool motion, float distance) {
    if (!deviceConnected) return;
    
    String json = createSensorJSON(temp, humidity, fanSpeed, ledBright, motion, distance);
    pTxCharacteristic->setValue(json.c_str());
    pTxCharacteristic->notify();
    
    DEBUG_PRINT("Sent: ");
    DEBUG_PRINTLN(json);
}

String BLEServiceManager::createSensorJSON(float temp, float humidity, int fanSpeed, 
                                           int ledBright, bool motion, float distance) {
    StaticJsonDocument<256> doc;
    
    doc["type"] = "sensor_data";
    doc["temperature"] = temp;
    doc["humidity"] = humidity;
    doc["fan_speed"] = fanSpeed;
    doc["led_brightness"] = ledBright;
    doc["motion"] = motion;
    doc["distance"] = distance;
    doc["timestamp"] = millis();
    
    String output;
    serializeJson(doc, output);
    return output;
}

void BLEServiceManager::handleCommand(String command) {
    StaticJsonDocument<256> doc;
    DeserializationError error = deserializeJson(doc, command);
    
    if (error) {
        DEBUG_PRINT("JSON parse error: ");
        DEBUG_PRINTLN(error.c_str());
        return;
    }
    
    const char* cmd = doc["cmd"];
    
    if (strcmp(cmd, "SET_FAN") == 0) {
        uint8_t speed = doc["value"];
        DEBUG_PRINTF("Setting fan speed to: %d\n", speed);
        if (fanSpeedCallback) {
            fanSpeedCallback(speed);
        }
    }
    else if (strcmp(cmd, "SET_LED") == 0) {
        uint8_t brightness = doc["value"];
        DEBUG_PRINTF("Setting LED brightness to: %d\n", brightness);
        if (ledBrightnessCallback) {
            ledBrightnessCallback(brightness);
        }
    }
    else if (strcmp(cmd, "SET_AUTO") == 0) {
        bool enabled = doc["value"];
        DEBUG_PRINTF("Setting auto mode to: %s\n", enabled ? "ON" : "OFF");
        if (autoModeCallback) {
            autoModeCallback(enabled);
        }
    }
    else if (strcmp(cmd, "GET_STATUS") == 0) {
        // Send immediate status update
        DEBUG_PRINTLN("Status request received");
    }
    else {
        DEBUG_PRINT("Unknown command: ");
        DEBUG_PRINTLN(cmd);
    }
}

void BLEServiceManager::onFanSpeedChange(void (*callback)(uint8_t)) {
    fanSpeedCallback = callback;
}

void BLEServiceManager::onLEDBrightnessChange(void (*callback)(uint8_t)) {
    ledBrightnessCallback = callback;
}

void BLEServiceManager::onAutoModeChange(void (*callback)(bool)) {
    autoModeCallback = callback;
}