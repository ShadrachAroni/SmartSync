import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/weather_service.dart';
import '../../models/sensor_data.dart';
import '../../providers/sensor_provider.dart';
import 'live_time_widget.dart';
import '../../core/utils/logger.dart';

final weatherDataProvider = FutureProvider.autoDispose<WeatherData?>((ref) async {
  final weatherService = WeatherService();
  // Get sensor data for fallback
  final sensorData = ref.watch(sensorStreamProvider);
  final temp = sensorData.asData?.value?.temperature;
  final hum = sensorData.asData?.value?.humidity;
  
  // Weather service will automatically request location permission and get coordinates
  return await weatherService.getCurrentWeather(
    fallbackTemperature: temp,
    fallbackHumidity: hum,
  );
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
              Icon(
                Icons.access_time_rounded,
                color: Colors.white.withOpacity(0.9),
                size: 24,
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
    IconData iconData;
    Color iconColor;
    bool shouldAnimate = false;

    switch (condition) {
      case WeatherCondition.sunny:
        iconData = Icons.wb_sunny_rounded;
        iconColor = Colors.amber;
        shouldAnimate = true;
        break;
      case WeatherCondition.cloudy:
        iconData = Icons.cloud_rounded;
        iconColor = Colors.grey.shade300;
        break;
      case WeatherCondition.rainy:
        iconData = Icons.grain_rounded;
        iconColor = Colors.blue.shade300;
        shouldAnimate = true;
        break;
      case WeatherCondition.stormy:
        iconData = Icons.flash_on_rounded;
        iconColor = Colors.purple.shade300;
        shouldAnimate = true;
        break;
      case WeatherCondition.snowy:
        iconData = Icons.ac_unit_rounded;
        iconColor = Colors.cyan.shade200;
        break;
      case WeatherCondition.foggy:
        iconData = Icons.blur_on_rounded;
        iconColor = Colors.grey.shade400;
        break;
      case WeatherCondition.partlyCloudy:
        iconData = Icons.wb_cloudy_rounded;
        iconColor = Colors.grey.shade200;
        break;
    }

    Widget icon = Icon(
      iconData,
      size: 48,
      color: iconColor,
    );

    if (shouldAnimate) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(seconds: 2),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 1.0 + (value * 0.1 * (value < 0.5 ? value : 1 - value)),
            child: Opacity(
              opacity: 0.8 + (value * 0.2),
              child: icon,
            ),
          );
        },
        onEnd: () {
          // Restart animation
        },
      );
    }

    return icon;
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

