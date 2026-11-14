import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mybudget/models/user.dart';
import 'package:mybudget/models/wallet.dart';
import 'package:mybudget/models/dashboard.dart';
import 'package:mybudget/features/onboarding/onboarding_screen.dart';
import 'package:mybudget/providers/auth_provider.dart';
import 'package:mybudget/providers/onboarding_provider.dart';
import 'package:mybudget/providers/transaction_provider.dart';
import 'package:mybudget/providers/wallet_provider.dart';
import 'package:mybudget/routing/app_redirect.dart';
import 'package:mybudget/routing/app_router.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:3000/api/v1');
  });

  group('appRedirect', () {
    test('première ouverture : tout mène à l’onboarding', () {
      expect(
        appRedirect(onboardingSeen: false, authLoading: false, loggedIn: false, location: '/home'),
        '/onboarding',
      );
      expect(
        appRedirect(onboardingSeen: false, authLoading: true, loggedIn: false, location: '/login'),
        '/onboarding',
      );
    });

    test('première ouverture : on reste sur l’onboarding', () {
      expect(
        appRedirect(onboardingSeen: false, authLoading: false, loggedIn: false, location: '/onboarding'),
        isNull,
      );
    });

    test('deuxième lancement : jamais l’onboarding (déconnexion → connexion)', () {
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: false, location: '/onboarding'),
        '/login',
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: true, location: '/onboarding'),
        '/home',
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: false, location: '/home'),
        '/login',
      );
    });

    test('session déjà connectée : directement l’accueil', () {
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: true, location: '/'),
        isNull,
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: true, location: '/home'),
        isNull,
      );
    });

    test('écran d’authentification : bloqué une fois connecté', () {
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: true, location: '/login'),
        '/home',
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: true, location: '/register'),
        '/home',
      );
    });

    test('restauration de session : /splash, puis décision', () {
      expect(
        appRedirect(onboardingSeen: true, authLoading: true, loggedIn: false, location: '/'),
        '/splash',
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: true, loggedIn: false, location: '/splash'),
        isNull,
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: true, location: '/splash'),
        '/home',
      );
      expect(
        appRedirect(onboardingSeen: true, authLoading: false, loggedIn: false, location: '/splash'),
        '/login',
      );
    });

    test('restauration en cours : les écrans d’auth restent accessibles', () {
      expect(
        appRedirect(onboardingSeen: true, authLoading: true, loggedIn: false, location: '/register'),
        isNull,
      );
    });
  });

  group('onboardingSeenProvider', () {
    test('markSeen persiste l’indicateur', () async {
      final container = ProviderContainer(
        overrides: [
          onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(false)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(onboardingSeenProvider), isFalse);
      await container.read(onboardingSeenProvider.notifier).markSeen();
      expect(container.read(onboardingSeenProvider), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingSeenNotifier.key), isTrue);
    });
  });

  /// Monte l'onboarding dans un routeur minimal (routes d'atterrissage factices).
  Future<ProviderContainer> pumpOnboarding(
    WidgetTester tester, {
    bool seen = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(seen)),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
        GoRoute(
          path: '/register',
          builder: (_, _) => const Scaffold(body: Center(child: Text('register-screen'))),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Center(child: Text('login-screen'))),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('OnboardingScreen', () {
    testWidgets('Passer → Inscription, marque l’onboarding vu', (tester) async {
      final container = await pumpOnboarding(tester);

      expect(find.text('MyBudget'), findsOneWidget);
      expect(find.text('Passer'), findsOneWidget);
      expect(find.text('Suivant'), findsOneWidget);
      expect(find.text('Commencer'), findsNothing);

      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();

      expect(find.text('register-screen'), findsOneWidget);
      expect(container.read(onboardingSeenProvider), isTrue);
    });

    testWidgets('Suivant → page 2, Suivant → page 3 ; « Passer » absent sur la page 3', (tester) async {
      await pumpOnboarding(tester);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Gardez le contrôle de votre budget'), findsOneWidget);
      expect(find.text('Passer'), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Disponible même sans internet'), findsOneWidget);
      expect(find.text('Commencer'), findsOneWidget);
      expect(find.text("J'ai déjà un compte"), findsOneWidget);
      expect(find.text('Passer'), findsNothing);
    });

    testWidgets('Commencer → Inscription, marque l’onboarding vu', (tester) async {
      final container = await pumpOnboarding(tester);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();

      expect(find.text('register-screen'), findsOneWidget);
      expect(container.read(onboardingSeenProvider), isTrue);
    });

    testWidgets("J'ai déjà un compte → Connexion, marque l'onboarding vu", (tester) async {
      final container = await pumpOnboarding(tester);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("J'ai déjà un compte"));
      await tester.pumpAndSettle();

      expect(find.text('login-screen'), findsOneWidget);
      expect(container.read(onboardingSeenProvider), isTrue);
    });

    testWidgets('aucun overflow — 360×640 (portrait), 320×568, paysage 667×375, tablette 800×1100', (tester) async {
      final originalSize = tester.view.physicalSize;
      final originalDpr = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalDpr;
      });
      tester.view.devicePixelRatio = 1.0;

      Future<void> checkAllPages() async {
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Les deux taps ont bien fait passer en page 3.
        expect(find.text('Commencer'), findsOneWidget);
      }

      for (final size in [const Size(320, 568), const Size(360, 640), const Size(667, 375), const Size(800, 1100)]) {
        await tester.pumpWidget(const SizedBox());
        tester.view.physicalSize = size;
        await pumpOnboarding(tester);
        try {
          await checkAllPages();
        } catch (e) {
          debugPrint('FAILED_SIZE=$size');
          rethrow;
        }
      }
    });
  });

  group('routerProvider (intégration, sans réseau)', () {
    AuthSession fakeSession() => AuthSession(
          user: const User(
            id: 'u1',
            displayName: 'Ulrich',
            email: 'u@example.com',
            currency: 'XOF',
            createdAt: null,
          ),
          accessToken: 'access-test',
          refreshToken: 'refresh-test',
        );

    Wallet fakeWallet() => const Wallet(
          id: 'w1',
          userId: 'u1',
          name: 'Portefeuille Test',
          initialAmount: 100000,
          startDate: '2026-11-01',
          currency: 'XOF',
          balance: 85000,
          savingsAmount: 0,
        );

    Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // Même approche que l'app : le routeur suit ref.watch(routerProvider).
          child: const _IntegrationApp(),
        ),
      );
      // pumpAndSettle boucle si un widget anime en continu — on avance à la main.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('première installation → onboarding au démarrage', (tester) async {
      final container = ProviderContainer(
        overrides: [
          onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(false)),
          authControllerProvider.overrideWith(() => _FakeAuthController(fakeSession())),
        ],
      );
      addTearDown(container.dispose);

      await pumpApp(tester, container);

      expect(find.text('Notez vos dépenses en quelques secondes'), findsOneWidget);
    });

    testWidgets('session connectée et onboarding vu → directement l’accueil', (tester) async {
      final container = ProviderContainer(
        overrides: [
          onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(true)),
          authControllerProvider.overrideWith(() => _FakeAuthController(fakeSession())),
          walletControllerProvider.overrideWith(() => _FakeWalletController(fakeWallet())),
          dashboardControllerProvider.overrideWith(() => _FakeDashboardController()),
          transactionsProvider.overrideWith(() => _FakeTransactionsController()),
          budgetsControllerProvider.overrideWith(() => _FakeBudgetsController()),
        ],
      );
      addTearDown(container.dispose);

      await pumpApp(tester, container);

      // L'accueil est visible (aucune redirection vers l'onboarding/connexion).
      expect(find.text('Reste'), findsOneWidget);
      expect(find.text('Portefeuille Test'), findsOneWidget);
    });

    testWidgets('première installation — Passer → Inscription (pas de retour vers l’onboarding)', (tester) async {
      final container = ProviderContainer(
        overrides: [
          onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(false)),
          authControllerProvider.overrideWith(() => _FakeAuthController(null)),
        ],
      );
      addTearDown(container.dispose);

      await pumpApp(tester, container);

      // On est sur l'onboarding (première ouverture).
      expect(find.text('Notez vos dépenses en quelques secondes'), findsOneWidget);

      // « Passer » → Inscription, marque vu, et ne renvoie pas à l'onboarding.
      await tester.tap(find.text('Passer'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('Créer mon compte'), findsOneWidget);
      expect(find.text('Passer'), findsNothing);
      expect(container.read(onboardingSeenProvider), isTrue);
    });

    testWidgets('déconnecté et onboarding vu → directement la connexion', (tester) async {
      final container = ProviderContainer(
        overrides: [
          onboardingSeenProvider.overrideWith(() => OnboardingSeenNotifier(true)),
        ],
      );
      addTearDown(container.dispose);

      await pumpApp(tester, container);

      expect(find.text('Se connecter'), findsWidgets);
    });
  });
}

class _IntegrationApp extends ConsumerWidget {
  const _IntegrationApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      routerConfig: router,
      themeMode: ThemeMode.light,
    );
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this.session);

  final AuthSession? session;

  @override
  FutureOr<AuthSession?> build() async => session;
}

class _FakeWalletController extends WalletController {
  _FakeWalletController(this.wallet);

  final Wallet wallet;

  @override
  FutureOr<Wallet?> build() async => wallet;
}

class _FakeDashboardController extends DashboardController {
  @override
  Future<DashboardData?> build() async => null;
}

class _FakeTransactionsController extends TransactionsController {
  @override
  Future<TransactionsState> build() async => const TransactionsState();
}

class _FakeBudgetsController extends BudgetsController {
  @override
  Future<List<Budget>> build() async => const [];
}
