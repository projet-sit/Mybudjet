import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../models/wallet.dart';
import '../services/cache_service.dart';
import '../services/outbox.dart';
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
      return cached;
    }
    throw StateError('Synchronisation indisponible et aucune donnée enregistrée');
  }

  Future<void> _refreshInBackground() async {
    try {
      final wallet = await WalletRepository.instance.first();
      if (wallet != null) {
        await CacheService.instance.saveWallet(wallet);
      }
      state = AsyncData(wallet);
    } catch (_) {
      // Backend injoignable : on garde le portefeuille en cache (repli local).
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
      return wallet;
    });
  }

  /// Verse un montant à l'épargne (argent sorti du Reste, atomique).
  /// Hors-ligne : mise en attente + application optimiste immédiate.
  Future<void> savingsDeposit(int amount) => _savingsMove(amount, isDeposit: true);

  /// Retire un montant de l'épargne (retour dans le Reste, atomique).
  Future<void> savingsWithdraw(int amount) => _savingsMove(amount, isDeposit: false);

  /// « Tout récupérer » : toute l'épargne retourne dans le Reste, atomique.
  Future<WriteResult> savingsWithdrawAll() async {
    final current = state.value;
    if (current == null) return const WriteResult.sent();
    try {
      final updated = await WalletRepository.instance.savingsWithdrawAll(current.id);
      await CacheService.instance.saveWallet(updated);
      state = AsyncData(updated);
      return const WriteResult.sent();
    } on DioException catch (e) {
      if (_isNetworkish(e)) {
        final tx = Transaction(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          walletId: current.id,
          type: 'savings_withdrawal',
          amount: current.savingsAmount > 0 ? current.savingsAmount : 0,
          category: 'Épargne',
          description: null,
          date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          time: DateFormat('HH:mm').format(DateTime.now()),
        );
        if (current.savingsAmount > 0) {
          // L'overlay applique la totalité : l'épargne passe à 0 côté cache.
          await Outbox.instance.applyPendingTransactionLocally(current.id, tx);
        }
        await Outbox.instance.enqueueSavings(current.id, kind: OutboxKind.savingsWithdrawAll);
        final updated = await CacheService.instance.loadWallet();
        if (updated != null) state = AsyncData(updated);
        return const WriteResult.queued();
      }
      rethrow;
    }
  }

  Future<void> _savingsMove(int amount, {required bool isDeposit}) async {
    final current = state.value;
    if (current == null) return;
    try {
      final updated = isDeposit
          ? await WalletRepository.instance.savingsDeposit(current.id, amount)
          : await WalletRepository.instance.savingsWithdraw(current.id, amount);
      await CacheService.instance.saveWallet(updated);
      state = AsyncData(updated);
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow; // refus métier : on laisse l'écran afficher
      final tx = Transaction(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        walletId: current.id,
        type: isDeposit ? 'savings_deposit' : 'savings_withdrawal',
        amount: amount,
        category: 'Épargne',
        description: null,
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        time: DateFormat('HH:mm').format(DateTime.now()),
      );
      await Outbox.instance.applyPendingTransactionLocally(current.id, tx);
      await Outbox.instance.enqueueSavings(
        current.id,
        kind: isDeposit ? OutboxKind.savingsDeposit : OutboxKind.savingsWithdraw,
        amount: amount,
      );
      final updated = await CacheService.instance.loadWallet();
      if (updated != null) state = AsyncData(updated);
    }
  }

  bool _isNetworkish(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) return true;
    return status >= 500;
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
    // revalidation (repli cache instantané, se termine toujours).
    state = await AsyncValue.guard(() async {
      try {
        final wallet = await WalletRepository.instance.first();
        if (wallet != null) {
          await CacheService.instance.saveWallet(wallet);
        }
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
      return 'Synchronisation indisponible — réessayez';
    }
    return 'Une erreur est survenue';
  }
}

final walletControllerProvider =
    AsyncNotifierProvider<WalletController, Wallet?>(WalletController.new);
