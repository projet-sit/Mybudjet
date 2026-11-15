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

  group('remise à zéro', () {
    test('mise en attente hors-ligne puis rejouée au retour du réseau', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_wallet', jsonEncode(_wallet(balance: 80000, savings: 30000).toJson()));

      await Outbox.instance.applyResetLocally('w1', includeSavings: false);
      await Outbox.instance.enqueueReset('w1', includeSavings: false);
      expect(await Outbox.instance.count(), 1);

      final posted = <Map<String, dynamic>>[];
      dio.httpClientAdapter = _FakeAdapter((options) async {
        if (options.path.endsWith('/reset')) {
          posted.add(Map<String, dynamic>.from(options.data as Map));
          return _json({
            'data': {
              'period': {
                'id': 'p2',
                'walletId': 'w1',
                'startDate': '2026-11-15',
                'endDate': '2026-11-30',
                'status': 'active',
              },
              'wallet': {
                'id': 'w1',
                'userId': 'u1',
                'name': 'Mon budget',
                'initialAmount': 30000,
                'startDate': '2026-11-15',
                'currency': 'XOF',
                'balance': 30000,
                'savingsAmount': 30000,
              },
              'previousPeriodId': 'p1',
              'mode': 'reset',
              'undoExpiresAt': '2026-11-15T00:00:10.000Z',
            },
          });
        }
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      final result = await Outbox.instance.flush();
      expect(result.replayed, 1);
      expect(result.hasFailures, isFalse);
      expect(posted, hasLength(1));
      expect(posted.first['includeSavings'], isFalse);
      expect(await Outbox.instance.count(), 0);
    });

    test('conserve l’épargne par défaut, la remet à zéro sur demande', () async {
      for (final includeSavings in [false, true]) {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cache_wallet', jsonEncode(_wallet(balance: 80000, savings: 30000).toJson()));
        await prefs.setString(
          'cache_dashboard_w1',
          jsonEncode({
            'walletId': 'w1',
            'walletName': 'Mon budget',
            'currency': 'XOF',
            'balance': 80000,
            'initialAmount': 80000,
            'totalExpenses': 20000,
            'totalIncomes': 50000,
            'transactionsCount': 12,
            'percentUsed': 25,
            'weeklySeries': <Map<String, dynamic>>[],
            'latestTransactions': <Map<String, dynamic>>[],
          }),
        );
        await prefs.setString('cache_txs_w1', jsonEncode([_expense().toJson()]));

        await Outbox.instance.applyResetLocally('w1', includeSavings: includeSavings);

        final wallet = jsonDecode(prefs.getString('cache_wallet')!) as Map<String, dynamic>;
        final dashboard = jsonDecode(prefs.getString('cache_dashboard_w1')!) as Map<String, dynamic>;
        if (includeSavings) {
          expect(wallet['balance'], 0);
          expect(wallet['savingsAmount'], 0);
        } else {
          expect(wallet['balance'], 30000, reason: 'Reste = 0, épargne conservée');
          expect(wallet['savingsAmount'], 30000);
        }
        expect(dashboard['totalExpenses'], 0);
        expect(dashboard['totalIncomes'], 0);
        expect(dashboard['transactionsCount'], 0);
        expect(prefs.getString('cache_txs_w1'), isNull, reason: 'opérations archivées côté local');
        expect(await Outbox.instance.count(), 0);
      }
    });
  });
}
