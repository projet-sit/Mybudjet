import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_prefs_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/currency_provider.dart';
import 'providers/epoch_reset_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/wallet_provider.dart';
import 'features/success_feedback/widgets/success_feedback_overlay.dart';
import 'routing/app_router.dart';
import 'services/api_client.dart';
import 'services/budget_alerts_service.dart';
import 'services/currency_service.dart';
import 'services/error_reporter.dart';
import 'services/outbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReporter.installGlobalHooks();
  await runZonedGuarded(() async {
    await _bootstrap();
  }, (error, stack) => ErrorReporter.reportError(error: error, stack: stack, screen: 'zone'));
}

Future<void> _bootstrap() async {
  // Démarrage : toutes les initialisations indépendantes tournent EN PARALLÈLE —
  // le temps d'affichage de la première frame = le max, pas la somme.
  final results = await Future.wait([
    dotenv.load(fileName: '.env'),
    initializeDateFormatting('fr_FR'),
    // Devise + cache du taux USD chargés AVANT runApp (pas de clignotement).
    CurrencyService.instance.init(),
    // Lu AVANT runApp : pas de clignotement de l'onboarding.
    SharedPreferences.getInstance(),
  ]);
  final prefs = results[3] as SharedPreferences;
  final onboardingSeen = prefs.getBool(OnboardingSeenNotifier.key) ?? false;
  // Réveil discret du backend (plan gratuit : il dort après inactivité).
  ApiClient.instance.wake();
  // Taux USD du jour en arrière-plan (affichage/conversion uniquement).
  unawaited(CurrencyService.instance.refreshUsdRate());
  // Plugin de notifications locales (alertes de budget) — non bloquant pour la 1re frame.
  unawaited(BudgetAlertsService.instance.initialize());
  runApp(
    ProviderScope(
      overrides: [
        // L'onboarding est lu ici : jamais d'affichage au-delà de la 1re ouverture.
        onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(onboardingSeen)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  AppLifecycleListener? _lifecycle;
  bool _resumeRunning = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  /// Retour au premier plan : tout est revérifié proprement —
  /// jamais besoin de se déconnecter/reconnecter.
  Future<void> _onResume() async {
    if (_resumeRunning) return;
    _resumeRunning = true;
    try {
      // 1. Connectivité recalculée (quitte seul l'état à jour).
      await ref.read(syncInfoProvider.notifier).refresh();
      // 2. Réveil discret du backend + revalidation de la session (jeton).
      ApiClient.instance.wake();
      await ref.read(authControllerProvider.notifier).revalidate();
      // 3. Rejoue les écritures en attente, puis rafraîchit tout — EN PARALLÈLE.
      final flushResult = await Outbox.instance.flush();
      if (flushResult.hasFailures) {
        ref.read(syncNoticeProvider.notifier).setFailed(
              flushResult.failures.length,
              flushResult.failures.first.message,
            );
      } else if (flushResult.replayed > 0) {
        ref.read(syncNoticeProvider.notifier).clear();
      }
      // Solde (portefeuille) et badge de synchro viennent du réseau indépendamment :
      // on les rafraîchit en parallèle — dashboard/transactions invalident derrière.
      await Future.wait([
        ref.read(walletControllerProvider.notifier).refresh(),
        ref.read(syncInfoProvider.notifier).refresh(),
      ]);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(transactionsProvider);
    } finally {
      _resumeRunning = false;
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeControllerProvider).value ?? ThemeMode.light;
    // Toute l'UI se reconstruit au changement de devise (mêmes montants, nouvelle mise en forme).
    ref.watch(currencyControllerProvider);

    // Un autre appareil (ou cette remise à zéro) a effacé les données côté serveur :
    // on renvoie l'utilisateur vers la création du premier portefeuille.
    ref.listen<int>(epochResetProvider, (previous, next) {
      if (next != previous && next > 0) {
        router.go('/wallet-setup');
      }
    });

    return MaterialApp.router(
      title: 'MyBudget',      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const SuccessFeedbackOverlay(),
          ],
        );
      },
    );
  }
}
