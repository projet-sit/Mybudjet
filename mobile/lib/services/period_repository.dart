import 'package:dio/dio.dart';

import '../models/period.dart';
import '../models/wallet.dart';
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

  /// Liste toutes les périodes (active + archivées) avec leurs totaux.
  Future<List<PeriodSummary>> list(String walletId) async {
    final response = await _dio.get('/wallets/$walletId/periods');
    final periods = (response.data['data']['periods'] as List)
        .map((e) => PeriodSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return periods;
  }

  /// Restaure une période archivée (uniquement si la période courante est vide).
  Future<({BudgetPeriod period, Wallet wallet, bool restored})> restore(
    String walletId,
    String periodId,
  ) async {
    final response = await _dio.post('/wallets/$walletId/periods/$periodId/restore');
    final data = response.data['data'] as Map<String, dynamic>;
    return (
      period: BudgetPeriod.fromJson(Map<String, dynamic>.from(data['period'] as Map)),
      wallet: Wallet.fromJson(Map<String, dynamic>.from(data['wallet'] as Map)),
      restored: data['restored'] == true,
    );
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
