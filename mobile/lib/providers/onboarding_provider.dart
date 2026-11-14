import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Indicateur « onboarding déjà vu » (SharedPreferences, clé `onboarding_seen`).
///
/// La valeur est lue AVANT `runApp` (cf. `main.dart`) et passée en override,
/// ce qui évite tout clignotement de l'écran d'onboarding au démarrage.
class OnboardingSeenNotifier extends Notifier<bool> {
  OnboardingSeenNotifier([this._initial = false]);

  final bool _initial;

  static const key = 'onboarding_seen';

  @override
  bool build() => _initial;

  /// Marque l'onboarding comme vu (après « Passer », « Commencer »,
  /// « J'ai déjà un compte »). Idempotent.
  Future<void> markSeen() async {
    if (state) return;
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}

/// true = l'utilisateur a déjà vu l'onboarding (jamais ré-affiché).
final onboardingSeenProvider =
    NotifierProvider<OnboardingSeenNotifier, bool>(OnboardingSeenNotifier.new);
