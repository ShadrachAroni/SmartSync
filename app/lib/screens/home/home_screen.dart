import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/bluetooth_service.dart';
import '../../models/sensor_data.dart';
import '../../core/constants/colors.dart';
import '../widgets/sensor_card.dart';
import '../widgets/custom_slider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BluetoothService _bluetoothService = BluetoothService();

  SensorData? _latestData;
  bool _isConnected = false;
  bool _autoMode = false;
  double _fanSpeed = 50;
  double _ledBrightness = 75;

  StreamSubscription? _sensorDataSubscription;
  StreamSubscription? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to sensor data
    _sensorDataSubscription = _bluetoothService.sensorDataStream.listen(
      (data) {
        setState(() {
          _latestData = data;
          _fanSpeed = data.fanSpeedPercentage.toDouble();
          _ledBrightness = data.ledBrightnessPercentage.toDouble();
        });
      },
    );

    // Listen to connection status
    _connectionSubscription = _bluetoothService.connectionStream.listen(
      (connected) {
        setState(() {
          _isConnected = connected;
        });

        if (!connected) {
          _showConnectionLostDialog();
        }
      },
    );

    // Check initial connection status
    _isConnected = _bluetoothService.isConnected;
  }

  void _showConnectionLostDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Connection Lost'),
        content: const Text(
          'Connection to your SmartSync device was lost. Would you like to reconnect?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back to scan screen
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement reconnection logic
            },
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _setFanSpeed(double speed) async {
    setState(() => _fanSpeed = speed);
    await _bluetoothService.setFanSpeed(speed.round());
  }

  Future<void> _setLEDBrightness(double brightness) async {
    setState(() => _ledBrightness = brightness);
    await _bluetoothService.setLEDBrightness(brightness.round());
  }

  Future<void> _toggleAutoMode(bool value) async {
    setState(() => _autoMode = value);
    await _bluetoothService.setAutoMode(value);
  }

  Future<void> _sendSOS() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: AppColors.emergency, size: 32),
            SizedBox(width: 10),
            Text('Emergency Alert'),
          ],
        ),
        content: const Text(
          'This will send an emergency alert to all your caregivers. Continue?',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergency,
            ),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Implement SOS functionality
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency alert sent to all caregivers!'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _sensorDataSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSync Home'),
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isConnected
                      ? AppColors.success.withOpacity(0.2)
                      : AppColors.error.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      size: 16,
                      color: _isConnected ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            _isConnected ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isConnected ? _buildContent() : _buildDisconnectedView(),
    );
  }

  Widget _buildDisconnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 100, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            'Not Connected',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Please connect to your device',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.search),
            label: const Text('Find Devices'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greeting
          _buildGreeting(),
          const SizedBox(height: 20),

          // Sensor Cards
          Row(
            children: [
              Expanded(
                child: SensorCard(
                  icon: Icons.thermostat,
                  title: 'Temperature',
                  value: _latestData?.temperatureDisplay ?? '--',
                  color: AppColors.temperature,
                  subtitle: _getTemperatureStatus(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SensorCard(
                  icon: Icons.water_drop,
                  title: 'Humidity',
                  value: _latestData?.humidityDisplay ?? '--',
                  color: AppColors.humidity,
                  subtitle: _getHumidityStatus(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Fan Control
          CustomSlider(
            title: 'Fan Control',
            icon: Icons.air,
            value: _fanSpeed,
            min: 0,
            max: 100,
            divisions: 20,
            suffix: '%',
            color: AppColors.primary,
            onChanged: _isConnected ? _setFanSpeed : null,
            trailing: Switch(
              value: _autoMode,
              onChanged: _isConnected ? _toggleAutoMode : null,
              activeColor: AppColors.success,
            ),
            trailingLabel: 'AUTO',
          ),
          const SizedBox(height: 16),

          // LED Control
          CustomSlider(
            title: 'Light Control',
            icon: Icons.light_mode,
            value: _ledBrightness,
            min: 0,
            max: 100,
            divisions: 20,
            suffix: '%',
            color: AppColors.warning,
            onChanged: _isConnected ? _setLEDBrightness : null,
          ),
          const SizedBox(height: 16),

          // Motion Status
          _buildMotionCard(),
          const SizedBox(height: 20),

          // SOS Button
          _buildSOSButton(),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    final hour = DateTime.now().hour;
    String greeting;
    IconData icon;

    if (hour < 12) {
      greeting = 'Good Morning';
      icon = Icons.wb_sunny;
    } else if (hour < 18) {
      greeting = 'Good Afternoon';
      icon = Icons.wb_sunny;
    } else {
      greeting = 'Good Evening';
      icon = Icons.nightlight_round;
    }

    return Row(
      children: [
        Icon(icon, size: 32, color: AppColors.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'All systems normal',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMotionCard() {
    final motion = _latestData?.motionDetected ?? false;
    final distance = _latestData?.distanceDisplay ?? '--';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: motion
                    ? AppColors.success.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.motion_photos_on,
                size: 32,
                color: motion ? AppColors.success : Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Motion Status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    motion ? 'Motion Detected' : 'No Motion',
                    style: TextStyle(
                      fontSize: 16,
                      color: motion ? AppColors.success : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Distance: $distance',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSButton() {
    return ElevatedButton(
      onPressed: _isConnected ? _sendSOS : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.emergency,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.emergency, size: 40),
          SizedBox(width: 16),
          Text(
            'EMERGENCY HELP',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getTemperatureStatus() {
    if (_latestData == null) return 'Waiting...';
    final temp = _latestData!.temperature;
    if (temp < 18) return 'Too Cold';
    if (temp > 28) return 'Too Hot';
    return 'Comfortable';
  }

  String _getHumidityStatus() {
    if (_latestData == null) return 'Waiting...';
    final humidity = _latestData!.humidity;
    if (humidity < 30) return 'Too Dry';
    if (humidity > 70) return 'Too Humid';
    return 'Normal';
  }
}
