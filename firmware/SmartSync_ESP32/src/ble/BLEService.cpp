#include "BLEService.h"
#include <ArduinoJson.h>

// Server callbacks
class ServerCallbacks : public NimBLEServerCallbacks {
public:
    explicit ServerCallbacks(BLEServiceManager* mgr) : manager(mgr) {}
    
    void onConnect(NimBLEServer* pServer) override {
        if (manager) {
            manager->handleConnectionChange(true);
        }
    }
    
    void onDisconnect(NimBLEServer* pServer) override {
        if (manager) {
            manager->handleConnectionChange(false);
        }
        pServer->startAdvertising();
    }
    
private:
    BLEServiceManager* manager;
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
            manager->handleCommand(command);
        }
    }
};

BLEServiceManager::BLEServiceManager() 
    : pServer(nullptr),
      pService(nullptr),
      pTxCharacteristic(nullptr),
      pRxCharacteristic(nullptr),
      pAdvertising(nullptr),
      deviceConnected(false), 
      oldDeviceConnected(false),
      lastHeartbeatSent(0),
      lastActivityMillis(0),
      lastConnectionEvent(0),
      lastAdvertisingCheck(0),
      lastStackRecovery(0),
      failedAdvRestarts(0),
      connectionStateCallback(nullptr),
      fanSpeedCallback(nullptr),
      ledBrightnessCallback(nullptr),
      autoModeCallback(nullptr),
      customCommandCallback(nullptr) {
}

BLEServiceManager::~BLEServiceManager() {
    if (pServer) {
        NimBLEDevice::deinit(true);
    }
}

bool BLEServiceManager::begin() {
    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEDevice::setDeviceName(BLE_DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    NimBLEDevice::setSecurityAuth(false, false, false);
    lastActivityMillis = millis();
    lastConnectionEvent = millis();
    failedAdvRestarts = 0;
    lastAdvertisingCheck = millis();
    
    // Create BLE Server
    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks(this));
    
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
    pAdvertising = NimBLEDevice::getAdvertising();
    
    // Set connection parameters for better compatibility (in units of 1.25ms)
    pAdvertising->setMinInterval(32);  // 40ms
    pAdvertising->setMaxInterval(160); // 200ms
    
    BLEAdvertisementData advData;
    advData.setName(BLE_DEVICE_NAME);
    advData.setCompleteServices(BLEUUID(BLE_SERVICE_UUID));
    pAdvertising->setAdvertisementData(advData);

    BLEAdvertisementData scanData;
    scanData.setName(BLE_DEVICE_NAME);
    scanData.setCompleteServices(BLEUUID(BLE_SERVICE_UUID));
    pAdvertising->setScanResponseData(scanData);
    
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMaxPreferred(0x12);
    
    // Add a small delay to ensure BLE stack is fully ready
    delay(100);
    
    if (!pAdvertising->start()) {
        DEBUG_PRINTLN("BLE advertising failed!");
        failedAdvRestarts++;
        return false;
    }
    
    DEBUG_PRINTLN("BLE advertising started");
    return true;
}

void BLEServiceManager::update() {
    if (!pServer) {
        return;
    }

    bool connectedNow = (pServer->getConnectedCount() > 0);
    if (connectedNow != deviceConnected) {
        handleConnectionChange(connectedNow);
    }

    if (!deviceConnected) {
        ensureAdvertising();
        return;
    }

    unsigned long now = millis();
    
    // Send connection event if we just connected and client is now subscribed
    static unsigned long lastConnectionEventCheck = 0;
    static bool connectionEventSent = false;
    if (deviceConnected && (now - lastConnectionEvent) < 3000) {
        if (hasSubscribers() && !connectionEventSent) {
            sendConnectionEvent(true);
            connectionEventSent = true;
        }
    } else {
        connectionEventSent = false;
    }
    
    if (now - lastHeartbeatSent >= HEARTBEAT_INTERVAL_MS) {
        sendHeartbeat();
    }

    if (now - lastActivityMillis > ACTIVITY_TIMEOUT_MS) {
        sendHeartbeat();
        lastActivityMillis = now;
    }

    if (now - lastActivityMillis > STALE_CONNECTION_TIMEOUT_MS) {
        forceDisconnectStaleClient();
    }
}

bool BLEServiceManager::isConnected() {
    return deviceConnected;
}

void BLEServiceManager::onConnectionChange(void (*callback)(bool connected)) {
    connectionStateCallback = callback;
}

