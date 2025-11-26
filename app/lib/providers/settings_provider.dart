import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../services/logging_service.dart';
import '../services/bluetooth_service.dart';
import '../services/adaptive_auto_service.dart';
import '../models/log_entry.dart';
import '../core/utils/logger.dart';
import 'device_provider.dart';

class SettingsState {
  final bool notificationsEnabled;
  final bool caregiverAlerts;
  final bool autoMode;

  const SettingsState({
    required this.notificationsEnabled,
    required this.caregiverAlerts,
    required this.autoMode,
  });

  SettingsState copyWith({
    bool? notificationsEnabled,
    bool? caregiverAlerts,
    bool? autoMode,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      caregiverAlerts: caregiverAlerts ?? this.caregiverAlerts,
      autoMode: autoMode ?? this.autoMode,
    );
  }
}

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._ref)
      : super(const SettingsState(
          notificationsEnabled: false,
          caregiverAlerts: false,
          autoMode: false,
        )) {
    _load();
  }

  final Ref _ref;
  static const _notifKey = 'settings.notifications';
  static const _caregiverKey = 'settings.caregiver';
  static const _autoModeKey = 'settings.auto_mode';

  StorageService get _storage => _ref.read(storageServiceProvider);
  NotificationService get _notifications =>
      _ref.read(notificationServiceProvider);
  BluetoothService get _bluetooth => _ref.read(bluetoothServiceProvider);
  AdaptiveAutoService get _adaptiveAuto => AdaptiveAutoService();

  Future<void> _load() async {
    await _storage.initialize();

    final localNotifications =
        _storage.getBool(_notifKey, defaultValue: false);

    state = SettingsState(
      notificationsEnabled: localNotifications,
      caregiverAlerts: _storage.getBool(_caregiverKey, defaultValue: false),
      autoMode: _storage.getBool(_autoModeKey, defaultValue: false),
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final remotePref =
            await _notifications.getStoredPreference(user.uid);
        final permissionGranted =
            await _notifications.isSystemPermissionGranted();
        final resolved =
            permissionGranted && (remotePref ?? localNotifications);
        if (resolved != state.notificationsEnabled) {
          state = state.copyWith(notificationsEnabled: resolved);
          await _storage.saveBool(_notifKey, resolved);
        }
      } catch (e) {
        Logger.warning('SettingsController: Failed to sync notification preference: $e');
      }
    }
  }

  Future<void> toggleNotifications(String userId, bool enabled) async {
    final previousState = state.notificationsEnabled;
    state = state.copyWith(notificationsEnabled: enabled);
    await _storage.saveBool(_notifKey, enabled);
    if (enabled) {
      await _notifications.initialize(userId);
    }
    await _notifications.updateGlobalNotificationPreference(userId, enabled);
    // Log the change with detailed information
    final loggingService = LoggingService();
    await loggingService.logAction(
      action: 'Push Notifications ${enabled ? "ENABLED" : "DISABLED"}',
      category: 'settings',
      details:
          'Push notifications ${enabled ? "enabled" : "disabled"} (previous state: ${previousState ? "enabled" : "disabled"})',
      metadata: {
        'setting': 'push_notifications',
        'previousState': previousState,
        'newState': enabled,
        'userId': userId,
        'actionType': 'notification_toggle',
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: LogLevel.info,
    );
  }

  Future<void> toggleCaregiverAlerts(bool enabled) async {
    final previousState = state.caregiverAlerts;
    state = state.copyWith(caregiverAlerts: enabled);
    await _storage.saveBool(_caregiverKey, enabled);
    // Log the change with detailed information
    final loggingService = LoggingService();
    await loggingService.logAction(
      action: 'Caregiver Alerts ${enabled ? "ENABLED" : "DISABLED"}',
      category: 'settings',
      details:
          'Caregiver alerts ${enabled ? "enabled" : "disabled"} (previous state: ${previousState ? "enabled" : "disabled"})',
      metadata: {
        'setting': 'caregiver_alerts',
        'previousState': previousState,
        'newState': enabled,
        'actionType': 'caregiver_alerts_toggle',
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: LogLevel.info,
    );
  }

  Future<void> setAutoMode(bool enabled) async {
    final previousState = state.autoMode;
    state = state.copyWith(autoMode: enabled);
    await _storage.saveBool(_autoModeKey, enabled);
    Logger.info('Auto mode preference updated: $enabled');

    // Enable/Disable AI-powered adaptive auto mode
    await _adaptiveAuto.setEnabled(enabled);

    // Also send command to BLE device for firmware auto mode (as fallback)
    bool bleCommandSuccess = false;
    if (_bluetooth.isConnected) {
      try {
        bleCommandSuccess = await _bluetooth.setAutoMode(enabled).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            Logger.warning('Auto mode BLE command timeout');
            return false;
          },
        );
        Logger.info('Auto mode command sent to BLE device: $enabled');
      } catch (e) {
        Logger.error('Failed to send auto mode command to BLE: $e');
      }
    } else {
      Logger.warning(
          'BLE not connected, auto mode preference saved but not sent to device');
    }

    // Log the change with detailed information
    final loggingService = LoggingService();
    await loggingService.logAction(
      action: 'Adaptive Auto Mode ${enabled ? "ENABLED" : "DISABLED"}',
      category: 'settings',
      details:
          'AI-powered adaptive auto mode ${enabled ? "enabled" : "disabled"} (previous state: ${previousState ? "enabled" : "disabled"})',
      metadata: {
        'setting': 'adaptive_auto_mode',
        'previousState': previousState,
        'newState': enabled,
        'bleConnected': _bluetooth.isConnected,
        'bleCommandSuccess': bleCommandSuccess,
        'actionType': 'auto_mode_toggle',
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: LogLevel.info,
    );
  }
}

final storageServiceProvider =
    Provider<StorageService>((ref) => StorageService());
final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>(
  (ref) => SettingsController(ref),
);
