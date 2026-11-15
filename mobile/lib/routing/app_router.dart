import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/onboarding/wallet_setup_screen.dart';
import '../features/periods/periods_history_screen.dart';
import '../features/savings/savings_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/stats/stats_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import 'app_redirect.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      // Lu à CHAQUE redirection : la valeur peut changer en cours de session
      // (l'utilisateur vient de terminer l'onboarding).
      final onboardingSeen = ref.read(onboardingSeenProvider);
      return appRedirect(
        onboardingSeen: onboardingSeen,
        authLoading: authState.isLoading,
        loggedIn: authState.value != null,
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
      GoRoute(path: '/periods', builder: (context, state) => const PeriodsHistoryScreen()),
      GoRoute(path: '/stats', builder: (context, state) => const StatsScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(child: Text(state.error?.message ?? 'Page introuvable')),
    ),
  );
});