void BLEServiceManager::recordActivity() {
    lastActivityMillis = millis();
}

void BLEServiceManager::sendHeartbeat() {
    if (!deviceConnected || !pTxCharacteristic || !hasSubscribers()) {
        return;
    }

    StaticJsonDocument<160> doc;
    doc["type"] = "heartbeat";
    doc["timestamp"] = millis();
    doc["uptime"] = millis();
    doc["last_activity"] = lastActivityMillis;
    doc["connected"] = deviceConnected;

    String payload;
    serializeJson(doc, payload);
    pTxCharacteristic->setValue(payload.c_str());
    
    // Try to notify, but don't fail if it doesn't work
    try {
        pTxCharacteristic->notify();
    } catch (...) {
        // Ignore notification errors - connection might be dropping
    }
    lastHeartbeatSent = millis();
}

void BLEServiceManager::sendConnectionEvent(bool connected) {
    if (!pTxCharacteristic || !deviceConnected) {
        return;
    }
    
    // Wait a bit for client to subscribe before sending connection event
    if (connected && !hasSubscribers()) {
        return;
    }

    StaticJsonDocument<160> doc;
    doc["type"] = "connection_state";
    doc["connected"] = connected;
    doc["timestamp"] = millis();
    doc["since"] = lastConnectionEvent;

    String payload;
    serializeJson(doc, payload);
    pTxCharacteristic->setValue(payload.c_str());
    
    // Try to notify, but don't fail if it doesn't work
    try {
        pTxCharacteristic->notify();
    } catch (...) {
        // Ignore notification errors
    }
}

void BLEServiceManager::handleConnectionChange(bool connected) {
    if (deviceConnected == connected && oldDeviceConnected == connected) {
        return;
    }

    deviceConnected = connected;
    oldDeviceConnected = connected;

    if (connected) {
        lastConnectionEvent = millis();
        lastHeartbeatSent = 0;
        recordActivity();
        
        // Delay before sending connection event to allow client to subscribe
        // Connection event will be sent when client subscribes (checked in sendConnectionEvent)
        if (connectionStateCallback) {
            connectionStateCallback(true);
        }
        
        // Try to send connection event after a short delay (client needs time to subscribe)
        // This will be retried in update() if client subscribes
    } else {
        lastHeartbeatSent = 0;
        recordActivity();
        if (connectionStateCallback) {
            connectionStateCallback(false);
        }
        ensureAdvertising();
    }
}

void BLEServiceManager::forceDisconnectStaleClient() {
    if (!deviceConnected || !pServer) {
        return;
    }

    std::vector<uint16_t> peers = pServer->getPeerDevices();
    for (uint16_t connId : peers) {
        pServer->disconnect(connId);
    }
    handleConnectionChange(false);
}

void BLEServiceManager::ensureAdvertising() {
    if (deviceConnected || pAdvertising == nullptr) {
        return;
    }

    unsigned long now = millis();
    if (pAdvertising->isAdvertising()) {
        failedAdvRestarts = 0;
        lastAdvertisingCheck = now;
        return;
    }

    if (now - lastAdvertisingCheck < ADV_RECOVERY_INTERVAL_MS) {
        return;
    }

    restartAdvertising();
}

void BLEServiceManager::restartAdvertising(bool forceStop) {
    if (pAdvertising == nullptr) {
        return;
    }

    if (forceStop && pAdvertising->isAdvertising()) {
        pAdvertising->stop();
        delay(10);
    }

    if (pAdvertising->start()) {
        failedAdvRestarts = 0;
    } else {
        failedAdvRestarts++;
        if (failedAdvRestarts >= MAX_ADV_RECOVERY_ATTEMPTS) {
            recoverBleStack();
            return;
        }
    }
    lastAdvertisingCheck = millis();
}

void BLEServiceManager::recoverBleStack() {
    unsigned long now = millis();
    if (now - lastStackRecovery < STACK_RECOVERY_BACKOFF_MS) {
        return;
    }

    lastStackRecovery = now;
    DEBUG_PRINTLN("BLE watchdog: resetting BLE stack");

    deviceConnected = false;
    oldDeviceConnected = false;
    lastHeartbeatSent = 0;

    if (pAdvertising && pAdvertising->isAdvertising()) {
        pAdvertising->stop();
        delay(10);
    }

    NimBLEDevice::deinit(true);
    pServer = nullptr;
    pService = nullptr;
    pTxCharacteristic = nullptr;
    pRxCharacteristic = nullptr;
    pAdvertising = nullptr;
    failedAdvRestarts = 0;
    delay(50);

    begin();
    if (connectionStateCallback) {
        connectionStateCallback(false);
    }
}

