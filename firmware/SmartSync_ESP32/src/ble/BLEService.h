#ifndef BLE_SERVICE_H
#define BLE_SERVICE_H

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include "../../include/config.h"

class BLEServiceManager {
public:
    static constexpr uint32_t HEARTBEAT_INTERVAL_MS = 30000;
    static constexpr uint32_t ACTIVITY_TIMEOUT_MS = 60000;
    static constexpr uint32_t STALE_CONNECTION_TIMEOUT_MS = 120000;
    static constexpr uint32_t ADV_RECOVERY_INTERVAL_MS = 4000;
    static constexpr uint32_t STACK_RECOVERY_BACKOFF_MS = 15000;
    static constexpr uint8_t MAX_ADV_RECOVERY_ATTEMPTS = 3;

    BLEServiceManager();
    ~BLEServiceManager();
    
    bool begin();
    void update();
    bool isConnected();
    unsigned long getLastActivity() const { return lastActivityMillis; }
    void sendSensorData(float temp, float humidity, float heatIndex, int fanSpeed, 
                       int ledBright, bool motion, float distance,
                       bool securityArmed);
    void onConnectionChange(void (*callback)(bool connected));
    void ensureAdvertising();
    
    // Callback setters
    void onFanSpeedChange(void (*callback)(uint8_t));
    void onLEDBrightnessChange(void (*callback)(uint8_t));
    void onAutoModeChange(void (*callback)(bool));
    void onCommand(void (*callback)(const char*, JsonVariantConst payload));
    
private:
    NimBLEServer* pServer;
    NimBLEService* pService;
    NimBLECharacteristic* pTxCharacteristic;
    NimBLECharacteristic* pRxCharacteristic;
    NimBLEAdvertising* pAdvertising;
    
    bool deviceConnected;
    bool oldDeviceConnected;
    unsigned long lastHeartbeatSent;
    unsigned long lastActivityMillis;
    unsigned long lastConnectionEvent;
    unsigned long lastAdvertisingCheck;
    unsigned long lastStackRecovery;
    uint8_t failedAdvRestarts;
    
    void (*connectionStateCallback)(bool);
    
    // Callbacks
    void (*fanSpeedCallback)(uint8_t);
    void (*ledBrightnessCallback)(uint8_t);
    void (*autoModeCallback)(bool);
    void (*customCommandCallback)(const char*, JsonVariantConst payload);
    
    void recordActivity();
    void sendHeartbeat();
    void sendConnectionEvent(bool connected);
    void handleConnectionChange(bool connected);
    void forceDisconnectStaleClient();
    void restartAdvertising(bool forceStop = false);
    void recoverBleStack();
    bool hasSubscribers() const;
    void sendAck(const char* cmd, bool success, const char* message = nullptr);
    
    void handleCommand(String command);
    String createSensorJSON(float temp, float humidity, float heatIndex, int fanSpeed, 
                           int ledBright, bool motion, float distance,
                           bool securityArmed);

    friend class ServerCallbacks;
    friend class CharacteristicCallbacks;
};

#endif // BLE_SERVICE_H