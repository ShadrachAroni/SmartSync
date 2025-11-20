import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/device_model.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/live_time_widget.dart';

class AddScheduledAutomationScreen extends ConsumerStatefulWidget {
  final String roomId;
  final List<DeviceModel> devices;

  const AddScheduledAutomationScreen({
    super.key,
    required this.roomId,
    required this.devices,
  });

  @override
  ConsumerState<AddScheduledAutomationScreen> createState() =>
      _AddScheduledAutomationScreenState();
}

class _AddScheduledAutomationScreenState
    extends ConsumerState<AddScheduledAutomationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _repeatDaily = true;
  List<int> _selectedDays = [1, 2, 3, 4, 5, 6, 7]; // All days by default
  final Map<String, bool> _selectedDevices = {};
  final Map<String, int> _deviceValues = {}; // Device ID -> value (0-100)
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize all devices as unselected
    for (var device in widget.devices) {
      _selectedDevices[device.id] = false;
      _deviceValues[device.id] = 50; // Default to 50%
    }
    Logger.debug('AddScheduledAutomationScreen: Initialized for room ${widget.roomId}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00BFA5),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1F3A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
      });
      final timeString = picked.format(context);
      Logger.debug('AddScheduledAutomationScreen: Time selected: $timeString');
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
      _selectedDays.sort();
    });
    Logger.debug('AddScheduledAutomationScreen: Days updated: $_selectedDays');
  }

  Future<void> _saveAutomation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedDeviceIds = _selectedDevices.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (selectedDeviceIds.isEmpty) {
      AppNotifications.showSnackBar(
        context,
        message: 'Please select at least one device',
        type: AppNotificationType.warning,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      // Create automation for each selected device
      for (var deviceId in selectedDeviceIds) {
        final device = widget.devices.firstWhere((d) => d.id == deviceId);
        final value = _deviceValues[deviceId] ?? 50;
        
        final automationRef = firestore.collection('automations').doc();
        final automationData = {
          'userId': user.uid,
          'roomId': widget.roomId,
          'deviceId': deviceId,
          'name': _nameController.text.trim(),
          'type': 'scheduled',
          'enabled': true,
          'hour': _selectedTime.hour,
          'minute': _selectedTime.minute,
          'repeatDaily': _repeatDaily,
          'daysOfWeek': _selectedDays,
          'action': {
            'type': device.type == DeviceType.fan ? 'setFanSpeed' : 'setBrightness',
            'value': value,
            'deviceType': device.type.toString().split('.').last,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        batch.set(automationRef, automationData);
        Logger.info('AddScheduledAutomationScreen: Creating automation for device $deviceId');
      }

      await batch.commit();
      Logger.success('AddScheduledAutomationScreen: Automation created successfully');

      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Scheduled automation created successfully',
        type: AppNotificationType.success,
      );
      Navigator.pop(context, true);
    } catch (e) {
      Logger.error('AddScheduledAutomationScreen: Error creating automation: $e');
      if (!mounted) return;
      AppNotifications.showSnackBar(
        context,
        message: 'Failed to create automation: ${e.toString()}',
        type: AppNotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text('Add Scheduled Automation'),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Live Time Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A1F3A),
                    const Color(0xFF0F1419),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Current Time',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LiveTimeWidget(
                    showSeconds: true,
                    showDayNight: true,
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Automation Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Automation Name',
                hintText: 'e.g., Morning Routine',
                filled: true,
                fillColor: const Color(0xFF1A1F3A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Time Selection
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Schedule Time',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _selectTime,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1419),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedTime.format(context),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Icon(Icons.access_time, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Repeat Daily Toggle
            SwitchListTile(
              title: const Text(
                'Repeat Daily',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Automation will run every day at the scheduled time',
                style: TextStyle(color: Colors.white70),
              ),
              value: _repeatDaily,
              onChanged: (value) {
                setState(() {
                  _repeatDaily = value;
                  if (value) {
                    _selectedDays = [1, 2, 3, 4, 5, 6, 7];
                  }
                });
              },
              activeColor: const Color(0xFF00BFA5),
            ),
            const SizedBox(height: 12),

            // Days of Week Selection (if not repeating daily)
            if (!_repeatDaily) ...[
              const Text(
                'Select Days',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _buildDayChip('Mon', 1),
                  _buildDayChip('Tue', 2),
                  _buildDayChip('Wed', 3),
                  _buildDayChip('Thu', 4),
                  _buildDayChip('Fri', 5),
                  _buildDayChip('Sat', 6),
                  _buildDayChip('Sun', 7),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Device Selection
            const Text(
              'Select Devices',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ...widget.devices.map((device) => _buildDeviceCard(device)),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveAutomation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Create Automation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayChip(String label, int day) {
    final isSelected = _selectedDays.contains(day);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _toggleDay(day),
      selectedColor: const Color(0xFF00BFA5),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildDeviceCard(DeviceModel device) {
    final isSelected = _selectedDevices[device.id] ?? false;
    final value = _deviceValues[device.id] ?? 50;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF1A1F3A)
            : const Color(0xFF0F1419),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF00BFA5)
              : Colors.white.withOpacity(0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    _selectedDevices[device.id] = value ?? false;
                  });
                },
                activeColor: const Color(0xFF00BFA5),
              ),
              Icon(
                device.icon,
                color: isSelected ? const Color(0xFF00BFA5) : Colors.white70,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  device.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          if (isSelected) ...[
            const SizedBox(height: 12),
            Text(
              device.type == DeviceType.fan ? 'Fan Speed' : 'Brightness',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$value%',
              activeColor: const Color(0xFF00BFA5),
              onChanged: (newValue) {
                setState(() {
                  _deviceValues[device.id] = newValue.round();
                });
              },
            ),
          ],
        ],
      ),
    );
  }
}

