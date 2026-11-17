import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/dashboard.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import 'api_client.dart';
import 'cache_service.dart';
import 'category_repository.dart';
import 'data_repository.dart';

/// File d'attente persistante des écritures faites hors-ligne ou lorsque le
/// backend est injoignable (Render endormi, réseau coupé…).
///
/// Principes :
/// - chaque opération est rejouée dans l'ordre (id UUID stable) ;
/// - un échec réseau conserve l'opération (nouvel essai au retour du réseau) ;
/// - une erreur de validation (4xx métier) abandonne l'opération, jamais de boucle infinie ;
/// - les opérations sont aussi appliquées localement en cache pour que l'app
///   reste immédiatement cohérente (solde, épargne, liste des opérations).
abstract final class OutboxKind {
  static const transactionCreate = 'transaction_create';
  static const transactionUpdate = 'transaction_update';
  static const transactionDelete = 'transaction_delete';
  static const savingsDeposit = 'savings_deposit';
  static const savingsWithdraw = 'savings_withdraw';
  static const savingsWithdrawAll = 'savings_withdraw_all';
  static const budgetUpsert = 'budget_upsert';
  static const budgetDelete = 'budget_delete';
  static const categoryCreate = 'category_create';
}

class OutboxOp {
  const OutboxOp({
    required this.id,
    required this.kind,
    required this.walletId,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String walletId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory OutboxOp.fromJson(Map<String, dynamic> json) => OutboxOp(
        id: json['id'] as String,
        kind: json['kind'] as String,
        walletId: (json['walletId'] ?? '') as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'walletId': walletId,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Résultat d'un flush : combien d'opérations rejouées + échecs définitifs.
class FlushResult {
  const FlushResult({required this.replayed, required this.failures});

  final int replayed;
  final List<FlushFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

class FlushFailure {
  const FlushFailure({required this.opId, required this.kind, required this.message});

  final String opId;
  final String kind;
  final String message;
}

/// Résultat d'une écriture : soit envoyée, soit mise en attente.
class WriteResult {
  const WriteResult._(this.queued, this.transaction);
  const WriteResult.sent({Transaction? transaction}) : this._(false, transaction);
  const WriteResult.queued() : this._(true, null);

  final bool queued;
  final Transaction? transaction;
}

class Outbox {
  Outbox._internal();
  static final Outbox instance = Outbox._internal();

  static const _opsKey = 'outbox_ops';
  static const _pendingTxKey = 'outbox_pending_transactions';
  static const _deletedIdsKey = 'outbox_deleted_transaction_ids';
  static const _updatedTxKey = 'outbox_updated_transactions';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Identifiant local pour une transaction créée hors-ligne.
  String newLocalId() => 'local_${const Uuid().v4()}';
  bool isLocalId(String id) => id.startsWith('local_');

  // ---------- Persistance des opérations ----------

  Future<List<OutboxOp>> _load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_opsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => OutboxOp.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<OutboxOp> ops) async {
    final prefs = await _prefs;
    await prefs.setString(_opsKey, jsonEncode(ops.map((o) => o.toJson()).toList()));
  }

  Future<int> count() async => (await _load()).length;

  Future<void> enqueue(OutboxOp op) async {
    final ops = await _load();
    ops.add(op);
    await _save(ops);
  }

  Future<void> _remove(String id) async {
    final ops = await _load();
    ops.removeWhere((o) => o.id == id);
    await _save(ops);
  }

  /// Met à jour le limitAmount d'une opération budgetUpsert en attente.
  Future<void> updatePendingUpsertAmount(String id, int limitAmount) async {
    final ops = await _load();
    final idx = ops.indexWhere((o) => o.id == id && o.kind == OutboxKind.budgetUpsert);
    if (idx < 0) return;
    final op = ops[idx];
    ops[idx] = OutboxOp(
      id: op.id,
      kind: op.kind,
      walletId: op.walletId,
      payload: {...op.payload, 'limitAmount': limitAmount},
      createdAt: op.createdAt,
    );
    await _save(ops);
  }

  /// Retire une opération précise de la file (ex. création jamais synchronisée
  /// supprimée avant envoi).
  Future<void> removePendingOp(String id) async {
    final ops = await _load();
    ops.removeWhere((o) => o.id == id || o.payload['id'] == id);
    await _save(ops);
    final pending = await pendingTransactions();
    pending.removeWhere((t) => t.id == id);
    await _savePendingTransactions(pending);
    final updates = await updatedTransactions();
    updates.remove(id);
    await _saveUpdatedTransactions(updates);
  }

  // ---------- Overlay local (transactions créées/supprimées/modifiées) ----------

  Future<List<Transaction>> pendingTransactions() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_pendingTxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Transaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((t) => t.id.startsWith('local_'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingTransactions(List<Transaction> txs) async {
    final prefs = await _prefs;
    await prefs.setString(_pendingTxKey, jsonEncode(txs.map((t) => t.toJson()).toList()));
  }

  Future<Set<String>> deletedTransactionIds() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_deletedIdsKey);
    return (raw ?? const <String>[]).toSet();
  }

  Future<void> _saveDeletedIds(Set<String> ids) async {
    final prefs = await _prefs;
    if (ids.isEmpty) {
      await prefs.remove(_deletedIdsKey);
    } else {
      await prefs.setStringList(_deletedIdsKey, ids.toList());
    }
  }

  /// Transactions mises en attente de modification (id -> nouvelle version).
  Future<Map<String, Transaction>> updatedTransactions() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_updatedTxKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, Transaction.fromJson(Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUpdatedTransactions(Map<String, Transaction> txs) async {
    final prefs = await _prefs;
    if (txs.isEmpty) {
      await prefs.remove(_updatedTxKey);
    } else {
      await prefs.setString(
        _updatedTxKey,
        jsonEncode(txs.map((k, v) => MapEntry(k, v.toJson()))),
      );
    }
  }

  /// Point de coupure local : les opérations créées après ce marqueur
  /// Applique l'overlay (pending + supprimées) sur une liste de transactions
  /// (issue du réseau ou du cache).
  Future<List<Transaction>> applyOverlay(List<Transaction> base) async {
    final pending = await pendingTransactions();
    final deleted = await deletedTransactionIds();
    final updates = await updatedTransactions();

    final merged = <String, Transaction>{};
    for (final tx in base) {
      if (deleted.contains(tx.id)) continue;
      merged[tx.id] = updates[tx.id] ?? tx;
    }
    for (final tx in pending) {
      if (deleted.contains(tx.id)) continue;
      merged[tx.id] = updates[tx.id] ?? tx;
    }
    final result = merged.values.toList()
      ..sort((a, b) {
        final cmp = b.date.compareTo(a.date);
        if (cmp != 0) return cmp;
        return b.time.compareTo(a.time);
      });
    return result;
  }

  // ---------- Overlay local (transactions créées/supprimées/modifiées) ----------

  // ---------- Écritures : tentative serveur puis mise en attente ----------

  /// Crée une transaction. En ligne : serveur + résultat réel.
  /// Hors-ligne : mise en attente + application optimiste locale.
  Future<WriteResult> createTransaction(String walletId, Transaction tx) async {
    final local = tx.id.isEmpty || isLocalId(tx.id);
    final toSend = local ? tx.copyWith(id: '') : tx;
    try {
      final result = await TransactionRepository.instance.create(walletId, toSend);
      return WriteResult.sent(transaction: result.transaction);
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow; // erreur métier : on laisse l'écran afficher
      final queuedTx = local
          ? tx.copyWith(id: newLocalId())
          : tx; // id serveur impossible hors-ligne : on garde l'id local
      await _applyCreateLocally(walletId, queuedTx);
      await enqueue(OutboxOp(
        id: queuedTx.id,
        kind: OutboxKind.transactionCreate,
        walletId: walletId,
        payload: queuedTx.toRequest(),
        createdAt: DateTime.now(),
      ));
      return const WriteResult.queued();
    }
  }

  Future<WriteResult> updateTransaction(String walletId, Transaction tx) async {
    try {
      final result = await TransactionRepository.instance.update(walletId, tx.id, tx);
      return WriteResult.sent(transaction: result.transaction);
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow;
      if (isLocalId(tx.id)) {
        // Modification d'une transaction pas encore synchronisée : on met à jour l'overlay.
        final pending = await pendingTransactions();
        final idx = pending.indexWhere((t) => t.id == tx.id);
        if (idx >= 0) {
          pending[idx] = tx;
          await _savePendingTransactions(pending);
        }
      } else {
        final updates = await updatedTransactions();
        updates[tx.id] = tx;
        await _saveUpdatedTransactions(updates);
      }
      await enqueue(OutboxOp(
        id: tx.id,
        kind: OutboxKind.transactionUpdate,
        walletId: walletId,
        payload: {'id': tx.id, ...tx.toRequest()},
        createdAt: DateTime.now(),
      ));
      return const WriteResult.queued();
    }
  }

  Future<WriteResult> deleteTransaction(String walletId, Transaction tx) async {
    try {
      await TransactionRepository.instance.delete(walletId, tx.id);
      return const WriteResult.sent();
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow;
      if (isLocalId(tx.id)) {
        final pending = await pendingTransactions();
        pending.removeWhere((t) => t.id == tx.id);
        await _savePendingTransactions(pending);
        // Annule l'effet optimiste de la création en attente.
        await _adjustCachedWalletForTx(walletId, tx, sign: -1);
        // Annule l'opération de création en attente s'il y en avait une.
        final ops = await _load();
        ops.removeWhere((o) => o.id == tx.id && o.kind == OutboxKind.transactionCreate);
        await _save(ops);
        return const WriteResult.queued();
      }
      final deleted = await deletedTransactionIds();
      deleted.add(tx.id);
      await _saveDeletedIds(deleted);
      // Effet optimiste : le solde reprend la contribution de la transaction supprimée.
      await _adjustCachedWalletForTx(walletId, tx, sign: -1);
      await enqueue(OutboxOp(
        id: tx.id,
        kind: OutboxKind.transactionDelete,
        walletId: walletId,
        payload: {'id': tx.id, 'tx': tx.toJson()},
        createdAt: DateTime.now(),
      ));
      return const WriteResult.queued();
    }
  }

  /// Applique une opération locale de façon optimiste :
  /// ajoute la transaction aux opérations en attente et corrige les caches
  /// portefeuille + dashboard (solde, épargne, totaux, dernières opérations).
  Future<void> applyPendingTransactionLocally(String walletId, Transaction tx) async {
    final pending = await pendingTransactions();
    if (!pending.any((t) => t.id == tx.id)) {
      pending.add(tx);
      await _savePendingTransactions(pending);
    }
    await _adjustCachedWalletForTx(walletId, tx, sign: 1);
  }

  Future<void> _applyCreateLocally(String walletId, Transaction tx) async {
    await applyPendingTransactionLocally(walletId, tx);
  }

  Future<void> adjustCachedWalletForTx(
    String walletId,
    Transaction tx, {
    int sign = 1,
  }) =>
      _adjustCachedWalletForTx(walletId, tx, sign: sign);

  /// Contribution d'une transaction au solde (savings : 0, le solde ne bouge pas).
  static int balanceDeltaOf(Transaction tx) {
    switch (tx.type) {
      case 'expense':
        return -tx.amount;
      case 'income':
        return tx.amount;
      default:
        return 0;
    }
  }

  /// Contribution d'une transaction à l'épargne.
  static int savingsDeltaOf(Transaction tx) {
    switch (tx.type) {
      case 'savings_deposit':
        return tx.amount;
      case 'savings_withdrawal':
        return -tx.amount;
      default:
        return 0;
    }
  }

  Future<void> _adjustCachedWalletForTx(String walletId, Transaction tx, {required int sign}) async {
    final delta = balanceDeltaOf(tx) * sign;
    final savingsDelta = savingsDeltaOf(tx) * sign;
    if (delta == 0 && savingsDelta == 0) return;
    // Modification des caches portefeuille + dashboard (meilleure source affichée immédiatement).
    final walletJson = await _readCachedWalletJson();
    if (walletJson != null && walletJson['id'] == walletId) {
      final balance = (walletJson['balance'] as num).toInt() + delta;
      final savings = ((walletJson['savingsAmount'] as num?)?.toInt() ?? 0) + savingsDelta;
      walletJson['balance'] = balance;
      walletJson['savingsAmount'] = savings < 0 ? 0 : savings;
      await _writeCachedWalletJson(walletJson);
    }
    final dashRaw = await _readCachedDashboard(walletId);
    if (dashRaw != null) {
      dashRaw['balance'] = ((dashRaw['balance'] as num?)?.toInt() ?? 0) + delta;
      if (tx.type == 'expense') {
        dashRaw['totalExpenses'] = ((dashRaw['totalExpenses'] as num?)?.toInt() ?? 0) + sign * tx.amount;
      } else if (tx.type == 'income') {
        dashRaw['totalIncomes'] = ((dashRaw['totalIncomes'] as num?)?.toInt() ?? 0) + sign * tx.amount;
      }
      dashRaw['transactionsCount'] = ((dashRaw['transactionsCount'] as num?)?.toInt() ?? 0) + sign;
      final latest = (dashRaw['latestTransactions'] as List?) ?? <Map<String, dynamic>>[];
      if (sign > 0) {
        dashRaw['latestTransactions'] = [tx.toJson(), ...latest].take(5).toList();
      } else {
        dashRaw['latestTransactions'] = latest
            .where((t) => (t as Map)['id'] != tx.id)
            .toList();
      }
      await _writeCachedDashboard(walletId, dashRaw);
    }
  }

  Future<Map<String, dynamic>?> _readCachedWalletJson() async {
    final prefs = await _prefs;
    final raw = prefs.getString('cache_wallet');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedWalletJson(Map<String, dynamic> json) async {
    final prefs = await _prefs;
    await prefs.setString('cache_wallet', jsonEncode(json));
  }

  Future<Map<String, dynamic>?> _readCachedDashboard(String walletId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('cache_dashboard_$walletId');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedDashboard(String walletId, Map<String, dynamic> json) async {
    final prefs = await _prefs;
    await prefs.setString('cache_dashboard_$walletId', jsonEncode(json));
  }

  // ---------- Flush ----------

  /// Retire l'overlay budgétaire (opérations en attente) sur une liste de budgets.
  Future<List<Budget>> applyBudgetOverlay(List<Budget> base) async {
    final ops = await _load();
    var result = List<Budget>.from(base);
    for (final op in ops) {
      if (op.kind == OutboxKind.budgetDelete) {
        final id = op.payload['id'] as String?;
        if (id != null) result.removeWhere((b) => b.id == id);
        continue;
      }
      if (op.kind == OutboxKind.budgetUpsert) {
        final id = op.payload['id'] as String? ?? op.id;
        final category = (op.payload['category'] ?? '') as String;
        final limit = (op.payload['limitAmount'] as num?)?.toInt() ?? 0;
        final idx = result.indexWhere((b) => b.id == id);
        if (idx >= 0) {
          final old = result[idx];
          result[idx] = Budget(
            id: old.id,
            walletId: old.walletId,
            category: category.isNotEmpty ? category : old.category,
            limitAmount: limit > 0 ? limit : old.limitAmount,
            spent: old.spent,
            percent: limit > 0 ? ((old.spent / limit) * 100).round() : old.percent,
            alertLevel: old.alertLevel,
          );
        } else if (category.isNotEmpty && limit > 0) {
          result.add(Budget(
            id: id,
            walletId: op.walletId,
            category: category,
            limitAmount: limit,
          ));
        }
      }
    }
    return result;
  }

  bool _isNetworkish(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) return true; // pas de réponse = réseau/backend injoignable
    if (status >= 500) return true;
    return false;
  }

  /// Rejoue les opérations en attente, dans l'ordre. S'arrête à la première
  /// erreur réseau (les suivantes attendront le prochain passage).
  ///
  /// - erreur réseau/timeout : l'opération est conservée, elle sera rejouée ;
  /// - erreur métier définitive (4xx) ou autre exception : l'opération est
  ///   abandonnée ET l'effet optimiste local est annulé (rollback), et le
  ///   problème est remonté à l'utilisateur via [FlushResult.failures].
  Future<FlushResult> flush() async {
    var replayed = 0;
    final failures = <FlushFailure>[];
    while (true) {
      final ops = await _load();
      if (ops.isEmpty) break;
      final op = ops.first;
      try {
        await _execute(op);
      } on DioException catch (e) {
        if (_isNetworkish(e)) break; // encore injoignable : on réessaie plus tard
        await _rollbackOp(op);
        failures.add(FlushFailure(opId: op.id, kind: op.kind, message: _errorMessage(e)));
        await _remove(op.id);
        continue;
      } catch (e) {
        await _rollbackOp(op);
        failures.add(FlushFailure(opId: op.id, kind: op.kind, message: _errorMessage(e)));
        await _remove(op.id);
        continue;
      }
      await _remove(op.id);
      await _dropServerSideOverlay(op);
      replayed++;
      // Après une remise à zéro, le reste de la file se rejoue sur la nouvelle
      // période active : on continue normalement.
    }
    if (replayed > 0) {
      await clearOverlayIfAllSynced();
    }
    return FlushResult(replayed: replayed, failures: failures);
  }

  /// Message d'erreur lisible à partir d'une erreur d'exécution.
  static String _errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
        final message = (data['error'] as Map<String, dynamic>)['message'];
        if (message is String && message.trim().isNotEmpty) return message;
      }
      if (data is Map && data['message'] is String && (data['message'] as String).trim().isNotEmpty) {
        return data['message'] as String;
      }
      return 'Synchronisation indisponible — réessayez';
    }
    return 'Une erreur est survenue';
  }

  /// Annule l'effet optimiste local d'une opération refusée définitivement,
  /// pour que le cache redevienne cohérent sans action de l'utilisateur.
  Future<void> _rollbackOp(OutboxOp op) async {
    switch (op.kind) {
      case OutboxKind.transactionCreate:
        // La transaction optimiste portait le même id : on la retire et on annule le solde.
        final pending = await pendingTransactions();
        final idx = pending.indexWhere((t) => t.id == op.id);
        if (idx >= 0) {
          final tx = pending.removeAt(idx);
          await _savePendingTransactions(pending);
          await _adjustCachedWalletForTx(op.walletId, tx, sign: -1);
        }
        break;
      case OutboxKind.transactionUpdate:
        final updates = await updatedTransactions();
        updates.remove(op.id);
        await _saveUpdatedTransactions(updates);
        break;
      case OutboxKind.transactionDelete:
        final deleted = await deletedTransactionIds();
        deleted.remove(op.id);
        await _saveDeletedIds(deleted);
        // Re-applique l'effet solde (l'opération « supprimer » échouant, la dépense réexiste).
        final raw = op.payload['tx'];
        if (raw is Map) {
          try {
            final tx = Transaction.fromJson(Map<String, dynamic>.from(raw));
            await _adjustCachedWalletForTx(op.walletId, tx, sign: 1);
          } catch (_) {
            // L'état serveur fera foi à la prochaine revalidation.
          }
        }
        break;
      case OutboxKind.savingsDeposit:
      case OutboxKind.savingsWithdraw:
      case OutboxKind.savingsWithdrawAll:
        final txId = op.payload['txId'] as String?;
        if (txId != null) {
          final pending = await pendingTransactions();
          final idx = pending.indexWhere((t) => t.id == txId);
          if (idx >= 0) {
            final tx = pending.removeAt(idx);
            await _savePendingTransactions(pending);
            await _adjustCachedWalletForTx(op.walletId, tx, sign: -1);
          }
        }
        break;
      case OutboxKind.budgetUpsert:
        if (op.id.startsWith('local_')) {
          // Budget jamais créé côté serveur : le purger du cache local.
          try {
            final budgets = await CacheService.instance.loadBudgets(op.walletId);
            if (budgets.any((b) => b.id == op.id)) {
              await CacheService.instance.saveBudgets(
                op.walletId,
                budgets
                    .where((b) => b.id != op.id)
                    .map((b) => b.toJson())
                    .toList(),
              );
            }
          } catch (_) {
            // La prochaine synchronisation corrigera le cache.
          }
        }
        break;
      case OutboxKind.budgetDelete:
        // Suppression refusée : le budget réapparaîtra à la prochaine revalidation.
        break;
      case OutboxKind.categoryCreate:
        try {
          final cached = await CategoryRepository.instance.loadCache();
          await CategoryRepository.instance.saveCache(
            cached.where((c) => c.id != op.id).toList(),
          );
        } catch (_) {
          // Le prochain chargement reconstituera le cache depuis le serveur.
        }
        break;
    }
  }

  /// Retire l'overlay local correspondant à une opération acceptée par le serveur.
  Future<void> _dropServerSideOverlay(OutboxOp op) async {
    final deleted = await deletedTransactionIds();
    final updates = await updatedTransactions();
    final pending = await pendingTransactions();
    switch (op.kind) {
      case OutboxKind.transactionCreate:
        pending.removeWhere((t) => t.id == op.id);
        deleted.remove(op.id);
        break;
      case OutboxKind.transactionUpdate:
        updates.remove(op.id);
        break;
      case OutboxKind.transactionDelete:
        deleted.remove(op.id);
        break;
      default:
        break;
    }
    await _savePendingTransactions(pending);
    await _saveUpdatedTransactions(updates);
    await _saveDeletedIds(deleted);
  }

  Future<void> clearOverlayIfAllSynced() async {
    final ops = await _load();
    if (ops.isEmpty) {
      await _savePendingTransactions(<Transaction>[]);
      await _saveDeletedIds(<String>{});
      await _saveUpdatedTransactions(<String, Transaction>{});
    }
  }

  Future<void> _execute(OutboxOp op) async {
    final dio = ApiClient.instance.dio;
    switch (op.kind) {
      case OutboxKind.transactionCreate:
        await dio.post('/wallets/${op.walletId}/transactions', data: op.payload);
        break;
      case OutboxKind.transactionUpdate:
        final id = op.payload['id'] as String;
        final data = Map<String, dynamic>.from(op.payload)..remove('id');
        await dio.patch('/wallets/${op.walletId}/transactions/$id', data: data);
        break;
      case OutboxKind.transactionDelete:
        final id = op.payload['id'] as String;
        await dio.delete('/wallets/${op.walletId}/transactions/$id');
        break;
      case OutboxKind.savingsDeposit:
        await dio.post('/wallets/${op.walletId}/savings/deposit',
            data: {'amount': op.payload['amount']});
        break;
      case OutboxKind.savingsWithdraw:
        await dio.post('/wallets/${op.walletId}/savings/withdraw',
            data: {'amount': op.payload['amount']});
        break;
      case OutboxKind.savingsWithdrawAll:
        await dio.post('/wallets/${op.walletId}/savings/withdraw-all');
        break;
      case OutboxKind.budgetUpsert:
        final data = op.payload;
        final id = data['id'] as String?;
        if (id == null || id.startsWith('local_')) {
          await dio.post('/wallets/${op.walletId}/budgets', data: {
            'category': data['category'],
            'limitAmount': data['limitAmount'],
          });
        } else {
          await dio.patch('/wallets/${op.walletId}/budgets/$id',
              data: {'limitAmount': data['limitAmount']});
        }
        break;
      case OutboxKind.budgetDelete:
        await dio.delete('/wallets/${op.walletId}/budgets/${op.payload['id']}');
        break;
      case OutboxKind.categoryCreate:
        final data = op.payload;
        try {
          await dio.post('/categories', data: {
            'id': data['id'],
            'type': data['type'],
            'name': data['name'],
          });
        } on DioException catch (e) {
          final body = e.response?.data;
          final error = (body is Map && body['error'] is Map) ? body['error'] as Map : null;
          final details = error?['details'];
          // Fusion idempotente : la catégorie existe déjà côté serveur → succès côté file.
          if (e.response?.statusCode == 409 &&
              error?['code'] == 'CATEGORY_EXISTS' &&
              details is Map &&
              details['category'] is Map) {
            final serverCategory = details['category'] as Map;
            final existingId = serverCategory['id'] as String?;
            final opId = data['id'] as String?;
            if (existingId != null && opId != null && existingId != opId) {
              // La transaction créée hors-ligne pointe l'id local : on réécrit
              // les opérations en attente sur l'id serveur pour éviter un 400.
              await _remapCategoryId(opId, existingId);
            }
            return;
          }
          rethrow;
        }
        break;
      default:
        break; // opération inconnue : ignorée
    }
  }

  /// Réécrit l'identifiant de catégorie dans toutes les opérations en attente
  /// (transactions créées/modifiées, budgets, cache local). Utilisé lorsqu'une
  /// catégorie créée hors-ligne fusionne avec une catégorie existante du serveur.
  Future<void> _remapCategoryId(String oldId, String newId) async {
    // 1. Opérations en attente (et payloads imbriqués).
    final ops = await _load();
    final remappedOps = ops.map((op) {
      final payload = Map<String, dynamic>.from(op.payload);
      if (payload['categoryId'] == oldId) payload['categoryId'] = newId;
      return OutboxOp(
        id: op.id,
        kind: op.kind,
        walletId: op.walletId,
        payload: payload,
        createdAt: op.createdAt,
      );
    }).toList();
    await _save(remappedOps);

    // 2. Overlay local des transactions créées hors-ligne.
    final pending = await pendingTransactions();
    final remappedPending = pending
        .map((t) => t.categoryId == oldId ? t.copyWith(categoryId: newId) : t)
        .toList();
    await _savePendingTransactions(remappedPending);

    // 3. Overlays des modifications.
    final updates = await updatedTransactions();
    for (final entry in updates.entries.toList()) {
      if (entry.value.categoryId == oldId) {
        updates[entry.key] = entry.value.copyWith(categoryId: newId);
      }
    }
    await _saveUpdatedTransactions(updates);
  }

  /// Crée une catégorie, en ligne si possible, sinon mise en file d'attente
  /// (l'opération sera rejouée au retour du réseau — id client stable).
  /// Retourne la catégorie effective (existante si fusion, nouvelle sinon).
  Future<Category> createCategoryOfflineAware({
    required String type,
    required String name,
    String? walletId,
  }) async {
    final clientId = const Uuid().v4();
    try {
      final res = await CategoryRepository.instance.create(
        type: type,
        name: name,
        clientId: clientId,
      );
      return res.category;
    } on DioException catch (e) {
      if (!_isNetworkish(e)) rethrow;
      final temp = Category(id: clientId, name: name, type: type, isDefault: false);
      final cached = await CategoryRepository.instance.loadCache();
      final exists = cached.any((c) => c.id == temp.id);
      if (!exists) {
        await CategoryRepository.instance.saveCache([...cached, temp]);
      }
      await enqueue(OutboxOp(
        id: clientId,
        kind: OutboxKind.categoryCreate,
        walletId: walletId ?? '',
        payload: {'id': clientId, 'type': type, 'name': name},
        createdAt: DateTime.now(),
      ));
      return temp;
    }
  }

  /// Vide toute la file et les caches locaux liés aux écritures en attente.
  /// Utilisé par la réinitialisation complète (le serveur fait foi ensuite).
  Future<void> clearAll() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('outbox_') || key.startsWith('reset_backup_')) {
        await prefs.remove(key);
      }
    }
  }

  /// Enregistre un versement/retrait d'épargne en attente (hors-ligne).
  /// [txId] : identifiant de la transaction optimiste correspondante
  /// (permet d'annuler proprement si le serveur refuse).
  Future<void> enqueueSavings(
    String walletId, {
    required String kind, // OutboxKind.savings*
    int? amount,
    String? txId,
  }) async {
    await enqueue(OutboxOp(
      id: '${kind}_${DateTime.now().millisecondsSinceEpoch}',
      kind: kind,
      walletId: walletId,
      payload: {'amount': ?amount, 'txId': ?txId},
      createdAt: DateTime.now(),
    ));
  }
}

