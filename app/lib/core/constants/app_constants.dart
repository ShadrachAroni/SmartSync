class AppConstants {
  // App Info
  static const String appName = 'SmartSync';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Smart Home for Elderly Care';

  // API Keys (Store in environment variables in production)
  static const String firebaseApiKey = 'YOUR_API_KEY';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration bleConnectionTimeout = Duration(seconds: 15);
  static const Duration sensorReadInterval = Duration(seconds: 10);

  // Limits
  static const int maxSchedulesPerDevice = 20;
  static const int maxCaregiversPerUser = 5;
  static const int maxAlertHistory = 100;

  // Temperature
  static const double minTemperature = -10.0;
  static const double maxTemperature = 50.0;
  static const double temperatureStep = 0.5;

  // Humidity
  static const double minHumidity = 0.0;
  static const double maxHumidity = 100.0;

  // Fan & LED
  static const int minSpeed = 0;
  static const int maxSpeed = 100;
  static const int speedStep = 5;

  // Motion timeout
  static const Duration motionTimeout = Duration(hours: 12);

  // Date formats
  static const String dateFormat = 'MMM dd, yyyy';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'MMM dd, yyyy HH:mm';

  // Storage keys
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';
  static const String keyNotifications = 'notifications_enabled';
  static const String keyLastDevice = 'last_connected_device';
}
