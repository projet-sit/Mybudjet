import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_env.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'cache_service.dart';
import 'token_storage.dart';

/// Annulation volontaire du flux Google (ne pas afficher d'erreur).
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// Échec Google : message déjà rédigé en français, affichable tel quel.
class GoogleSignInFailure implements Exception {
  final String message;
  const GoogleSignInFailure(this.message);
}

/// Connexion Google demandée alors que GOOGLE_SERVER_CLIENT_ID est vide.
class GoogleSignInNotConfigured extends GoogleSignInFailure {
  const GoogleSignInNotConfigured()
      : super('Connexion Google non configurée — crée le client OAuth dans Google Cloud Console et renseigne GOOGLE_SERVER_CLIENT_ID');
}

class AuthRepository {
  AuthRepository._internal();

  static final AuthRepository instance = AuthRepository._internal();

  final Dio _dio = ApiClient.instance.dio;
  final TokenStorage _storage = TokenStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: AppEnv.googleServerClientId.isEmpty ? null : AppEnv.googleServerClientId,
  );
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

  Future<AuthSession> signInWithGoogle() async {
    if (AppEnv.googleServerClientId.isEmpty) {
      throw const GoogleSignInNotConfigured();
    }
    final GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signIn();
    } on PlatformException catch (e) {
      // 10 / 12500 : DEVELOPER_ERROR = SHA-1 ou client OAuth Android manquant.
      final code = e.code.toLowerCase();
      final details = '${e.message} ${e.details}'.toLowerCase();
      if (details.contains('12500') ||
          details.contains('12501') ||
          details.contains('developer') ||
          details.contains(': 10') ||
          (code.contains('sign_in_failed') && details.trim().endsWith('10'))) {
        throw const GoogleSignInFailure(
          'Configuration Google invalide — ajoute le package et le SHA-1 de l’app dans Google Cloud Console',
        );
      }
      if (code.contains('network') || details.contains('network')) {
        throw const GoogleSignInFailure('Réseau indisponible — vérifie ta connexion et réessaie');
      }
      throw GoogleSignInFailure('Connexion Google impossible — réessaie ($code)');
    } catch (_) {
      throw const GoogleSignInFailure('Connexion Google impossible — réessaie dans un instant');
    }
    if (account == null) {
      throw const GoogleSignInCancelled();
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const GoogleSignInFailure(
        'Token Google manquant — vérifie que GOOGLE_SERVER_CLIENT_ID (client OAuth Web) est défini dans .env',
      );
    }
    final response = await _dio.post('/auth/google', data: {'idToken': idToken});
    return _saveSession(response.data['data'] as Map<String, dynamic>);
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
