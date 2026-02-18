import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

class ThemeService {
  static const _boxName = 'app_settings';
  static const _kThemeIndex = 'themeMode';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
  late final GetStorage _box;

  Future<void> init() async {
    await GetStorage.init(_boxName);
    _box = GetStorage(_boxName);
    final idx = _box.read<int>(_kThemeIndex) ?? 0;
    themeMode.value = _fromIndex(idx);
  }

  void setThemeIndex(int idx) {
    final mode = _fromIndex(idx);
    _box.write(_kThemeIndex, idx);
    themeMode.value = mode;
  }

  int get currentIndex => _toIndex(themeMode.value);

  ThemeMode _fromIndex(int idx) {
    switch (idx) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  int _toIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      case ThemeMode.system:
      default:
        return 0;
    }
  }
}
