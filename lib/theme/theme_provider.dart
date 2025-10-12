import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('themeMode');
    switch (v) {
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      case 'light':
        _mode = ThemeMode.light;
        break;
      default:
        _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'themeMode',
        switch (m) {
          ThemeMode.dark => 'dark',
          ThemeMode.light => 'light',
          _ => 'system',
        });
    notifyListeners();
  }
}
