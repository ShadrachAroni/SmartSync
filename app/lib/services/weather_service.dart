import 'dart:async';
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

  /// Get current weather from public weather API based on local area
  /// Only uses sensor data as absolute last resort if weather API completely fails
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
          // Check location permission with timeout - wrap in try-catch to handle timeout gracefully
          PermissionStatus? locationPermission;
          try {
            locationPermission = await Permission.location.status
                .timeout(const Duration(seconds: 1));
          } on TimeoutException {
            Logger.info('WeatherService: Location permission check timed out, skipping location request');
            // Skip to default location fallback
            locationPermission = null;
          } catch (e) {
            Logger.info('WeatherService: Error checking location permission: $e');
            locationPermission = null;
          }
          
          // Only proceed if we got a valid permission status
          if (locationPermission != null) {
            // Request permission if denied
            if (locationPermission.isDenied) {
              try {
                locationPermission = await Permission.location.request()
                    .timeout(const Duration(seconds: 1));
              } on TimeoutException {
                Logger.info('WeatherService: Location permission request timed out');
                locationPermission = PermissionStatus.denied;
              } catch (e) {
                Logger.info('WeatherService: Error requesting location permission: $e');
                locationPermission = PermissionStatus.denied;
              }
            }
            
            // Check if permission is granted (use the updated status)
            final isGranted = locationPermission.isGranted || 
                locationPermission.isLimited;
            
            if (isGranted) {
              // Check if location services are enabled with timeout
              bool serviceEnabled = false;
              try {
                serviceEnabled = await Geolocator.isLocationServiceEnabled()
                    .timeout(const Duration(seconds: 1));
              } catch (e) {
                Logger.info('WeatherService: Could not check if location services are enabled: $e');
                // Skip if check times out
              }
              
              if (serviceEnabled) {
                // Get current position with shorter timeout to prevent hanging
                try {
                  Position position = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.low,
                    timeLimit: const Duration(seconds: 2),
                  ).timeout(
                    const Duration(seconds: 2),
                    onTimeout: () => throw TimeoutException('Location timeout'),
                  );
                  lat = position.latitude;
                  lon = position.longitude;
                  Logger.info('WeatherService: Successfully obtained location: lat=$lat, lon=$lon');
                } on TimeoutException catch (e) {
                  Logger.info('WeatherService: Location request timed out: $e');
                  // Skip location on timeout, will use default location
                } catch (e) {
                  Logger.info('WeatherService: Failed to get current position: $e');
                  // Skip location, will use default location
                }
              } else {
                Logger.info('WeatherService: Location services are disabled');
              }
            } else {
              Logger.info('WeatherService: Location permission not granted (status: $locationPermission)');
            }
          }
        } catch (e) {
          Logger.info('WeatherService: Error in location flow: $e');
          // Continue with fallback on any error
        }
      }

      // Try to fetch from API if coordinates are valid
      if (lat != 0.0 && lon != 0.0) {
        final url = Uri.parse(
          '$_baseUrl?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code&timezone=auto',
        );

        try {
          final response = await http.get(url).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Weather API timeout'),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final current = data['current'];
            
            if (current != null) {
              // Always use public weather API data - never fallback to sensor data here
              final temp = (current['temperature_2m'] as num?)?.toDouble();
              final hum = (current['relative_humidity_2m'] as num?)?.toDouble();
              final weatherCode = current['weather_code'] as int? ?? 0;

              // Only use API data if valid
              if (temp != null && hum != null) {
                Logger.info('WeatherService: Successfully fetched weather from API');
                return WeatherData(
                  temperature: temp,
                  humidity: hum,
                  description: _getWeatherDescription(weatherCode),
                  condition: _getWeatherCondition(weatherCode),
                  location: 'Current Location',
                );
              } else {
                Logger.warning('WeatherService: API returned invalid temperature/humidity data');
              }
            } else {
              Logger.warning('WeatherService: API response missing current weather data');
            }
          } else {
            Logger.warning('WeatherService: API returned status code ${response.statusCode}');
          }
        } on TimeoutException catch (e) {
          Logger.warning('WeatherService: API request timed out: $e');
        } catch (e) {
          Logger.warning('WeatherService: API request failed: $e');
        }
      } else {
        Logger.info('WeatherService: No valid coordinates available (lat: $lat, lon: $lon)');
      }

      // Only use sensor data as absolute last resort if weather API completely failed
      // and we couldn't get location or API returned invalid data
      if (fallbackTemperature != null && fallbackHumidity != null) {
        Logger.info('WeatherService: Using sensor data as fallback (weather API unavailable)');
        return WeatherData(
          temperature: fallbackTemperature,
          humidity: fallbackHumidity,
          description: _getWeatherDescriptionFromTemp(fallbackTemperature),
          condition: _getWeatherConditionFromTemp(fallbackTemperature),
          location: 'Local (Sensor)',
        );
      }

      // Final fallback: Try using a default location (major city) if no location/sensor data
      if (lat == 0.0 && lon == 0.0) {
        Logger.info('WeatherService: Attempting to use default location as last resort');
        // Use a default location (e.g., New York City coordinates)
        // This ensures users get weather data even if location permission is denied
        const defaultLat = 40.7128; // New York City
        const defaultLon = -74.0060;
        
        try {
          final url = Uri.parse(
            '$_baseUrl?latitude=$defaultLat&longitude=$defaultLon&current=temperature_2m,relative_humidity_2m,weather_code&timezone=auto',
          );

          final response = await http.get(url).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Weather API timeout'),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final current = data['current'];
            
            if (current != null) {
              final temp = (current['temperature_2m'] as num?)?.toDouble();
              final hum = (current['relative_humidity_2m'] as num?)?.toDouble();
              final weatherCode = current['weather_code'] as int? ?? 0;

              if (temp != null && hum != null) {
                Logger.info('WeatherService: Using default location weather data (location permission unavailable)');
                return WeatherData(
                  temperature: temp,
                  humidity: hum,
                  description: _getWeatherDescription(weatherCode),
                  condition: _getWeatherCondition(weatherCode),
                  location: 'Sample Location',
                );
              }
            }
          }
        } catch (e) {
          Logger.warning('WeatherService: Failed to fetch default location weather: $e');
        }
      }

      // Final fallback: return null to indicate weather data unavailable
      Logger.warning(
        'WeatherService: Unable to fetch weather data from API or sensors. '
        'Location: lat=$lat, lon=$lon. '
        'Sensor fallback: temp=${fallbackTemperature ?? "null"}, hum=${fallbackHumidity ?? "null"}'
      );
      return null;
    } catch (e, stackTrace) {
      Logger.warning('WeatherService: Error fetching weather: $e');
      Logger.warning('WeatherService: Stack trace: $stackTrace');
      
      // Only use sensor data as last resort if available
      if (fallbackTemperature != null && fallbackHumidity != null) {
        Logger.info('WeatherService: Using sensor data as fallback after error');
        return WeatherData(
          temperature: fallbackTemperature,
          humidity: fallbackHumidity,
          description: _getWeatherDescriptionFromTemp(fallbackTemperature),
          condition: _getWeatherConditionFromTemp(fallbackTemperature),
          location: 'Local (Sensor)',
        );
      }
      
      // Return null if no sensor data available either
      Logger.warning(
        'WeatherService: No sensor fallback available. '
        'Sensor fallback: temp=${fallbackTemperature ?? "null"}, hum=${fallbackHumidity ?? "null"}'
      );
      return null;
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


