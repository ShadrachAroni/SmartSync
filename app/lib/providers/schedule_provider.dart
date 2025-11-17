import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule_model.dart';
import '../models/ml_prediction.dart';
import '../services/firebase_service.dart';

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

  void _listen() {
    _subscription =
        _firebase.getSchedules(_args.userId, deviceId: _args.deviceId).listen(
              (schedules) => state = AsyncValue.data(schedules),
              onError: (error, stack) => state = AsyncValue.error(error, stack),
            );
  }

  Future<void> addSchedule(ScheduleModel schedule) async {
    await _firebase.addSchedule(_args.userId, schedule);
  }

  Future<void> updateSchedule(ScheduleModel schedule) async {
    await _firebase.updateSchedule(_args.userId, schedule);
  }

  Future<void> deleteSchedule(String id) async {
    await _firebase.deleteSchedule(_args.userId, id);
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
      brightness: prediction.deviceType == 'led' ? prediction.value : 0,
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
