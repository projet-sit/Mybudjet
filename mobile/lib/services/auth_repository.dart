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

  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'displayName': displayName,
      'email': email,
      'password': password,
    });
    return _saveSession(response.data['data'] as Map<String, dynamic>);
  }

  Future<AuthSession> login({required String email, required String password}) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
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
    final response = await _dio.post('/auth/forgot-password', data: {'email': email});
    return (response.data['data']['resetToken'] ?? '') as String;
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _dio.post('/auth/reset-password', data: {
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

  /// Efface la session locale ET le cache du portefeuille (déconnexion, 401, suppression).
  Future<void> clearSession() async {
    ApiClient.instance.setAccessToken(null);
    await _storage.clearSession();
    await CacheService.instance.clearWallet();
  }
}
