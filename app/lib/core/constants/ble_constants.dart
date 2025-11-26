class BLEConstants {
  // Service UUID
  static const String serviceUUID = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

  // Characteristic UUIDs
  static const String rxCharacteristicUUID =
      'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String txCharacteristicUUID =
      'beb5483f-36e1-4688-b7f5-ea07361b26a8';

  // Device name prefix
  static const String deviceNamePrefix = 'SmartSync';

  // Scan settings
  static const Duration scanTimeout = Duration(seconds: 15);
  static const int rssiThreshold = -80; // Minimum signal strength

  // Connection settings - Enhanced for stability
  static const int maxConnectionAttempts = 5; // Increased attempts
  static const Duration connectionRetryDelay = Duration(milliseconds: 500); // Faster retry
  static const Duration heartbeatInterval = Duration(seconds: 20); // Less aggressive heartbeat
  static const Duration inactivityGracePeriod = Duration(seconds: 120); // Longer grace period for stability
  static const Duration scanReconnectTimeout = Duration(seconds: 8); // Faster scan reconnect
  static const Duration sensorPollInterval = Duration(seconds: 20); // Less aggressive polling
  static const Duration connectionKeepaliveInterval = Duration(seconds: 15); // Less aggressive keepalive
  static const Duration connectionGracePeriod = Duration(seconds: 10); // Grace period after connection before monitoring

  // Add this to fix undefined getter error
  // Increased timeout to handle slower connections and ESP32 initialization
  // Increased to 30 seconds for better reliability with ESP32 devices
  static const Duration bleConnectionTimeout = Duration(seconds: 30);

  // Event identifiers
  static const String eventHeartbeat = 'heartbeat';
  static const String eventConnectionState = 'connection_state';

  // Command codes
  static const String cmdGetStatus = 'GET_STATUS';
  static const String cmdSetFan = 'SET_FAN';
  static const String cmdSetLED = 'SET_LED';
  static const String cmdGetSensor = 'GET_SENSOR';
  static const String cmdSetAutoMode = 'SET_AUTO';
  static const String cmdAddSchedule = 'ADD_SCHEDULE';
  static const String cmdDeleteSchedule = 'DEL_SCHEDULE';
  static const String cmdSOS = 'SOS';
  static const String cmdSetSecurity = 'SET_SECURITY';
  static const String cmdSetHubConfig = 'SET_HUB_CONFIG';

  // Response codes
  static const String respOK = 'OK';
  static const String respError = 'ERROR';
  static const String respData = 'DATA';
}
