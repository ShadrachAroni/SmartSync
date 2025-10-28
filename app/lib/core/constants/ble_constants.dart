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

  // Connection settings
  static const int maxConnectionAttempts = 3;
  static const Duration connectionRetryDelay = Duration(seconds: 2);

  // Add this to fix undefined getter error
  static const Duration bleConnectionTimeout = Duration(seconds: 10);

  // Command codes
  static const String cmdGetStatus = 'GET_STATUS';
  static const String cmdSetFan = 'SET_FAN';
  static const String cmdSetLED = 'SET_LED';
  static const String cmdGetSensor = 'GET_SENSOR';
  static const String cmdSetAutoMode = 'SET_AUTO';
  static const String cmdAddSchedule = 'ADD_SCHEDULE';
  static const String cmdDeleteSchedule = 'DEL_SCHEDULE';
  static const String cmdSOS = 'SOS';

  // Response codes
  static const String respOK = 'OK';
  static const String respError = 'ERROR';
  static const String respData = 'DATA';
}
