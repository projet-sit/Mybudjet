import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onglet actif de la coquille principale :
/// 0 Accueil · 1 Opérations · 2 Budgets · 3 Profil.
class ShellTabController extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final shellTabProvider = NotifierProvider<ShellTabController, int>(ShellTabController.new);
