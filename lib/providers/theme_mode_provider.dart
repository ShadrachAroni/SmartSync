import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current theme mode (light / dark / system)
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);
