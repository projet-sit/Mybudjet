import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybudget/models/transaction.dart';
import 'package:mybudget/models/wallet.dart';
import 'package:mybudget/services/api_client.dart';
import 'package:mybudget/services/category_repository.dart';
import 'package:mybudget/services/outbox.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      'content-type': ['application/json'],
    });

Transaction _expense({String id = '', int amount = 5000}) => Transaction(
      id: id,
      walletId: 'w1',
      type: 'expense',
      amount: amount,
      category: 'Alimentation',
      description: 'Restaurant',
      date: '2026-11-14',
      time: '12:32',
    );

Wallet _wallet({int balance = 100000, int savings = 25000}) => Wallet(
      id: 'w1',
      userId: 'u1',
      name: 'Mon budget',
      initialAmount: 100000,
      startDate: '2026-11-01',
      currency: 'XOF',
      balance: balance,
      savingsAmount: savings,
    );

void main() {
  late Dio dio;
  late HttpClientAdapter originalAdapter;

  setUpAll(() async {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost/api/v1');
    await initializeDateFormatting('fr_FR');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dio = ApiClient.instance.dio;
    originalAdapter = dio.httpClientAdapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
  });

  group('création hors-ligne (backend injoignable)', () {
    test('l’opération est mise en attente et le cache local est ajusté', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_wallet', jsonEncode(_wallet().toJson()));
      dio.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('backend down'),
        );
      });

      final result = await Outbox.instance.createTransaction('w1', _expense());

      expect(result.queued, isTrue);
      expect(await Outbox.instance.count(), 1);

      // Le solde en cache a été décrémenté immédiatement.
      final cached = jsonDecode(prefs.getString('cache_wallet')!) as Map<String, dynamic>;
      expect(cached['balance'], 95000);

      // L'opération apparaît dans les opérations en attente.
      final pending = await Outbox.instance.pendingTransactions();
      expect(pending, hasLength(1));
      expect(pending.first.amount, 5000);
      expect(pending.first.id.startsWith('local_'), isTrue);
    });

    test('flush() rejoue l’opération quand le backend revient', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_wallet', jsonEncode(_wallet().toJson()));

      var backendUp = false;
      final received = <Map<String, dynamic>>[];
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (!backendUp) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('backend down'),
          );
        }
        received.add(Map<String, dynamic>.from(options.data as Map));
        return _json({
          'data': {
            'transaction': {
              'id': 'server-uuid-1',
              'walletId': 'w1',
              'type': 'expense',
              'amount': 5000,
              'category': 'Alimentation',
              'description': 'Restaurant',
              'date': '2026-11-14',
              'time': '12:32',
            },
            'newBalance': 95000,
          },
        }, 201);
      });

      await Outbox.instance.createTransaction('w1', _expense());
      expect(await Outbox.instance.count(), 1);

      backendUp = true;
      final result = await Outbox.instance.flush();

      expect(result.replayed, 1);
      expect(result.hasFailures, isFalse);
      expect(await Outbox.instance.count(), 0);
      expect(received, hasLength(1));
      expect(received.first['amount'], 5000);
    });

    test('échec définitif au rejeu : rollback local + échec remonté', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_wallet', jsonEncode(_wallet().toJson()));

      // Passe 1 : backend down → l'opération est mise en attente.
      var backendMode = 'down';
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (backendMode == 'down') {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('backend down'),
          );
        }
        return _json({
          'error': {'message': 'Solde disponible insuffisant pour cette dépense'},
        }, 409);
      });

      await Outbox.instance.createTransaction('w1', _expense());
      var cached = jsonDecode(prefs.getString('cache_wallet')!) as Map<String, dynamic>;
      expect(cached['balance'], 95000, reason: 'effet optimiste appliqué');

      // Passe 2 : backend up mais refuse (409) → rollback.
      backendMode = 'up409';
      final result = await Outbox.instance.flush();

      expect(result.replayed, 0);
      expect(result.failures, hasLength(1));
      expect(result.failures.first.message, contains('Solde disponible insuffisant'));
      expect(await Outbox.instance.count(), 0);

      cached = jsonDecode(prefs.getString('cache_wallet')!) as Map<String, dynamic>;
      expect(cached['balance'], 100000, reason: 'rollback : le solde est restauré');
      expect(await Outbox.instance.pendingTransactions(), isEmpty);
    });

    test('une erreur métier (4xx) abandonne l’opération au lieu de boucler', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_wallet', jsonEncode(_wallet().toJson()));
      dio.httpClientAdapter = _FakeAdapter((options) async {
        return _json({
          'error': {'message': 'Solde disponible insuffisant pour cette dépense'},
        }, 409);
      });

      // 4xx = pas une erreur réseau : l'écran affiche l'erreur, rien en attente.
      await expectLater(
        Outbox.instance.createTransaction('w1', _expense()),
        throwsA(isA<DioException>()),
      );
      expect(await Outbox.instance.count(), 0);
    });
  });

  group('épargne', () {
    test('un versement diminue le Reste et augmente l’épargne (atomique côté cache)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_wallet', jsonEncode(_wallet(balance: 100000, savings: 20000).toJson()));
      dio.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('backend down'),
        );
      });

      final tx = Transaction(
        id: 'local_1',
        walletId: 'w1',
        type: 'savings_deposit',
        amount: 10000,
        category: 'Épargne',
        description: null,
        date: '2026-11-14',
        time: '12:32',
      );
      await Outbox.instance.applyPendingTransactionLocally('w1', tx);

      final cached = jsonDecode(prefs.getString('cache_wallet')!) as Map<String, dynamic>;
      expect(cached['balance'], 100000); // le solde ne bouge pas
      expect(cached['savingsAmount'], 30000); // l'épargne augmente
      expect(cached['balance'] - cached['savingsAmount'], 70000); // Reste diminue
    });

    test('balanceDeltaOf / savingsDeltaOf reflètent les types', () {
      expect(Outbox.balanceDeltaOf(_expense()), -5000);
      expect(Outbox.savingsDeltaOf(_expense()), 0);

      final deposit = _expense().copyWith(id: 's');
      final savingsTx = Transaction(
        id: 's1',
        walletId: 'w1',
        type: 'savings_deposit',
        amount: 3000,
        category: 'Épargne',
        date: '2026-11-14',
        time: '12:00',
      );
      expect(Outbox.balanceDeltaOf(savingsTx), 0);
      expect(Outbox.savingsDeltaOf(savingsTx), 3000);

      final withdrawal = Transaction(
        id: 's2',
        walletId: 'w1',
        type: 'savings_withdrawal',
        amount: 2000,
        category: 'Épargne',
        date: '2026-11-14',
        time: '12:00',
      );
      expect(Outbox.savingsDeltaOf(withdrawal), -2000);
      expect(deposit.id, 's');
    });
  });

  group('catégories personnalisées (hors-ligne puis synchronisation)', () {
    test('création hors-ligne : mise en cache + en file d’attente', () async {
      SharedPreferences.setMockInitialValues({});
      dio.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('offline'),
        );
      });

      final created = await Outbox.instance.createCategoryOfflineAware(
        type: 'expense',
        name: 'Coiffure',
        walletId: 'w1',
      );
      expect(created.name, 'Coiffure');
      expect(await Outbox.instance.count(), 1);

      final cached = await CategoryRepository.instance.loadCache();
      expect(cached.map((c) => c.name), contains('Coiffure'));
    });

    test('le flush rejoue la création avec le même id client', () async {
      SharedPreferences.setMockInitialValues({});
      var backendUp = false;
      final posted = <Map<String, dynamic>>[];
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (!backendUp) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('offline'),
          );
        }
        posted.add(Map<String, dynamic>.from(options.data as Map));
        return _json({
          'data': {
            'category': {'id': posted.last['id'], 'name': 'Coiffure', 'type': 'expense', 'isDefault': false, 'iconKey': 'label'},
            'fused': false,
          },
        }, 201);
      });

      await Outbox.instance.createCategoryOfflineAware(type: 'expense', name: 'Coiffure', walletId: 'w1');
      backendUp = true;
      final result = await Outbox.instance.flush();
      expect(result.replayed, 1);
      expect(result.hasFailures, isFalse);
      expect(posted, hasLength(1));
      expect(posted.first['id'], isNotNull);
      expect(posted.first['name'], 'Coiffure');
      expect(await Outbox.instance.count(), 0);
    });

    test('fusion : 409 CATEGORY_EXISTS avec la catégorie existante = succès (pas de doublon)', () async {
      SharedPreferences.setMockInitialValues({});
      var backendUp = false;
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (!backendUp) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('offline'),
          );
        }
        return _json({
          'success': false,
          'error': {
            'code': 'CATEGORY_EXISTS',
            'message': 'Cette catégorie existe déjà, elle est sélectionnée',
            'details': {
              'category': {'id': 'cat-server-1', 'name': 'Coiffure', 'type': 'expense', 'isDefault': false, 'iconKey': 'label'},
            },
          },
        }, 409);
      });

      await Outbox.instance.createCategoryOfflineAware(type: 'expense', name: 'Coiffure', walletId: 'w1');
      backendUp = true;
      final result = await Outbox.instance.flush();
      expect(result.replayed, 1);
      expect(result.hasFailures, isFalse);
      expect(await Outbox.instance.count(), 0);
    });

    test('fusion + transaction hors-ligne : l’id serveur est propagé aux opérations en attente', () async {
      SharedPreferences.setMockInitialValues({});
      var backendUp = false;
      final postedTx = <Map<String, dynamic>>[];
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (!backendUp) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('offline'),
          );
        }
        if (options.path.endsWith('/categories')) {
          // Fusion : le serveur renvoie SA catégorie existante (id différent).
          return _json({
            'success': false,
            'error': {
              'code': 'CATEGORY_EXISTS',
              'message': 'Cette catégorie existe déjà, elle est sélectionnée',
              'details': {
                'category': {'id': 'cat-server-1', 'name': 'Coiffure', 'type': 'expense', 'isDefault': false, 'iconKey': 'label'},
              },
            },
          }, 409);
        }
        if (options.path.endsWith('/transactions')) {
          postedTx.add(Map<String, dynamic>.from(options.data as Map));
          return _json({'data': {'transaction': {'id': 'tx-1'}, 'newBalance': 95000}}, 201);
        }
        return _json({}, 404);
      });

      // 1. Création de catégorie hors-ligne (id client A).
      final created = await Outbox.instance.createCategoryOfflineAware(
        type: 'expense',
        name: 'Coiffure',
        walletId: 'w1',
      );
      final clientId = created.id;

      // 2. Création d'une transaction hors-ligne sur cette catégorie.
      final txCreate = await Outbox.instance.createTransaction(
        'w1',
        Transaction(
          id: '',
          walletId: 'w1',
          type: 'expense',
          amount: 3000,
          category: 'Coiffure',
          categoryId: clientId,
          date: '2026-11-17',
          time: '08:00',
        ),
      );
      expect(txCreate.queued, isTrue);
      expect(await Outbox.instance.count(), 2);

      // 3. Synchronisation : la catégorie fusionne, le tx relaie le nouvel id.
      backendUp = true;
      final result = await Outbox.instance.flush();
      expect(result.replayed, 2);
      expect(result.hasFailures, isFalse);
      expect(postedTx, hasLength(1));
      expect(postedTx.single['categoryId'], 'cat-server-1');
    });

    test('doublon serveur sans détails : la catégorie optimiste est annulée (rollback)', () async {
      SharedPreferences.setMockInitialValues({});
      var backendUp = false;
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (!backendUp) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('offline'),
          );
        }
        return _json({
          'success': false,
          'error': {'code': 'CATEGORY_EXISTS', 'message': 'Conflit'},
        }, 409);
      });

      await Outbox.instance.createCategoryOfflineAware(type: 'expense', name: 'Coiffure', walletId: 'w1');
      backendUp = true;
      final result = await Outbox.instance.flush();
      expect(result.hasFailures, isTrue);
      final cached = await CategoryRepository.instance.loadCache();
      expect(cached.map((c) => c.name), isNot(contains('Coiffure')));
    });

    test('clearAll vide toute la file (réinitialisation complète)', () async {
      SharedPreferences.setMockInitialValues({});
      dio.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('offline'),
        );
      });

      await Outbox.instance.createTransaction('w1', _expense());
      await Outbox.instance.createCategoryOfflineAware(type: 'expense', name: 'Coiffure');
      expect(await Outbox.instance.count(), 2);

      await Outbox.instance.clearAll();
      expect(await Outbox.instance.count(), 0);
      expect(await Outbox.instance.pendingTransactions(), isEmpty);
    });
  });
}
