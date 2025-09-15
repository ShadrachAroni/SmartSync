#pragma once
#include <Arduino.h>

#define ADAPTIVE_APPLIANCES 4
#define ADAPTIVE_SAMPLES 14

struct AdaptiveLog {
  uint16_t times[ADAPTIVE_SAMPLES];
  uint8_t head;
  uint8_t count;
};

extern AdaptiveLog adaptiveLogs[ADAPTIVE_APPLIANCES];

void log_manual_toggle(uint8_t applianceId, uint16_t minuteOfDay);
void evaluateAdaptive(uint8_t applianceId);
void handleSimLog(const String &cmd);
void handleSuggestAccept(const String &applStr);
