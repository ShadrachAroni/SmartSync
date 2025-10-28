#ifndef BLE_SERVICE_H
#define BLE_SERVICE_H

#include <Arduino.h>
#include <NimBLEDevice.h>
#include "../../include/config.h"

class BLEServiceManager {
public:
    BLEServiceManager();
    ~BLEServiceManager();
    
    bool begin();
    void update();
    bool isConnected();
    void sendSensorData(float temp, float humidity, int fanSpeed, 
                       int ledBright, bool motion, float distance);
    
    // Callback setters
    void onFanSpeedChange(void (*callback)(uint8_t));
    void onLEDBrightnessChange(void (*callback)(uint8_t));
    void onAutoModeChange(void (*callback)(bool));
    
private:
    NimBLEServer* pServer;
    NimBLEService* pService;
    NimBLECharacteristic* pTxCharacteristic;
    NimBLECharacteristic* pRxCharacteristic;
    
    bool deviceConnected;
    bool oldDeviceConnected;
    
    // Callbacks
    void (*fanSpeedCallback)(uint8_t);
    void (*ledBrightnessCallback)(uint8_t);
    void (*autoModeCallback)(bool);
    
    void handleCommand(String command);
    String createSensorJSON(float temp, float humidity, int fanSpeed, 
                           int ledBright, bool motion, float distance);
};

#endif // BLE_SERVICE_H