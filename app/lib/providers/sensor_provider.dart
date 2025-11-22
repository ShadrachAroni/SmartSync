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
    Logger.info('sensorStreamProvider: Initializing service for ${user.uid}');
    await service.initialize(user.uid).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        Logger.warning('sensorStreamProvider: Initialization timeout');
      },
    );
    Logger.info('sensorStreamProvider: Service initialized');
  } catch (e, stackTrace) {
    Logger.error('sensorStreamProvider: Failed to initialize service', e, stackTrace);
    yield null;
    return;
  }
  
  ref.onDispose(() {
    // Don't dispose the service since it's a singleton
    // Just log that the provider is disposed
    Logger.info('sensorStreamProvider: Provider disposed');
  });
  
  // Emit null immediately to show "no data" state, then wait for actual data
  yield null;
  
  // Add timeout and fallback to prevent infinite loading
  try {
    // Use takeWhile to prevent infinite waiting
    await for (final data in service.sensorStream
        .timeout(
          const Duration(seconds: 30),
          onTimeout: (sink) {
            Logger.warning('sensorStreamProvider: Stream timeout, emitting null');
            sink.add(null);
            sink.close();
          },
        )
        .handleError((error, stackTrace) {
          Logger.error('sensorStreamProvider: Stream error', error, stackTrace);
        })
        .take(1000)) { // Limit to 1000 emissions to prevent infinite loops
      yield data;
    }
  } catch (e, stackTrace) {
    Logger.error('sensorStreamProvider: Exception in stream', e, stackTrace);
    // Yield null on any error to show "no data" state
    yield null;
  }
});

final anomalyStreamProvider = StreamProvider.autoDispose<AnomalyReport?>((ref) {
  final service = ref.watch(monitoringServiceProvider);
  service.refreshAnomalies();
  return service.anomalyStream;
});
