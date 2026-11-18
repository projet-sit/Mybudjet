import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/success_event.dart';

/// Point d'émission unique des événements de succès.
///
/// Seuls les cas d'usage autorisés (voir la documentation) appellent
/// [SuccessFeedbackController.emit]. Jamais un écran, un widget,
/// un listener de synchronisation ou une photo de profil.
class SuccessFeedbackController extends Notifier<SuccessEvent?> {
  static const _visibleDuration = Duration(milliseconds: 1200);

  Timer? _timer;

  @override
  SuccessEvent? build() => null;

  /// Émet un événement. Toute animation en cours est remplacée immédiatement.
  void emit(SuccessEvent event) {
    _timer?.cancel();
    state = event;
    _timer = Timer(_visibleDuration, () {
      if (state == event) {
        state = null;
      }
      _timer = null;
    });
  }

  /// Ferme/masque l'animation immédiatement.
  void clear() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

final successFeedbackProvider =
    NotifierProvider<SuccessFeedbackController, SuccessEvent?>(SuccessFeedbackController.new);
