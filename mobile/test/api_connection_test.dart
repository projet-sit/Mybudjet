// Test d'intégration Phases 2-4 : liaison Flutter ↔ Node.js + auth + portefeuille.
// Prérequis : backend démarré sur http://localhost:3000 (npm run dev / node src/server.js)
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests d'intégration désactivés par défaut (backend requis).
/// Lancer avec : flutter test --dart-define=RUN_API_TESTS=true
const bool _runApiTests = bool.fromEnvironment('RUN_API_TESTS');

void main() {
  late Dio dio;

  setUpAll(() {
    dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:3000/api/v1',
      connectTimeout: const Duration(seconds: 5),
    ));
  });

  test('GET /health répond avec success=true et le service MYBUDGET API', () async {
    final response = await dio.get('/health');
    expect(response.statusCode, 200);
    expect(response.data['success'], true);
    expect(response.data['data']['service'], 'MYBUDGET API');
    expect(response.data['data']['status'], 'ok');
  }, skip: !_runApiTests);

  test('Inscription → portefeuille (solde = montant saisi, zéro donnée fictive) → isolation',
      () async {
    final phone = '+2299${DateTime.now().millisecondsSinceEpoch % 100000000}';

    final register = await dio.post('/auth/register', data: {
      'displayName': 'Utilisateur Flutter',
      'phone': phone,
      'password': 'secret123',
    });
    final token = register.data['data']['tokens']['accessToken'] as String;
    final headers = Options(headers: {'Authorization': 'Bearer $token'});

    // Aucun portefeuille au départ
    final empty = await dio.get('/wallets', options: headers);
    expect(empty.data['data']['hasWallet'], false);

    // Création avec montant initial saisi par l'utilisateur
    final create = await dio.post(
      '/wallets',
      options: headers,
      data: {'name': 'Mon budget', 'initialAmount': 150000, 'startDate': '2026-11-01'},
    );
    expect(create.statusCode, 201);
    expect(create.data['data']['wallet']['balance'], 150000);

    // Portefeuille sans montant → solde 0 (aucune donnée fictive)
    final createZero = await dio.post(
      '/wallets',
      options: headers,
      data: {'name': 'Épargne'},
    );
    expect(createZero.data['data']['wallet']['balance'], 0);

    // Route protégée sans token → 401
    try {
      await dio.get('/wallets');
      fail('route accessible sans token');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 401);
    }
  }, skip: !_runApiTests);
}
