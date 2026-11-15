import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_env.dart';

/// Client HTTP centralisé (Dio) pour toutes les communications avec le backend.
///
/// Le backend (Render, plan gratuit) dort après inactivité : le premier appel
/// peut prendre ~30-60 s à répondre. La stratégie est donc :
/// 1. un appel de réveil discret au démarrage et au retour au premier plan ;
/// 2. des lectures (GET) avec nouvel essai et délai croissant ;
/// 3. des messages d'erreur simples, jamais « hors ligne » (réservé au réseau réel).
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppEnv.apiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 12),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(_retryInterceptor());
    _dio.interceptors.add(_authInterceptor());
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  String? _accessToken;

  /// Appel de réveil discret : réveille le backend endormi sans bloquer l'UI.
  /// L'erreur éventuelle est ignorée — c'est juste un battement de cœur.
  Future<void> wake() async {
    try {
      await _dio.get<Map<String, dynamic>>(
        '/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 45),
          connectTimeout: const Duration(seconds: 45),
        ),
      );
    } catch (_) {
      // Réveil en arrière-plan : on ne remonte rien à l'utilisateur.
    }
  }

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  String? get accessToken => _accessToken;

  /// Nouvel essai automatique pour les LECTURES uniquement (idempotentes) :
  /// 2 tentatives supplémentaires avec délai croissant (1 s puis 3 s).
  InterceptorsWrapper _retryInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) async {
        final options = error.requestOptions;
        final isGet = options.method.toUpperCase() == 'GET';
        final attempt = (options.extra['retry_attempt'] as int?) ?? 0;
        final retriable = isGet &&
            attempt < 2 &&
            (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.sendTimeout ||
                error.type == DioExceptionType.connectionError);
        if (!retriable) {
          return handler.next(error);
        }
        options.extra['retry_attempt'] = attempt + 1;
        final delay = attempt == 0 ? const Duration(seconds: 1) : const Duration(seconds: 3);
        await Future<void>.delayed(delay);
        try {
          final response = await _dio.fetch<dynamic>(options);
          return handler.resolve(response);
        } on DioException catch (e) {
          return handler.next(e);
        }
      },
    );
  }

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        // 401 géré globalement (tentative de rafraîchissement du jeton côté AuthController).
        handler.next(error);
      },
    );
  }

  Dio get dio => _dio;
}
