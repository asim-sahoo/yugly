import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Theme provider to handle theme changes across the app
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFFFCAA38); // Default amber/orange

  // Getters
  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;

  // Constructor loads saved preferences
  ThemeProvider() {
    _loadPreferences();
  }

  // Load saved preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('themeMode') ?? 'system';
    final accentColorValue = prefs.getInt('accentColor') ?? 0xFFFCAA38;

    _themeMode = _stringToThemeMode(themeModeString);
    _accentColor = Color(accentColorValue);
    notifyListeners();
  }

  // Convert string to ThemeMode
  ThemeMode _stringToThemeMode(String themeModeString) {
    switch (themeModeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // Set theme mode and save to preferences
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString().split('.').last);
    notifyListeners();
  }

  // Set accent color and save to preferences
  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentColor', color.value);
    notifyListeners();
  }
}