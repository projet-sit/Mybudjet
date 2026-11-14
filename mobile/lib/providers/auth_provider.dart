import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart' show AuthSession;
import '../services/auth_repository.dart';
import '../services/cache_service.dart';
import 'wallet_provider.dart';

/// Session courante (null si non connecté).
/// États exposés : chargement / session / échec (messages en français).
class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  FutureOr<AuthSession?> build() async {
    final session = await AuthRepository.instance.restoreSession();
    if (session != null) {
      // Validation en arrière-plan : l'app est déjà sur l'accueil avec les
      // données en cache ; on confirme juste que le token est toujours valide.
      unawaited(_validateInBackground(session));
    }
    return session;
  }

  Future<void> _validateInBackground(AuthSession session) async {
    try {
      final user = await AuthRepository.instance.me();
      final refreshed = AuthSession(
        user: user,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      await AuthRepository.instance.persistSession(refreshed);
      ref.read(offlineProvider.notifier).set(false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Token refusé : on ferme la session proprement (l'app retourne au login).
        await AuthRepository.instance.clearSession();
        state = const AsyncData(null);
        return;
      }
      // Hors ligne : la session locale est conservée (mode dégradé).
      ref.read(offlineProvider.notifier).set(true);
    } catch (_) {
      ref.read(offlineProvider.notifier).set(true);
    }
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await AuthRepository.instance.register(
        displayName: displayName,
        email: email,
        password: password,
      );
      return session;
    });
    if (state.hasValue) {
      ref.read(offlineProvider.notifier).set(false);
      ref.invalidate(walletControllerProvider);
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return AuthRepository.instance.login(email: email, password: password);
    });
    if (state.hasValue) {
      ref.read(offlineProvider.notifier).set(false);
      ref.invalidate(walletControllerProvider);
    }
  }

  Future<void> signInWithGoogle() async {
    final previousState = state;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return AuthRepository.instance.signInWithGoogle();
    });
    if (state.hasError && state.error is GoogleSignInCancelled) {
      // Annulation volontaire : on restaure l'état précédent sans erreur.
      state = previousState;
      return;
    }
    if (state.hasValue) {
      ref.read(offlineProvider.notifier).set(false);
      ref.invalidate(walletControllerProvider);
    }
  }
  Future<void> logout() async {
    await AuthRepository.instance.logout();
    ref.read(offlineProvider.notifier).set(false);
    ref.invalidate(walletControllerProvider);
    state = const AsyncData(null);
  }

  Future<void> deleteAccount() async {
    await AuthRepository.instance.deleteAccount();
    ref.read(offlineProvider.notifier).set(false);
    ref.invalidate(walletControllerProvider);
    state = const AsyncData(null);
  }
  /// Message d'erreur lisible à partir d'une AsyncError.
  static String messageFrom(Object error) {
    if (error is GoogleSignInFailure) return error.message;
    if (error is GoogleSignInCancelled) return 'Connexion Google annulée';
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final err = data['error'] as Map<String, dynamic>;
        if (err['message'] is String) return err['message'] as String;
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Délai dépassé — vérifie ta connexion';
        case DioExceptionType.sendTimeout:
          return 'Envoi trop long — vérifie ta connexion et réessaie';
        case DioExceptionType.connectionError:
          return 'Impossible de joindre le serveur — vérifie que l’API est démarrée et réessaie';
        case DioExceptionType.badCertificate:
          return 'Certificat du serveur invalide — contacte le support';
        case DioExceptionType.badResponse:
          return 'Le serveur n’a pas pu traiter la demande — réessaie';
        case DioExceptionType.cancel:
          return 'Demande annulée — réessaie';
        default:
          return 'Connexion au serveur impossible — vérifie ta connexion et réessaie';
      }
    }
    if (error is FormatException) {
      return 'Réponse du serveur invalide — vérifie que le backend est à jour';
    }
    if (error is TypeError) {
      return 'Réponse du serveur inattendue — vérifie que le backend est à jour';
    }
    return 'Connexion impossible — réessaie dans un instant';
  }
}

/// Provider global de session d'authentification.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
