import 'package:dio/dio.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'cache_service.dart';
import 'token_storage.dart';

class AuthRepository {
  AuthRepository._internal();

  static final AuthRepository instance = AuthRepository._internal();

  final Dio _dio = ApiClient.instance.dio;
  final TokenStorage _storage = TokenStorage();
  String? get currentAccessToken => ApiClient.instance.accessToken;

  /// POST vers l'API d'authentification avec réveil du serveur endormi
  /// (Render plan gratuit : ~30-60 s à se réveiller) et UN ré-essai.
  ///
  /// Sans ça, la première requête expire côté téléphone alors que le serveur
  /// est en train de démarrer — l'inscription "échoue" alors que le compte est
  /// parfois créé côté serveur.
  Future<Response<dynamic>> _postWithWakeRetry(
    String path,
    Map<String, dynamic> data,
  ) async {
    // Timeouts longs : le réveil Render peut dépasser la minute.
    final options = Options(
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 75),
      sendTimeout: const Duration(seconds: 30),
    );
    try {
      return await _dio.post(path, data: data, options: options);
    } on DioException catch (e) {
      if (!_isWakeRetriable(e)) rethrow;
      // Réveille le backend puis tente une seconde fois (une seule).
      await ApiClient.instance.wake();
      return _dio.post(path, data: data, options: options);
    }
  }

  bool _isWakeRetriable(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  Future<AuthSession> register({
    required String displayName,
    required String phone,
    required String password,
    String? email,
  }) async {
    try {
      final response = await _postWithWakeRetry('/auth/register', {
        'displayName': displayName,
        'phone': phone,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        'password': password,
      });
      return _saveSession(response.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      // 409 : le compte existait déjà — éventuellement CRÉÉ par une tentative
      // précédente qui avait expiré côté téléphone. On se connecte simplement
      // avec les mêmes identifiants au lieu d'afficher une erreur.
      if (e.response?.statusCode == 409) {
        return login(phone: phone, password: password);
      }
      rethrow;
    }
  }

  Future<AuthSession> login({required String phone, required String password}) async {
    final response = await _postWithWakeRetry('/auth/login', {
      'phone': phone,
      'password': password,
    });
    return _saveSession(response.data['data'] as Map<String, dynamic>);
  }

  Future<User> me() async {
    final response = await _dio.get('/auth/me');
    return User.fromJson(response.data['data']['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {    final session = await _storage.loadSession();
    try {
      await _dio.post('/auth/logout', data: {'refreshToken': session?.refreshToken});
    } catch (_) {
      // La déconnexion locale prime sur les erreurs réseau.
    }
    await clearSession();
  }

  Future<String> forgotPassword({required String email}) async {
    final response = await _postWithWakeRetry('/auth/forgot-password', {'email': email});
    return (response.data['data']['resetToken'] ?? '') as String;
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _postWithWakeRetry('/auth/reset-password', {
      'token': token,
      'newPassword': newPassword,
    });
  }

  /// Restaure la session sauvegardée SANS appeler le serveur :
  /// l'app démarre instantanément (les données sont ensuite validées/rafraîchies
  /// en arrière-plan par le contrôleur). Si le serveur refuse le token (401),
  /// la session est effacée en arrière-plan.
  Future<AuthSession?> restoreSession() async {
    final session = await _storage.loadSession();
    if (session == null) return null;
    ApiClient.instance.setAccessToken(session.accessToken);
    return session;
  }

  /// Renouvelle la session via le refresh token (jeton d'accès expiré) :
  /// nouveaux jetons puis /auth/me pour recharger le profil.
  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    final tokens = response.data['data']['tokens'] as Map<String, dynamic>;
    final accessToken = tokens['accessToken'] as String;
    final newRefreshToken = (tokens['refreshToken'] ?? refreshToken) as String;
    ApiClient.instance.setAccessToken(accessToken);
    final user = await me();
    final session = AuthSession(
      user: user,
      accessToken: accessToken,
      refreshToken: newRefreshToken,
    );
    await _storage.saveSession(session);
    return session;
  }

  /// Persiste la session courante (token + stockage).
  Future<AuthSession> persistSession(AuthSession session) async {
    ApiClient.instance.setAccessToken(session.accessToken);
    await _storage.saveSession(session);
    return session;
  }

  Future<AuthSession> _saveSession(Map<String, dynamic> data) async {
    final session = AuthSession.fromJson(data);
    ApiClient.instance.setAccessToken(session.accessToken);
    await _storage.saveSession(session);
    return session;
  }

  Future<void> deleteAccount() async {
    await _dio.delete('/auth/me');
    await clearSession();
  }

  /// Réinitialisation complète du compte : supprime TOUTES les données côté
  /// serveur (une seule transaction), puis recharge le profil — ce qui retourne
  /// le nouveau data_epoch — et met à jour la session locale.
  /// Les jetons restent valides (session conservée).
  Future<AuthSession> resetAccount() async {
    await _postWithWakeRetry('/me/reset', {});
    final user = await me();
    final session = await _storage.loadSession();
    if (session == null) throw Exception('Session introuvable');
    final refreshed = AuthSession(
      user: user,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    return persistSession(refreshed);
  }

  /// Efface la session locale ET le cache du portefeuille (déconnexion, 401, suppression).
  Future<void> clearSession() async {
    ApiClient.instance.setAccessToken(null);
    await _storage.clearSession();
    await CacheService.instance.clearWallet();
  }
}
