import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thème clair/sombre persistant (Profil → Mode sombre).
class ThemeController extends AsyncNotifier<ThemeMode> {
  static const _key = 'theme_dark';

  @override
  FutureOr<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) == true ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setDark(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dark);
    state = AsyncData(dark ? ThemeMode.dark : ThemeMode.light);
  }
}

final themeControllerProvider =
    AsyncNotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// Alertes de budget activées/désactivées (Profil).
class AlertsController extends AsyncNotifier<bool> {
  static const _key = 'budget_alerts';

  @override
  FutureOr<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
    state = AsyncData(enabled);
  }
}

final alertsEnabledProvider =
    AsyncNotifierProvider<AlertsController, bool>(AlertsController.new);
