import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wallet.dart';
import '../services/cache_service.dart';
import '../services/wallet_repository.dart';

/// Portefeuille courant de l'utilisateur (null si aucun).
///
/// Stratégie hors-ligne « données réelles uniquement » :
/// 1. au démarrage : affiche immédiatement le dernier portefeuille réel connu
///    (cache), puis valide/rafraîchit depuis le serveur EN arrière-plan ;
/// 2. si rien n'est en cache : charge depuis le réseau (et cache le résultat) ;
/// 3. en cas d'échec réseau sans cache : erreur (écran « réessayer »).
class WalletController extends AsyncNotifier<Wallet?> {
  @override
  FutureOr<Wallet?> build() async {
    final cached = await CacheService.instance.loadWallet();
    if (cached != null) {
      unawaited(_refreshInBackground());
      return cached;
    }
    return _loadFromNetwork();
  }

  Future<Wallet?> _loadFromNetwork() async {
    try {
      final wallet = await WalletRepository.instance.first();
      if (wallet != null) {
        await CacheService.instance.saveWallet(wallet);
      }
      ref.read(offlineProvider.notifier).set(false);
      return wallet;
    } on DioException catch (_) {
      return _fallbackToCache();
    } catch (_) {
      return _fallbackToCache();
    }
  }

  Future<Wallet?> _fallbackToCache() async {
    final cached = await CacheService.instance.loadWallet();
    if (cached != null) {
      ref.read(offlineProvider.notifier).set(true);
      return cached;
    }
    throw StateError('Hors ligne et aucune donnée enregistrée');
  }

  Future<void> _refreshInBackground() async {
    try {
      final wallet = await WalletRepository.instance.first();
      if (wallet != null) {
        await CacheService.instance.saveWallet(wallet);
      }
      ref.read(offlineProvider.notifier).set(false);
      state = AsyncData(wallet);
    } catch (_) {
      // Hors ligne : on garde le portefeuille en cache (mode dégradé).
      ref.read(offlineProvider.notifier).set(true);
    }
  }

  Future<void> create({
    required String name,
    required int initialAmount,
    required String startDate,
    String currency = 'XOF',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final wallet = await WalletRepository.instance.create(
        name: name,
        initialAmount: initialAmount,
        startDate: startDate,
        currency: currency,
      );
      await CacheService.instance.saveWallet(wallet);
      ref.read(offlineProvider.notifier).set(false);
      return wallet;
    });
  }

  /// Met de côté un montant dans le même compte (0 = tout récupérer).
  /// Lève une erreur en cas de refus serveur (montant > solde).
  Future<void> setSavings(int amount) async {
    final current = state.value;
    if (current == null) return;
    final updated = await WalletRepository.instance.setSavings(current.id, amount);
    await CacheService.instance.saveWallet(updated);
    state = AsyncData(updated);
  }

  Future<void> updateInitialAmount(int newAmount) async {
    final current = state.value;
    if (current == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await WalletRepository.instance.updateInitialAmount(current.id, newAmount);
      await CacheService.instance.saveWallet(updated);
      return updated;
    });
  }

  Future<void> refresh() async {
    // Pas d'AsyncLoading : on garde les données en cache affichées pendant la
    // revalidation réseau (pull-to-refresh fluide, sans spinner hors-ligne).
    state = await AsyncValue.guard(() async {
      try {
        final wallet = await WalletRepository.instance.first();
        if (wallet != null) {
          await CacheService.instance.saveWallet(wallet);
        }
        ref.read(offlineProvider.notifier).set(false);
        return wallet;
      } catch (_) {
        return _fallbackToCache();
      }
    });
  }

  /// Met à jour le portefeuille sans repasser par un écran de chargement.
  void setWallet(Wallet wallet) {
    unawaited(CacheService.instance.saveWallet(wallet));
    state = AsyncData(wallet);
  }

  static String messageFrom(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final err = data['error'] as Map<String, dynamic>;
        if (err['message'] is String) return err['message'] as String;
      }
      return 'Erreur réseau — vérifie ta connexion';
    }
    return 'Une erreur est survenue';
  }
}

final walletControllerProvider =
    AsyncNotifierProvider<WalletController, Wallet?>(WalletController.new);
