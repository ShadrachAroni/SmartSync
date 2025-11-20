import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/utils/logger.dart';

/// Storage Service for persistent local data
/// 
/// Uses SharedPreferences for regular data and FlutterSecureStorage for sensitive data
/// All operations are safe and handle errors gracefully
class StorageService {
  StorageService._internal();
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;

  static const _secureStorage = FlutterSecureStorage();
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  /// Initialize storage service
  /// Safe to call multiple times - will only initialize once
  Future<void> initialize() async {
    if (_isInitialized && _prefs != null) return;
    
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _isInitialized = true;
      Logger.debug('StorageService: Initialized successfully');
    } catch (e) {
      Logger.error('StorageService: Failed to initialize: $e');
      _isInitialized = false;
    }
  }

  /// Ensure storage is initialized before operations
  Future<void> _ensureInitialized() async {
    if (!_isInitialized || _prefs == null) {
      await initialize();
    }
  }

  // ==================== BOOLEAN OPERATIONS ====================

  /// Save a boolean value
  Future<bool> saveBool(String key, bool value) async {
    try {
      await _ensureInitialized();
      if (_prefs == null) {
        Logger.warning('StorageService: Cannot save bool - not initialized');
        return false;
      }
      final result = await _prefs!.setBool(key, value);
      if (result) {
        Logger.debug('StorageService: Saved bool $key = $value');
      }
      return result;
    } catch (e) {
      Logger.error('StorageService: Error saving bool $key: $e');
      return false;
    }
  }

  /// Get a boolean value
  bool getBool(String key, {bool defaultValue = false}) {
    try {
      if (_prefs == null) {
        Logger.warning('StorageService: getBool called before initialization, returning default');
        return defaultValue;
      }
      return _prefs!.getBool(key) ?? defaultValue;
    } catch (e) {
      Logger.error('StorageService: Error getting bool $key: $e');
      return defaultValue;
    }
  }

  // ==================== STRING OPERATIONS ====================

  /// Save a string value
  Future<bool> saveString(String key, String value) async {
    try {
      await _ensureInitialized();
      if (_prefs == null) {
        Logger.warning('StorageService: Cannot save string - not initialized');
        return false;
      }
      final result = await _prefs!.setString(key, value);
      if (result) {
        Logger.debug('StorageService: Saved string $key');
      }
      return result;
    } catch (e) {
      Logger.error('StorageService: Error saving string $key: $e');
      return false;
    }
  }

  /// Get a string value
  String? getString(String key) {
    try {
      if (_prefs == null) {
        Logger.warning('StorageService: getString called before initialization');
        return null;
      }
      return _prefs!.getString(key);
    } catch (e) {
      Logger.error('StorageService: Error getting string $key: $e');
      return null;
    }
  }

  // ==================== INTEGER OPERATIONS ====================

  /// Save an integer value
  Future<bool> saveInt(String key, int value) async {
    try {
      await _ensureInitialized();
      if (_prefs == null) {
        Logger.warning('StorageService: Cannot save int - not initialized');
        return false;
      }
      final result = await _prefs!.setInt(key, value);
      if (result) {
        Logger.debug('StorageService: Saved int $key = $value');
      }
      return result;
    } catch (e) {
      Logger.error('StorageService: Error saving int $key: $e');
      return false;
    }
  }

  /// Get an integer value
  int getInt(String key, {int defaultValue = 0}) {
    try {
      if (_prefs == null) {
        Logger.warning('StorageService: getInt called before initialization, returning default');
        return defaultValue;
      }
      return _prefs!.getInt(key) ?? defaultValue;
    } catch (e) {
      Logger.error('StorageService: Error getting int $key: $e');
      return defaultValue;
    }
  }

  // ==================== DOUBLE OPERATIONS ====================

  /// Save a double value
  Future<bool> saveDouble(String key, double value) async {
    try {
      await _ensureInitialized();
      if (_prefs == null) {
        Logger.warning('StorageService: Cannot save double - not initialized');
        return false;
      }
      final result = await _prefs!.setDouble(key, value);
      if (result) {
        Logger.debug('StorageService: Saved double $key = $value');
      }
      return result;
    } catch (e) {
      Logger.error('StorageService: Error saving double $key: $e');
      return false;
    }
  }

  /// Get a double value
  double getDouble(String key, {double defaultValue = 0.0}) {
    try {
      if (_prefs == null) {
        Logger.warning('StorageService: getDouble called before initialization, returning default');
        return defaultValue;
      }
      return _prefs!.getDouble(key) ?? defaultValue;
    } catch (e) {
      Logger.error('StorageService: Error getting double $key: $e');
      return defaultValue;
    }
  }

  // ==================== STRING LIST OPERATIONS ====================

  /// Save a string list
  Future<bool> saveStringList(String key, List<String> value) async {
    try {
      await _ensureInitialized();
      if (_prefs == null) {
        Logger.warning('StorageService: Cannot save string list - not initialized');
        return false;
      }
      final result = await _prefs!.setStringList(key, value);
      if (result) {
        Logger.debug('StorageService: Saved string list $key (${value.length} items)');
      }
      return result;
    } catch (e) {
      Logger.error('StorageService: Error saving string list $key: $e');
      return false;
    }
  }

  /// Get a string list
  List<String> getStringList(String key, {List<String>? defaultValue}) {
    try {
      if (_prefs == null) {
        Logger.warning('StorageService: getStringList called before initialization');
        return defaultValue ?? [];
      }
      return _prefs!.getStringList(key) ?? defaultValue ?? [];
    } catch (e) {
      Logger.error('StorageService: Error getting string list $key: $e');
      return defaultValue ?? [];
    }
  }

  // ==================== SECURE STORAGE OPERATIONS ====================

  /// Save a value to secure storage (encrypted)
  Future<bool> saveSecure(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
      Logger.debug('StorageService: Saved secure value $key');
      return true;
    } catch (e) {
      Logger.error('StorageService: Error saving secure value $key: $e');
      return false;
    }
  }

  /// Read a value from secure storage
  Future<String?> readSecure(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      Logger.error('StorageService: Error reading secure value $key: $e');
      return null;
    }
  }

  /// Delete a secure value
  Future<bool> deleteSecure(String key) async {
    try {
      await _secureStorage.delete(key: key);
      Logger.debug('StorageService: Deleted secure value $key');
      return true;
    } catch (e) {
      Logger.error('StorageService: Error deleting secure value $key: $e');
      return false;
    }
  }

  // ==================== KEY MANAGEMENT ====================

  /// Remove a key from storage
  Future<bool> remove(String key) async {
    try {
      await _ensureInitialized();
      if (_prefs == null) {
        Logger.warning('StorageService: Cannot remove key - not initialized');
        return false;
      }
      final result = await _prefs!.remove(key);
      if (result) {
        Logger.debug('StorageService: Removed key $key');
      }
      return result;
    } catch (e) {
      Logger.error('StorageService: Error removing key $key: $e');
      return false;
    }
  }

  /// Check if a key exists
  bool containsKey(String key) {
    try {
      if (_prefs == null) {
        return false;
      }
      return _prefs!.containsKey(key);
    } catch (e) {
      Logger.error('StorageService: Error checking key $key: $e');
      return false;
    }
  }

  /// Get all keys
  Set<String> getKeys() {
    try {
      if (_prefs == null) {
        return {};
      }
      return _prefs!.getKeys();
    } catch (e) {
      Logger.error('StorageService: Error getting keys: $e');
      return {};
    }
  }

  // ==================== CLEAR OPERATIONS ====================

  /// Clear all stored data (both regular and secure)
  Future<bool> clear() async {
    try {
      await _ensureInitialized();
      bool success = true;
      
      if (_prefs != null) {
        final cleared = await _prefs!.clear();
        if (!cleared) {
          Logger.warning('StorageService: Failed to clear SharedPreferences');
          success = false;
        }
      }
      
      try {
        await _secureStorage.deleteAll();
        Logger.debug('StorageService: Cleared secure storage');
      } catch (e) {
        Logger.error('StorageService: Error clearing secure storage: $e');
        success = false;
      }
      
      if (success) {
        Logger.info('StorageService: All storage cleared successfully');
      }
      
      return success;
    } catch (e) {
      Logger.error('StorageService: Error clearing storage: $e');
      return false;
    }
  }

  /// Check if storage is initialized
  bool get isInitialized => _isInitialized && _prefs != null;
}
