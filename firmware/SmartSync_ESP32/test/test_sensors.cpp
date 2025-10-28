// Add to test/test_sensors.cpp
#include <Arduino.h>
#include <unity.h>

void test_dht22_reading() {
    // Test that temperature reading is within valid range
    float temp = dht.readTemperature();
    TEST_ASSERT_TRUE(!isnan(temp));
    TEST_ASSERT_TRUE(temp >= -40 && temp <= 80);
}

void test_pir_sensor() {
    // Test PIR sensor input
    pinMode(PIR_PIN, INPUT);
    int value = digitalRead(PIR_PIN);
    TEST_ASSERT_TRUE(value == HIGH || value == LOW);
}

void setup() {
    UNITY_BEGIN();
    RUN_TEST(test_dht22_reading);
    RUN_TEST(test_pir_sensor);
    UNITY_END();
}

void loop() {}