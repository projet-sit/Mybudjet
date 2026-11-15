import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';

/// Rapport de plantage minimaliste vers le backend (`POST /client-errors`).
///
/// Sans SDK externe : message + pile + écran + version, fire-and-forget.
/// Jamais d'exception propagée, jamais d'attente pour l'UI, au plus un
/// rapport toutes les 30 s (anti-tempestes).
abstract final class ErrorReporter {
  ErrorReporter._();

  static DateTime? _lastSent;
  static String? _cachedVersion;

  /// Branche les hooks globaux — à appeler une seule fois au démarrage.
  static void installGlobalHooks() {
    FlutterError.onError = (details) {
      // On garde le comportement d'origine (afficher dans la console).
      FlutterError.presentError(details);
      reportError(error: details.exception, stack: details.stack, screen: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      reportError(error: error, stack: stack, screen: 'app');
      return true; // erreur considérée comme traitée, pas de crash brut
    };
  }

  /// Déclare une erreur capturée (écran, zone, handler).
  static Future<void> reportError({
    Object? error,
    StackTrace? stack,
    String? screen,
  }) async {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < const Duration(seconds: 30)) {
      return; // anti-tempestes : au plus un rapport / 30 s
    }
    _lastSent = now;

    String? version = _cachedVersion;
    try {
      version ??= (await PackageInfo.fromPlatform()).version;
      _cachedVersion = version;
    } catch (_) {
      version = null;
    }

    String truncate(String? value, int max) {
      if (value == null) return '';
      return value.length <= max ? value : value.substring(0, max);
    }

    try {
      await Dio(BaseOptions(
        baseUrl: ApiClient.instance.dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
        sendTimeout: const Duration(seconds: 3),
        headers: {'Content-Type': 'application/json'},
      )).post('/client-errors', data: {
        'message': truncate(error?.toString(), 300),
        'stack': truncate(stack?.toString(), 1500),
        'screen': truncate(screen, 80),
        'platform': 'flutter',
        'appVersion': version,
      });
    } catch (_) {
      // Un rapport d'erreur ne doit JAMAIS faire crasher l'app.
    }
  }
}
