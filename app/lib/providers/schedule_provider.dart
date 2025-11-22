import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule_model.dart';
import '../models/ml_prediction.dart';
import '../services/firebase_service.dart';
import '../services/bluetooth_service.dart';
import '../core/utils/logger.dart';

class ScheduleProviderArgs {
  final String userId;
  final String? deviceId;

  const ScheduleProviderArgs({
    required this.userId,
    this.deviceId,
  });
}

class ScheduleController
    extends StateNotifier<AsyncValue<List<ScheduleModel>>> {
  ScheduleController(this._ref, this._args)
      : super(const AsyncValue.loading()) {
    _listen();
  }

  final Ref _ref;
  final ScheduleProviderArgs _args;
  StreamSubscription<List<ScheduleModel>>? _subscription;

  FirebaseService get _firebase => _ref.read(firebaseServiceProvider);
  BluetoothService get _bluetooth => BluetoothService();

  void _listen() {
    _subscription =
        _firebase.getSchedules(_args.userId, deviceId: _args.deviceId).listen(
              (schedules) => state = AsyncValue.data(schedules),
              onError: (error, stack) => state = AsyncValue.error(error, stack),
            );
  }

  Future<void> addSchedule(ScheduleModel schedule) async {
    await _firebase.addSchedule(_args.userId, schedule);
    
    // Sync to device if connected and schedule is for the connected device
    if (_bluetooth.isConnected) {
      try {
        // Get the connected device ID
        final connectedDeviceId = _bluetooth.connectedDeviceId ?? '';
        if (schedule.deviceId == connectedDeviceId) {
          await _bluetooth.addScheduleToDevice(schedule);
          Logger.info('ScheduleProvider: Synced schedule to device');
        }
      } catch (e) {
        Logger.error('ScheduleProvider: Error syncing schedule to device: $e');
        // Don't fail the operation if sync fails
      }
    }
  }

  Future<void> updateSchedule(ScheduleModel schedule) async {
    await _firebase.updateSchedule(_args.userId, schedule);
    
    // Sync to device if connected and schedule is for the connected device
    if (_bluetooth.isConnected) {
      try {
        final connectedDeviceId = _bluetooth.connectedDeviceId ?? '';
        if (schedule.deviceId == connectedDeviceId) {
          await _bluetooth.syncScheduleToDevice(schedule);
          Logger.info('ScheduleProvider: Synced updated schedule to device');
        }
      } catch (e) {
        Logger.error('ScheduleProvider: Error syncing schedule update to device: $e');
        // Don't fail the operation if sync fails
      }
    }
  }

  Future<void> deleteSchedule(String id) async {
    // Get the schedule before deleting to sync deletion to device
    ScheduleModel? scheduleToDelete;
    state.whenData((schedules) {
      scheduleToDelete = schedules.firstWhere(
        (s) => s.id == id,
        orElse: () => throw StateError('Schedule not found'),
      );
    });
    
    await _firebase.deleteSchedule(_args.userId, id);
    
    // Sync deletion to device if connected
    if (_bluetooth.isConnected && scheduleToDelete != null) {
      try {
        final connectedDeviceId = _bluetooth.connectedDeviceId ?? '';
        if (scheduleToDelete!.deviceId == connectedDeviceId) {
          await _bluetooth.deleteScheduleFromDevice(scheduleToDelete!);
          Logger.info('ScheduleProvider: Synced schedule deletion to device');
        }
      } catch (e) {
        Logger.error('ScheduleProvider: Error syncing schedule deletion to device: $e');
        // Don't fail the operation if sync fails
      }
    }
  }

  Future<void> applyPrediction(
      SchedulePrediction prediction, String deviceId) async {
    final schedule = ScheduleModel(
      id: '',
      userId: _args.userId,
      deviceId: deviceId,
      hour: prediction.hour,
      minute: prediction.minute,
      fanSpeed: prediction.deviceType == 'fan' ? prediction.value : 0,
      brightness: prediction.deviceType == 'light' ? prediction.value : 0,
      enabled: true,
      repeatDaily: true,
      source: 'ai',
      createdAt: DateTime.now(),
    );
    await addSchedule(schedule);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final scheduleControllerProvider = StateNotifierProvider.autoDispose.family<
    ScheduleController, AsyncValue<List<ScheduleModel>>, ScheduleProviderArgs>(
  (ref, args) {
    final controller = ScheduleController(ref, args);
    ref.onDispose(controller.dispose);
    return controller;
  },
);
