#include <Arduino.h>
#include "hardware.h"
#include "ble_server.h"

void setup(){
  Serial.begin(115200);
  hw_init();
  ble_setup();
  Serial.println("SmartSync firmware started");
}

void loop(){
  // main loop: read sensors, run scheduler, etc.
  delay(100);
}
