#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include "ble_server.h"
#include "adaptive.h"
#include "hardware.h"

#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHAR_WRITE_UUID     "abcd0001-1234-1234-1234-1234567890ab"
#define CHAR_NOTIFY_UUID    "abcd0002-1234-1234-1234-1234567890ab"

BLECharacteristic *pWriteCharacteristic = nullptr;
BLECharacteristic *pNotifyCharacteristic = nullptr;

class WriteCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    std::string rx = pChar->getValue();
    if(rx.length()>0) {
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

void ble_notify(const String &msg) {
  if(pNotifyCharacteristic) {
    pNotifyCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
    pNotifyCharacteristic->notify();
  }
}

// parse trusted simple commands; includes SIMLOG for seeding adaptive logs.
void parseCommand(const String &cmd){
  // trim whitespace
  String c = cmd;
  c.trim();
  if(c == "") return;

  if(c == "B1:ON") setRelay(RELAY_BULB1_PIN, true);
  else if(c == "B1:OFF") setRelay(RELAY_BULB1_PIN, false);
  else if(c == "B2:ON") setRelay(RELAY_BULB2_PIN, true);
  else if(c == "B2:OFF") setRelay(RELAY_BULB2_PIN, false);
  else if(c == "FAN:ON") {
    setRelay(RELAY_FAN_PIN, true);
    log_manual_toggle(0, minuteOfDay()); // applianceId 0 = fan (example)
  }
  else if(c == "FAN:OFF") {
    setRelay(RELAY_FAN_PIN, false);
    log_manual_toggle(0, minuteOfDay());
  }
  else if(c.startsWith("FAN:PWM:")) {
    int v = c.substring(8).toInt();
    setFanPWM(constrain(v,0,255));
  }
  // SIMLOG to seed learning quickly: SIMLOG:APPL:HH:MM,HH:MM,...
  else if(c.startsWith("SIMLOG:")) {
    handleSimLog(c); // implemented in adaptive.cpp
  }
  else if(c.startsWith("SUGGEST:ACCEPT:")) {
    // forward to adaptive module
    String appl = c.substring(strlen("SUGGEST:ACCEPT:"));
    handleSuggestAccept(appl);
  }
  // add more commands as needed
}
