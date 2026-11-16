import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart' show AuthSession;
import '../services/auth_repository.dart';
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
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Jeton refusé : on tente un rafraîchissement avant d'abandonner la session.
        final ok = await _refreshSession();
        if (!ok) {
          await AuthRepository.instance.clearSession();
          state = const AsyncData(null);
        }
        return;
      }
      // Backend injoignable : la session locale est conservée (repli local).
    } catch (_) {
      // Idem : jamais de déconnexion forcée sur une panne transitoire.
    }
  }

  /// Tente de renouveler la session via le refresh token.
  /// Retourne true si une nouvelle session est en place.
  Future<bool> _refreshSession() async {
    final current = state.value ?? await AuthRepository.instance.restoreSession();
    if (current == null) return false;
    try {
      final session = await AuthRepository.instance.refresh(current.refreshToken);
      await AuthRepository.instance.persistSession(session);
      state = AsyncData(session);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Revalidation complète : connectivité re-vérifiée par l'appelant,
  /// jeton rafraîchi si besoin. Appelée au retour au premier plan.
  Future<void> revalidate() async {
    final session = state.value;
    if (session == null) return;
    await _validateInBackground(session);
  }

  Future<void> register({
    required String displayName,
    required String phone,
    required String password,
    String? email,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await AuthRepository.instance.register(
        displayName: displayName,
        phone: phone,
        password: password,
        email: email,
      );
      return session;
    });
    if (state.hasValue) {
      ref.invalidate(walletControllerProvider);
    }
  }

  Future<void> login({required String phone, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return AuthRepository.instance.login(phone: phone, password: password);
    });
    if (state.hasValue) {
      ref.invalidate(walletControllerProvider);
    }
  }

  Future<void> logout() async {
    await AuthRepository.instance.logout();
    ref.invalidate(walletControllerProvider);
    state = const AsyncData(null);
  }

  Future<void> deleteAccount() async {
    await AuthRepository.instance.deleteAccount();
    ref.invalidate(walletControllerProvider);
    state = const AsyncData(null);
  }
  /// Message d'erreur lisible à partir d'une AsyncError.
  ///
  /// Retourne une chaîne VIDE pour les échecs de connectivité (timeout,
  /// serveur endormi, pas de réseau…) : tant que le réseau ne marche pas,
  /// RIEN ne doit s'afficher. Les vraies erreurs (validation, e-mail déjà
  /// utilisé, mot de passe incorrect…) gardent leur message actionnable.
  static String messageFrom(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final err = data['error'] as Map<String, dynamic>;
        if (err['message'] is String) return err['message'] as String;
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.badCertificate:
        case DioExceptionType.cancel:
          // Connectivité : silence tant que le réseau ne fonctionne pas.
          return '';
        case DioExceptionType.badResponse:
          return 'Le serveur rencontre un problème — réessaie dans un instant';
        default:
          // Connectivité (ou inconnue) : silence aussi.
          return '';
      }
    }
    if (error is FormatException || error is TypeError) {
      // Réponse inexploitable (version incompatible) : pas de message technique.
      return 'Réponse inattendue — réessaie dans un instant';
    }
    return '';
  }
}

/// Provider global de session d'authentification.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
