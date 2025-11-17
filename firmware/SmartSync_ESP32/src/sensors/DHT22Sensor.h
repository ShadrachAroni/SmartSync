#ifndef DHT22_SENSOR_H
#define DHT22_SENSOR_H

#include <Arduino.h>
#include <DHT.h>

struct EnvironmentalReading {
    float temperature = NAN;
    float humidity = NAN;
    float heatIndex = NAN;
    bool valid = false;
};

class DHT22Sensor {
public:
    explicit DHT22Sensor(uint8_t pin, uint8_t type = DHT22);

    void begin();
    EnvironmentalReading read();
    EnvironmentalReading last() const { return _lastReading; }

private:
    DHT _dht;
    EnvironmentalReading _lastReading;
};

#endif // DHT22_SENSOR_H

