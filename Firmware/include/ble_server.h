#pragma once
#include <Arduino.h>

void ble_setup();
void ble_notify(const String &msg);
void parseCommand(const String &cmd);
