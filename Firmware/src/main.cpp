#include <Arduino.h>
#include "hardware.h"
#include "ble_server.h"
#include "adaptive.h"

void setup(){
  Serial.begin(115200);
  hw_init();
  ble_setup();
  Serial.println("SmartSync firmware (Week1) ready");
}

void loop(){
  // Minimal: blink or process sensors later.
  delay(100);
}
