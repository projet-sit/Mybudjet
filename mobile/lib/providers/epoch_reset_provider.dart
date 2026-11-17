import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signal émis quand le serveur annonce un `data_epoch` différent du cache local :
/// un autre appareil (ou la réinitialisation actuelle) a tout effacé côté serveur.
/// La navigation vers « création du premier portefeuille » est gérée par MyApp.
class EpochResetNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int epoch) => state = epoch;
}

final epochResetProvider = NotifierProvider<EpochResetNotifier, int>(EpochResetNotifier.new);
