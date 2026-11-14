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

  Future<PeriodTransition> next(String walletId, {required String mode}) async {
    final response = await _dio.post(
      '/wallets/$walletId/period/next',
      data: {'mode': mode},
    );
    return PeriodTransition.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<PeriodTransition> undo(String walletId, String periodId) async {
    final response = await _dio.post('/wallets/$walletId/period/$periodId/undo');
    return PeriodTransition.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}
