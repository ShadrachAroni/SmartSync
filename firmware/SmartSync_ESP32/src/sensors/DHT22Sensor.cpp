#include "DHT22Sensor.h"

DHT22Sensor::DHT22Sensor(uint8_t pin, uint8_t type) : _dht(pin, type) {}

void DHT22Sensor::begin() {
    _dht.begin();
    _lastReading = {};
}

EnvironmentalReading DHT22Sensor::read() {
    EnvironmentalReading reading;
    reading.temperature = _dht.readTemperature();
    reading.humidity = _dht.readHumidity();

    if (!isnan(reading.temperature) && !isnan(reading.humidity)) {
        reading.heatIndex = _dht.computeHeatIndex(reading.temperature, reading.humidity, false);
        reading.valid = true;
        _lastReading = reading;
    } else {
        reading = _lastReading;
        reading.valid = false;
    }

    return reading;
}

