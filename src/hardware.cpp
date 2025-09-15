#include "hardware.h"

void hw_init(){
  pinMode(RELAY_BULB1_PIN, OUTPUT);
  pinMode(RELAY_BULB2_PIN, OUTPUT);
  pinMode(RELAY_FAN_PIN, OUTPUT);
  pinMode(FAN_PWM_PIN, OUTPUT);
  pinMode(PIR_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  digitalWrite(RELAY_BULB1_PIN, LOW);
  digitalWrite(RELAY_BULB2_PIN, LOW);
  digitalWrite(RELAY_FAN_PIN, LOW);
  analogWrite(FAN_PWM_PIN, 0); // if using PWM on the pin
}

void setRelay(uint8_t pin, bool state){
  digitalWrite(pin, state ? HIGH : LOW);
}

void setFanPWM(uint8_t value){
  // ESP32 uses ledcWrite for PWM, implement in main for simplicity
  analogWrite(FAN_PWM_PIN, value); // If using Arduino-ESP32 compatibility
}
