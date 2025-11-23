import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/weather_service.dart';
import '../../providers/sensor_provider.dart';
import 'live_time_widget.dart';
import 'lottie_weather_icon.dart';

final weatherDataProvider =
    StreamProvider.autoDispose<WeatherData?>((ref) async* {
  // Keep provider alive to prevent unnecessary recreations
  ref.keepAlive();
  
  final weatherService = WeatherService();
  WeatherData? lastWeather;
  
  // Helper function to fetch weather
  Future<WeatherData?> _fetchWeather() async {
    try {
      // Get sensor data ONLY as absolute last resort if weather API completely fails
      double? sensorTemp;
      double? sensorHum;
      try {
        final sensorData = ref.read(sensorStreamProvider);
        sensorTemp = sensorData.asData?.value?.temperature;
        sensorHum = sensorData.asData?.value?.humidity;
      } catch (e) {
        // Sensor data not available - that's okay, we'll use weather API
      }

      // Weather service will automatically:
      // 1. Get user's location (GPS)
      // 2. Fetch public weather data from Open-Meteo API for that location
      // 3. Only use sensor data if weather API completely fails
      final weather = await weatherService
          .getCurrentWeather(
        fallbackTemperature: sensorTemp,
        fallbackHumidity: sensorHum,
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // On timeout, only use sensor data if available, otherwise return null
          if (sensorTemp != null && sensorHum != null) {
            return WeatherData(
              temperature: sensorTemp,
              humidity: sensorHum,
              description: 'Partly Cloudy',
              condition: WeatherCondition.partlyCloudy,
              location: 'Local (Sensor)',
            );
          }
          return null;
        },
      );
      
      return weather;
    } catch (e) {
      // On error, try sensor data as last resort
      double? sensorTemp;
      double? sensorHum;
      try {
        final sensorData = ref.read(sensorStreamProvider);
        sensorTemp = sensorData.asData?.value?.temperature;
        sensorHum = sensorData.asData?.value?.humidity;
      } catch (e) {
        // No sensor data available
      }
      
      // Only return sensor data if available
      if (sensorTemp != null && sensorHum != null) {
        return WeatherData(
          temperature: sensorTemp,
          humidity: sensorHum,
          description: 'Partly Cloudy',
          condition: WeatherCondition.partlyCloudy,
          location: 'Local (Sensor)',
        );
      }
      
      return null;
    }
  }
  
  // Initial fetch
  final initialWeather = await _fetchWeather();
  if (initialWeather != null) {
    lastWeather = initialWeather;
    yield initialWeather;
  }
  
  // Fetch weather data periodically (every 2 minutes) for real-time updates
  await for (final _ in Stream.periodic(const Duration(minutes: 2)).skip(1)) {
    final weather = await _fetchWeather();
    if (weather != null) {
      lastWeather = weather;
      yield weather;
    } else if (lastWeather != null) {
      // Keep last known weather if new fetch fails
      yield lastWeather;
    }
  }
});

class WeatherTimeWidget extends ConsumerWidget {
  const WeatherTimeWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(weatherDataProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade700.withOpacity(0.8),
            Colors.blue.shade900.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Time Section
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.access_time,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              const LiveTimeWidget(
                showSeconds: true,
                showDayNight: true,
                textStyle: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Weather Section
          weatherAsync.when(
            data: (weather) {
              if (weather == null) {
                return _buildWeatherPlaceholder();
              }
              return _buildWeatherContent(weather);
            },
            loading: () => _buildWeatherPlaceholder(),
            error: (_, __) => _buildWeatherPlaceholder(),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherContent(WeatherData weather) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Animated Weather Icon
        _buildAnimatedWeatherIcon(weather.condition),
        const SizedBox(width: 16),
        // Weather Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                weather.description,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.thermostat_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${weather.temperature.toStringAsFixed(1)}°C',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.water_drop_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${weather.humidity.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedWeatherIcon(WeatherCondition condition) {
    // Use Lottie animation for weather icons
    return LottieWeatherIcon(
      condition: condition,
      size: 64,
    );
  }

  Widget _buildWeatherPlaceholder() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.wb_cloudy_rounded,
          size: 48,
          color: Colors.white.withOpacity(0.7),
        ),
        const SizedBox(width: 16),
        Text(
          'Loading weather...',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
}
