import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_prefs_provider.dart';
import 'providers/onboarding_provider.dart';
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  // Lu AVANT runApp : pas de clignotement de l'onboarding au démarrage.
  final prefs = await SharedPreferences.getInstance();
  final onboardingSeen = prefs.getBool(OnboardingSeenNotifier.key) ?? false;
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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeControllerProvider).value ?? ThemeMode.light;

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
    );
  }
}
