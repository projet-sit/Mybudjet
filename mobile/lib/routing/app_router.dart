import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/onboarding/wallet_setup_screen.dart';
import '../features/savings/savings_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/help/help_screen.dart';
import '../features/profile/privacy_policy_screen.dart';
import '../features/stats/stats_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import 'app_redirect.dart';

/// Notifie le routeur des changements d'auth/onboarding sans recréer GoRouter
/// (un seul routeur, une seule pile de navigation — jamais de redirection
/// perdue à la fin d'une inscription).
class _RouterTransitionNotifier extends ChangeNotifier {
  _RouterTransitionNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(onboardingSeenProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final transition = _RouterTransitionNotifier(ref);
  ref.onDispose(transition.dispose);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    refreshListenable: transition,
    redirect: (context, state) {
      // Lu à CHAQUE redirection : la valeur peut changer en cours de session
      // (l'utilisateur vient de terminer l'onboarding ou de créer son compte).
      final auth = ref.read(authControllerProvider);
      return appRedirect(
        onboardingSeen: ref.read(onboardingSeenProvider),
        authLoading: auth.isLoading,
        loggedIn: auth.value != null,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/wallet-setup', builder: (context, state) => const WalletSetupScreen()),
      GoRoute(path: '/home', builder: (context, state) => const MainShell()),
      GoRoute(path: '/savings', builder: (context, state) => const SavingsScreen()),
      GoRoute(path: '/stats', builder: (context, state) => const StatsScreen()),
      GoRoute(path: '/help', builder: (context, state) => const HelpScreen()),
      GoRoute(path: '/privacy-policy', builder: (context, state) => const PrivacyPolicyScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(child: Text(state.error?.message ?? 'Page introuvable')),
    ),
  );
});
