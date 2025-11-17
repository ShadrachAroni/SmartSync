import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_data.dart';
import '../models/ml_prediction.dart';
import '../services/monitoring_service.dart';
import '../providers/auth_provider.dart';

final monitoringServiceProvider =
    Provider<MonitoringService>((ref) => MonitoringService());

final sensorStreamProvider = StreamProvider.autoDispose<SensorData?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return const Stream.empty();

  final service = ref.watch(monitoringServiceProvider);
  service.initialize(user.uid);
  ref.onDispose(service.dispose);
  return service.sensorStream;
});

final anomalyStreamProvider = StreamProvider.autoDispose<AnomalyReport?>((ref) {
  final service = ref.watch(monitoringServiceProvider);
  service.refreshAnomalies();
  return service.anomalyStream;
});