void BLEServiceManager::sendSensorData(float temp, float humidity, float heatIndex, int fanSpeed, 
                                       int ledBright, bool motion, float distance,
                                       bool securityArmed) {
    if (!deviceConnected || !pTxCharacteristic || !hasSubscribers()) {
        return;
    }
    
    String json = createSensorJSON(temp, humidity, heatIndex, fanSpeed, ledBright, motion, distance, securityArmed);
    pTxCharacteristic->setValue(json.c_str());
    
    // Try to notify, but don't fail if it doesn't work
    try {
        pTxCharacteristic->notify();
    } catch (...) {
        // Ignore notification errors - connection might be dropping
        return;
    }
    lastHeartbeatSent = millis();
    recordActivity();
}

String BLEServiceManager::createSensorJSON(float temp, float humidity, float heatIndex, int fanSpeed, 
                                           int ledBright, bool motion, float distance,
                                           bool securityArmed) {
    StaticJsonDocument<360> doc;
    
    doc["type"] = "sensor_data";
    doc["temperature"] = temp;
    doc["humidity"] = humidity;
    doc["heat_index"] = heatIndex;
    doc["fan_speed"] = fanSpeed;
    doc["led_brightness"] = ledBright;
    doc["motion"] = motion;
    doc["distance"] = distance;
    doc["timestamp"] = millis();
    doc["security_enabled"] = securityArmed;
    
    String output;
    serializeJson(doc, output);
    return output;
}

bool BLEServiceManager::hasSubscribers() const {
    if (!pTxCharacteristic) {
        return false;
    }
    return pTxCharacteristic->getSubscribedCount() > 0;
}

void BLEServiceManager::sendAck(const char* cmd, bool success, const char* message) {
    if (!deviceConnected || !pTxCharacteristic || !hasSubscribers()) {
        return;
    }

    StaticJsonDocument<160> doc;
    doc["type"] = "ack";
    doc["cmd"] = cmd;
    doc["status"] = success ? "ok" : "error";
    if (message != nullptr) {
        doc["message"] = message;
    }

    String payload;
    serializeJson(doc, payload);
    pTxCharacteristic->setValue(payload.c_str());
    
    // Try to notify, but don't fail if it doesn't work
    try {
        pTxCharacteristic->notify();
    } catch (...) {
        // Ignore notification errors
    }
}

void BLEServiceManager::handleCommand(String command) {
    StaticJsonDocument<256> doc;
    DeserializationError error = deserializeJson(doc, command);
    
    if (error) {
        sendAck("PARSE_ERROR", false, error.c_str());
        return;
    }

    recordActivity();
    
    const char* cmd = doc["cmd"];
    if (cmd == nullptr) {
        sendAck("UNKNOWN", false, "Missing cmd");
        return;
    }

    bool handled = false;
    JsonVariantConst value = doc["value"];
    
    if (strcmp(cmd, "SET_FAN") == 0) {
        uint8_t speed = value.as<uint8_t>();
        if (fanSpeedCallback) {
            fanSpeedCallback(speed);
            handled = true;
        }
    }
    else if (strcmp(cmd, "SET_LED") == 0) {
        uint8_t brightness = value.as<uint8_t>();
        if (ledBrightnessCallback) {
            ledBrightnessCallback(brightness);
            handled = true;
        }
    }
    else if (strcmp(cmd, "SET_AUTO") == 0) {
        bool enabled = value.as<bool>();
        if (autoModeCallback) {
            autoModeCallback(enabled);
            handled = true;
        }
    }
    else if (strcmp(cmd, "GET_STATUS") == 0 || strcmp(cmd, "GET_SENSOR") == 0) {
        if (customCommandCallback) {
            customCommandCallback(cmd, doc.as<JsonVariantConst>());
            handled = true;
        }
    }
    else if (customCommandCallback) {
        customCommandCallback(cmd, doc.as<JsonVariantConst>());
        handled = true;
    }

    sendAck(cmd, handled, handled ? nullptr : "Unsupported command");
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

void BLEServiceManager::onCommand(void (*callback)(const char*, JsonVariantConst payload)) {
    customCommandCallback = callback;
}