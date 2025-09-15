#pragma once
#include <Arduino.h>

#define RELAY_BULB1_PIN 16
#define RELAY_BULB2_PIN 17
#define RELAY_FAN_PIN   18
#define FAN_PWM_CH      0   // ledc channel for ESP32 PWM
#define FAN_PWM_FREQ    5000
#define FAN_PWM_RES     8   // 8-bit resolution (0-255)
#define FAN_PWM_PIN     19
#define PIR_PIN         4
#define BUZZER_PIN      2

void hw_init();
void setRelay(uint8_t pin, bool state);
void setFanPWM(uint8_t value);
uint16_t minuteOfDay();
