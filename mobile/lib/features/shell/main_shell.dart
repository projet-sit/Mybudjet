import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_feedback.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shell_provider.dart';
import '../budgets/budgets_screen.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../transactions/quick_add_sheet.dart';

/// Coquille principale (maquette « MyBudget ») :
/// Accueil · Opérations · [+ FAB] · Budgets · Profil.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    // Une confirmation de bienvenue (connexion / création de compte) est
    // affichée une seule fois, à l'arrivée sur l'accueil.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAuthSuccessIfPending());
  }

  Future<void> _showAuthSuccessIfPending() async {
    final notice = ref.read(authNoticeProvider);
    if (notice == null || !mounted) return;
    ref.read(authNoticeProvider.notifier).set(null);
    final (title, message) = switch (notice) {
      AuthNotice.login => ('Connexion réussie !', 'Bon retour ! Vous êtes connecté à votre compte.'),
      AuthNotice.register => ('Compte créé !', 'Votre compte a été créé avec succès. Bienvenue sur MyBudget !'),
    };
    await showSuccessDialog(context, title: title, message: message);
  }

  void _openQuickAdd(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const QuickAddSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    final scheme = Theme.of(context).colorScheme;
    final screens = const [HomeScreen(), HistoryScreen(), BudgetsScreen(), ProfileScreen()];

    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: index, children: screens)),
      floatingActionButton: _AddButton(onTap: () => _openQuickAdd(context)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 92,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Accueil',
                  selected: index == 0,
                  onTap: () => ref.read(shellTabProvider.notifier).set(0),
                ),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: 'Opérations',
                  selected: index == 1,
                  onTap: () => ref.read(shellTabProvider.notifier).set(1),
                ),
                const SizedBox(width: 68),
                _NavItem(
                  icon: Icons.verified_outlined,
                  activeIcon: Icons.verified,
                  label: 'Budgets',
                  selected: index == 2,
                  onTap: () => ref.read(shellTabProvider.notifier).set(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profil',
                  selected: index == 3,
                  onTap: () => ref.read(shellTabProvider.notifier).set(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.deepGreenLight, AppColors.deepGreen],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.deepGreen.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 34),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(selected ? activeIcon : icon, size: 34, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
