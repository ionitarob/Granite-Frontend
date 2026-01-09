import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemePrefKey = 'user_theme_is_dark_v1';

/// Minimal ThemeController used by the sidebar. In the real app this would
/// manage app-wide theme state and persistence.
class ThemeController extends ChangeNotifier {
  bool _isDark = true;

  bool get isDark => _isDark;

  ThemeController() {
    // Load persisted preference asynchronously. This won't block UI; once
    // loaded, listeners are notified to rebuild with the correct theme.
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_kThemePrefKey)) {
        _isDark = prefs.getBool(_kThemePrefKey) ?? true;
        notifyListeners();
      }
    } catch (_) {
      // ignore errors and keep default
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kThemePrefKey, _isDark);
    } catch (_) {
      // ignore
    }
  }

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
    _saveToPrefs();
  }
}
