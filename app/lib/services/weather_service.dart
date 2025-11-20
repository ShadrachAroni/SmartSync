import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/utils/logger.dart';

/// Weather condition types
enum WeatherCondition {
  sunny,
  cloudy,
  rainy,
  stormy,
  snowy,
  foggy,
  partlyCloudy,
}

/// Weather data model
class WeatherData {
  final double temperature;
  final double humidity;
  final String description;
  final WeatherCondition condition;
  final String location;

  WeatherData({
    required this.temperature,
    required this.humidity,
    required this.description,
    required this.condition,
    required this.location,
  });
}

/// Service to fetch weather data
/// Note: This uses OpenWeatherMap API as an example
/// You'll need to add your API key to .env file: WEATHER_API_KEY=your_key_here
class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  // Using a free weather API (Open-Meteo) that doesn't require API key
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Get current weather (using temperature from sensor as fallback)
  Future<WeatherData?> getCurrentWeather({
    double? latitude,
    double? longitude,
    double? fallbackTemperature,
    double? fallbackHumidity,
  }) async {
    try {
      // Get location if not provided
      double lat = latitude ?? 0.0;
      double lon = longitude ?? 0.0;
      
      // If coordinates not provided, try to get current location
      if (lat == 0.0 && lon == 0.0) {
        try {
          // Check location permission
          final locationPermission = await Permission.location.status;
          if (locationPermission.isDenied) {
            final result = await Permission.location.request();
            if (result.isDenied) {
              Logger.warning('WeatherService: Location permission denied');
            }
          }
          
          if (locationPermission.isGranted || await Permission.location.isGranted) {
            // Check if location services are enabled
            bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
            if (!serviceEnabled) {
              Logger.warning('WeatherService: Location services are disabled');
            } else {
              // Get current position
              Position position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.low,
                timeLimit: const Duration(seconds: 5),
              );
              lat = position.latitude;
              lon = position.longitude;
              Logger.info('WeatherService: Got location: $lat, $lon');
            }
          }
        } catch (e) {
          Logger.warning('WeatherService: Failed to get location: $e');
          // Continue with fallback
        }
      }

      // Try to fetch from API if coordinates are valid
      if (lat != 0.0 && lon != 0.0) {
        final url = Uri.parse(
          '$_baseUrl?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code&timezone=auto',
        );

        final response = await http.get(url).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception('Weather API timeout'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final current = data['current'];
          
          if (current != null) {
            final temp = (current['temperature_2m'] as num?)?.toDouble() ?? fallbackTemperature ?? 22.0;
            final hum = (current['relative_humidity_2m'] as num?)?.toDouble() ?? fallbackHumidity ?? 50.0;
            final weatherCode = current['weather_code'] as int? ?? 0;

            return WeatherData(
              temperature: temp,
              humidity: hum,
              description: _getWeatherDescription(weatherCode),
              condition: _getWeatherCondition(weatherCode),
              location: 'Current Location',
            );
          }
        }
      }

      // Fallback: Use sensor data or default values
      return WeatherData(
        temperature: fallbackTemperature ?? 22.0,
        humidity: fallbackHumidity ?? 50.0,
        description: _getWeatherDescriptionFromTemp(fallbackTemperature ?? 22.0),
        condition: _getWeatherConditionFromTemp(fallbackTemperature ?? 22.0),
        location: 'Local',
      );
    } catch (e) {
      Logger.warning('WeatherService: Error fetching weather: $e');
      // Return fallback weather
      return WeatherData(
        temperature: fallbackTemperature ?? 22.0,
        humidity: fallbackHumidity ?? 50.0,
        description: 'Partly Cloudy',
        condition: WeatherCondition.partlyCloudy,
        location: 'Local',
      );
    }
  }

  String _getWeatherDescription(int code) {
    // WMO Weather interpretation codes
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Partly Cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 55) return 'Drizzle';
    if (code <= 65) return 'Rainy';
    if (code <= 67) return 'Freezing Rain';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Rain Showers';
    if (code <= 86) return 'Snow Showers';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  WeatherCondition _getWeatherCondition(int code) {
    if (code == 0) return WeatherCondition.sunny;
    if (code <= 3) return WeatherCondition.partlyCloudy;
    if (code <= 48) return WeatherCondition.foggy;
    if (code <= 55 || (code >= 61 && code <= 65)) return WeatherCondition.rainy;
    if (code >= 66 && code <= 77) return WeatherCondition.snowy;
    if (code >= 95) return WeatherCondition.stormy;
    return WeatherCondition.cloudy;
  }

  String _getWeatherDescriptionFromTemp(double temp) {
    if (temp < 10) return 'Cold';
    if (temp < 20) return 'Cool';
    if (temp < 25) return 'Mild';
    if (temp < 30) return 'Warm';
    return 'Hot';
  }

  WeatherCondition _getWeatherConditionFromTemp(double temp) {
    if (temp < 10) return WeatherCondition.cloudy;
    if (temp < 20) return WeatherCondition.partlyCloudy;
    if (temp < 30) return WeatherCondition.sunny;
    return WeatherCondition.sunny;
  }
}

