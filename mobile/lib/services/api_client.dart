import 'package:dio/dio.dart';

import '../config/app_env.dart';

/// Client HTTP centralisé (Dio) pour toutes les communications avec le backend.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppEnv.apiBaseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 6),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  String? _accessToken;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  String? get accessToken => _accessToken;

  Interceptor _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        // 401 géré globalement dans la Phase 3 (déconnexion + redirection).
        handler.next(error);
      },
    );
  }

  Dio get dio => _dio;
}
