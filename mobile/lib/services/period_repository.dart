import 'package:dio/dio.dart';

import '../models/period.dart';
import 'api_client.dart';

class PeriodRepository {
  PeriodRepository._internal();

  static final PeriodRepository instance = PeriodRepository._internal();

  final Dio _dio = ApiClient.instance.dio;

  Future<PeriodInfo> get(String walletId) async {
    final response = await _dio.get('/wallets/$walletId/period');
    return PeriodInfo.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<PeriodTransition> undo(String walletId, String periodId) async {
    final response = await _dio.post('/wallets/$walletId/period/$periodId/undo');
    return PeriodTransition.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  /// Remise à zéro : archive la période en cours (historique conservé) et en
  /// ouvre une nouvelle. L'épargne est conservée sauf `includeSavings`.
  Future<PeriodTransition> reset(String walletId, {required bool includeSavings}) async {
    final response = await _dio.post('/wallets/$walletId/reset', data: {
      'includeSavings': includeSavings,
    });
    return PeriodTransition.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}
