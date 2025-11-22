import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../services/weather_service.dart';
import '../../providers/sensor_provider.dart';
import 'live_time_widget.dart';
import 'lottie_weather_icon.dart';

final weatherDataProvider = FutureProvider.autoDispose<WeatherData?>((ref) async {
  try {
    final weatherService = WeatherService();
    // Get sensor data for fallback
    final sensorData = ref.watch(sensorStreamProvider);
    final temp = sensorData.asData?.value?.temperature;
    final hum = sensorData.asData?.value?.humidity;
    
    // Weather service will automatically request location permission and get coordinates
    // Add timeout to prevent hanging
    return await weatherService.getCurrentWeather(
      fallbackTemperature: temp,
      fallbackHumidity: hum,
    ).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        // Return fallback weather data on timeout
        return WeatherData(
          temperature: temp ?? 22.0,
          humidity: hum ?? 50.0,
          description: 'Partly Cloudy',
          condition: WeatherCondition.partlyCloudy,
          location: 'Local',
        );
      },
    );
  } catch (e) {
    // Return fallback on any error
    final sensorData = ref.watch(sensorStreamProvider);
    final temp = sensorData.asData?.value?.temperature;
    final hum = sensorData.asData?.value?.humidity;
    return WeatherData(
      temperature: temp ?? 22.0,
      humidity: hum ?? 50.0,
      description: 'Partly Cloudy',
      condition: WeatherCondition.partlyCloudy,
      location: 'Local',
    );
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

