import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_data.dart';
import '../models/ml_prediction.dart';
import '../services/monitoring_service.dart';
import '../providers/auth_provider.dart';
import '../core/utils/logger.dart';

final monitoringServiceProvider =
    Provider<MonitoringService>((ref) => MonitoringService());

final sensorStreamProvider = StreamProvider.autoDispose<SensorData?>((ref) async* {
  Logger.debug('sensorStreamProvider: Starting');
  
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  
  if (user == null) {
    Logger.debug('sensorStreamProvider: User is null, yielding null');
    yield null;
    return;
  }

  Logger.debug('sensorStreamProvider: Initializing monitoring service for ${user.uid}');
  final service = ref.watch(monitoringServiceProvider);
  
  try {
    await service.initialize(user.uid);
    Logger.debug('sensorStreamProvider: Service initialized');
  } catch (e) {
    Logger.error('sensorStreamProvider: Failed to initialize service: $e');
    yield null;
    return;
  }
  
  ref.onDispose(() {
    Logger.debug('sensorStreamProvider: Disposing');
    service.dispose();
  });
  
  // Emit null immediately to show "no data" state, then wait for actual data
  yield null;
  
  // Add timeout and fallback to prevent infinite loading
  try {
    Logger.debug('sensorStreamProvider: Starting to listen to sensor stream');
    await for (final data in service.sensorStream
        .timeout(
          const Duration(seconds: 20), // Reduced timeout
          onTimeout: (sink) {
            Logger.warning('sensorStreamProvider: Stream timeout, emitting null');
            sink.add(null);
            sink.close();
          },
        )
        .handleError((error, stackTrace) {
          Logger.error('sensorStreamProvider: Stream error: $error');
          Logger.error('sensorStreamProvider: Stack trace: $stackTrace');
        })) {
      Logger.debug('sensorStreamProvider: Received sensor data: ${data != null}');
      yield data;
    }
  } catch (e, stackTrace) {
    Logger.error('sensorStreamProvider: Exception in stream: $e');
    Logger.error('sensorStreamProvider: Stack trace: $stackTrace');
    // Yield null on any error to show "no data" state
    yield null;
  }
});

final anomalyStreamProvider = StreamProvider.autoDispose<AnomalyReport?>((ref) {
  final service = ref.watch(monitoringServiceProvider);
  service.refreshAnomalies();
  return service.anomalyStream;
});
