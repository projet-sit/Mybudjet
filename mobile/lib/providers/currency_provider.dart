import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/currency_service.dart';

/// État monétaire vu par les écrans : devise active + infos du taux USD.
class CurrencyState {
  const CurrencyState({
    required this.code,
    required this.usdUpdatedAt,
    required this.usdIsFallback,
  });

  final String code; // 'XOF' | 'EUR' | 'USD'
  final DateTime? usdUpdatedAt;
  final bool usdIsFallback;
}

/// Devise active de l'application.
///
/// Le montant est stocké en base en XOF : changer de devise n'écrit RIEN côté
/// serveur — seule la mise en forme change (les montants sont reconvertis à
/// l'affichage). Les widgets regardent ce provider pour se reconstruire.
class CurrencyController extends Notifier<CurrencyState> {
  CurrencyState _snapshot() => CurrencyState(
        code: CurrencyService.instance.current,
        usdUpdatedAt: CurrencyService.instance.usdUpdatedAt,
        usdIsFallback: CurrencyService.instance.usdRateIsFallback,
      );

  @override
  CurrencyState build() => _snapshot();

  /// Change la devise active (le dialogue de confirmation est géré par l'appelant).
  Future<void> setCurrency(String code) async {
    await CurrencyService.instance.setCurrent(code);
    state = _snapshot();
  }

  /// Rafraîchit le taux USD (best effort) — met à jour la date affichée.
  Future<bool> refreshUsdRate() async {
    final ok = await CurrencyService.instance.refreshUsdRate();
    state = _snapshot();
    return ok;
  }
}

final currencyControllerProvider =
    NotifierProvider<CurrencyController, CurrencyState>(CurrencyController.new);
