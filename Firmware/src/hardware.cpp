#include "hardware.h"

void hw_init() {
  pinMode(RELAY_BULB1_PIN, OUTPUT);
  pinMode(RELAY_BULB2_PIN, OUTPUT);
  pinMode(RELAY_FAN_PIN, OUTPUT);
  pinMode(PIR_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  digitalWrite(RELAY_BULB1_PIN, LOW);
  digitalWrite(RELAY_BULB2_PIN, LOW);
  digitalWrite(RELAY_FAN_PIN, LOW);
  // setup PWM for fan (ESP32)
  ledcSetup(FAN_PWM_CH, FAN_PWM_FREQ, FAN_PWM_RES);
  ledcAttachPin(FAN_PWM_PIN, FAN_PWM_CH);
  ledcWrite(FAN_PWM_CH, 0);
}

void setRelay(uint8_t pin, bool state) {
  digitalWrite(pin, state ? HIGH : LOW);
}

void setFanPWM(uint8_t value) {
  ledcWrite(FAN_PWM_CH, value);
}

uint16_t minuteOfDay() {
  time_t now = time(nullptr);
  struct tm *tm = localtime(&now);
  return (uint16_t)(tm->tm_hour * 60 + tm->tm_min);
}
