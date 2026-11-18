import 'dart:async';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conversion monétaire multi-devise avec stockage de référence en XOF.
///
/// Principe (important) :
/// - chaque montant est stocké en base (backend + caches) en XOF, entier,
///   sans jamais être réécrit lors d'un changement de devise ;
/// - la conversion n'existe qu'à l'affichage et à la saisie :
///   affiché = montantXOF × taux, saisi → montantXOF = saisi / taux ;
/// - taux EUR : parité fixe officielle, 1 EUR = 655,957 XOF (en dur) ;
/// - taux USD : variable, récupéré via open.er-api.com/v6/latest/XOF
///   (gratuit, sans clé), mis en cache avec la date de mise à jour ;
///   hors ligne ou en échec → dernier taux connu, sinon taux de secours en dur.
class CurrencyService {
  CurrencyService._internal();

  static final CurrencyService instance = CurrencyService._internal();

  /// 1 EUR = 655,957 XOF (parité fixe officielle, jamais d'API).
  static const double eurPerXof = 1 / 655.957;

  /// Taux de secours USD (≈ 1 USD = 570 XOF) — utilisé tant qu'aucun taux
  /// réel n'a été récupéré.
  static const double usdFallbackPerXof = 0.00175;

  static const _codeKey = 'currency_code';
  static const _usdRateKey = 'usd_rate_per_xof';
  static const _usdUpdatedAtKey = 'usd_rate_updated_at';

  String _current = 'XOF';
  double _usdPerXof = usdFallbackPerXof;
  DateTime? _usdUpdatedAt;
  bool _usdRateFromCache = false;
  bool _initialized = false;

  /// Charge la devise active et le cache du taux USD (à appeler au démarrage).
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    _current = (code == 'EUR' || code == 'USD' || code == 'XOF') ? code! : 'XOF';
    final cachedRate = prefs.getDouble(_usdRateKey);
    if (cachedRate != null && cachedRate > 0) {
      _usdPerXof = cachedRate;
      _usdRateFromCache = true;
    }
    final rawDate = prefs.getString(_usdUpdatedAtKey);
    _usdUpdatedAt = rawDate != null ? DateTime.tryParse(rawDate) : null;
    _initialized = true;
  }

  /// Devise active (« XOF » | « EUR » | « USD »).
  String get current => _current;

  /// Date de dernière mise à jour du taux USD (null si jamais récupéré).
  DateTime? get usdUpdatedAt => _usdUpdatedAt;

  /// Vrai si le taux USD provient du cache local (ou du taux de secours
  /// si rien n'a jamais été récupéré).
  bool get usdRateIsFallback => !_usdRateFromCache;

  /// Unités de [code] pour 1 XOF.
  static double perXofFor(String code) {
    switch (code) {
      case 'EUR':
        return eurPerXof;
      case 'USD':
        return instance._usdPerXof;
      case 'XOF':
      default:
        return 1.0;
    }
  }

  /// XOF → valeur dans la devise [code] (non arrondie).
  static double convertFromXof(int xof, [String code = 'XOF']) => xof * perXofFor(code);

  /// Saisie (valeur dans [code]) → entier XOF à stocker (arrondi).
  static int convertToXof(num entered, [String code = 'XOF']) {
    final per = perXofFor(code);
    if (code == 'XOF') return entered.round();
    return (entered / per).round();
  }

  /// Taux de conversion d'une devise (base XOF) vers une autre.
  /// Utile pour les affichages "1 EUR = 655,957 XOF".
  static double xofPerUnit(String code) {
    switch (code) {
      case 'EUR':
        return 655.957;
      case 'USD':
        final per = instance._usdPerXof;
        return per > 0 ? 1 / per : 1 / usdFallbackPerXof;
      case 'XOF':
      default:
        return 1.0;
    }
  }

  /// Persiste la devise active (la mémoire est mise à jour immédiatement).
  Future<void> setCurrent(String code) async {
    if (code != 'XOF' && code != 'EUR' && code != 'USD') return;
    _current = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
  }

  /// Récupère le taux USD réel depuis l'API publique ; retombe sur le cache
  /// ou le taux de secours en cas d'échec. Ne lève jamais d'exception.
  /// Renvoie true si un taux réel vient d'être enregistré.
  Future<bool> refreshUsdRate() async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final response = await dio.get<Map<String, dynamic>>(
        'https://open.er-api.com/v6/latest/XOF',
      );
      final rates = response.data?['rates'];
      final usd = (rates is Map ? rates['USD'] as num? : null)?.toDouble();
      if (usd == null || usd <= 0) return false;
      _usdPerXof = usd;
      _usdUpdatedAt = DateTime.now();
      _usdRateFromCache = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_usdRateKey, usd);
      await prefs.setString(_usdUpdatedAtKey, _usdUpdatedAt!.toIso8601String());
      return true;
    } catch (_) {
      // Hors ligne, API indisponible, réponse invalide : on garde le cache / secours.
      return false;
    }
  }
}
