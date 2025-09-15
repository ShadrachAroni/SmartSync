#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include "ble_server.h"
#include "hardware.h"

#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHAR_WRITE_UUID     "abcd0001-1234-1234-1234-1234567890ab"
#define CHAR_NOTIFY_UUID    "abcd0002-1234-1234-1234-1234567890ab"

BLECharacteristic *pWriteCharacteristic;
BLECharacteristic *pNotifyCharacteristic;

class WriteCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    std::string rx = pChar->getValue();
    if(rx.length()>0){
      String cmd = String(rx.c_str());
      parseCommand(cmd);
    }
  }
};

void ble_setup(){
  BLEDevice::init("SmartSync");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pWriteCharacteristic = pService->createCharacteristic(
                         CHAR_WRITE_UUID,
                         BLECharacteristic::PROPERTY_WRITE
                       );
  pWriteCharacteristic->setCallbacks(new WriteCallbacks());

  pNotifyCharacteristic = pService->createCharacteristic(
                          CHAR_NOTIFY_UUID,
                          BLECharacteristic::PROPERTY_NOTIFY
                         );

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
}

void ble_notify(const String &msg){
  if(pNotifyCharacteristic){
    pNotifyCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
    pNotifyCharacteristic->notify();
  }
}

// simple parser (implement more robust parsing later)
void parseCommand(const String &cmd){
  if(cmd.startsWith("B1:ON")) setRelay(RELAY_BULB1_PIN, true);
  else if(cmd.startsWith("B1:OFF")) setRelay(RELAY_BULB1_PIN, false);
  else if(cmd.startsWith("B2:ON")) setRelay(RELAY_BULB2_PIN, true);
  else if(cmd.startsWith("B2:OFF")) setRelay(RELAY_BULB2_PIN, false);
  else if(cmd.startsWith("FAN:ON")) { setRelay(RELAY_FAN_PIN, true); /* log for adaptive */ }
  else if(cmd.startsWith("FAN:OFF")) { setRelay(RELAY_FAN_PIN, false); /* log */ }
  // FAN:PWM: later
}
