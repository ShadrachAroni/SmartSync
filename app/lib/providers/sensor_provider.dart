import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_data.dart';
import '../models/ml_prediction.dart';
import '../services/monitoring_service.dart';
import '../providers/auth_provider.dart';
import '../core/utils/logger.dart';

final monitoringServiceProvider =
    Provider<MonitoringService>((ref) => MonitoringService());

final sensorStreamProvider = StreamProvider.autoDispose<SensorData?>((ref) async* {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  
  if (user == null) {
    yield null;
    return;
  }

  final service = ref.watch(monitoringServiceProvider);
  
  // Initialize with timeout to prevent hanging
  try {
    await service.initialize(user.uid).timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
  } catch (e, stackTrace) {
    Logger.error('sensorStreamProvider: Failed to initialize', e, stackTrace);
    yield null;
    return;
  }
  
  // Emit null immediately to show "no data" state, then wait for actual data
  yield null;
  
  // Listen to the stream
  try {
    await for (final data in service.sensorStream
        .handleError((error, stackTrace) {
          Logger.error('sensorStreamProvider: Stream error', error, stackTrace);
        })
        .take(10000)) {
      yield data;
    }
  } catch (e, stackTrace) {
    Logger.error('sensorStreamProvider: Exception', e, stackTrace);
    yield null;
  }
});

final anomalyStreamProvider = StreamProvider.autoDispose<AnomalyReport?>((ref) {
  final service = ref.watch(monitoringServiceProvider);
  service.refreshAnomalies();
  return service.anomalyStream;
});
