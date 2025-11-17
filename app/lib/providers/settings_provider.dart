import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../core/utils/logger.dart';

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
          notificationsEnabled: true,
          caregiverAlerts: true,
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

  Future<void> _load() async {
    await _storage.initialize();

    state = SettingsState(
      notificationsEnabled: _storage.getBool(_notifKey, defaultValue: true),
      caregiverAlerts: _storage.getBool(_caregiverKey, defaultValue: true),
      autoMode: _storage.getBool(_autoModeKey, defaultValue: false),
    );
  }

  Future<void> toggleNotifications(String userId, bool enabled) async {
    state = state.copyWith(notificationsEnabled: enabled);
    await _storage.saveBool(_notifKey, enabled);
    if (enabled) {
      await _notifications.initialize(userId);
    }
  }

  Future<void> toggleCaregiverAlerts(bool enabled) async {
    state = state.copyWith(caregiverAlerts: enabled);
    await _storage.saveBool(_caregiverKey, enabled);
  }

  Future<void> setAutoMode(bool enabled) async {
    state = state.copyWith(autoMode: enabled);
    await _storage.saveBool(_autoModeKey, enabled);
    Logger.info('Auto mode preference updated: $enabled');
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
