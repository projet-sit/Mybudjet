/// Redirection initiale de l'app (onboarding → connexion → accueil).
/// Fonction pure : testée unitairement dans test/onboarding_test.dart.
///
/// Règles :
/// - onboarding jamais vu : toujours l'onboarding (avant la connexion) ;
/// - déjà vu : jamais l'onboarding (déconnexion → connexion directe) ;
/// - restauration de la session : écran d'attente /splash, puis décision ;
/// - état décidé : accueil si connecté, connexion sinon, écrans d'auth bloqués
///   quand connecté.
String? appRedirect({
  required bool onboardingSeen,
  required bool authLoading,
  required bool loggedIn,
  required String location,
}) {
  final isOnboarding = location == '/onboarding';
  final isAuthScreen = location == '/login' ||
      location == '/register' ||
      location == '/forgot-password';
  final isSplash = location == '/splash';

  // Onboarding pas encore vu : tout mène à l'onboarding.
  if (!onboardingSeen) {
    return isOnboarding ? null : '/onboarding';
  }
  // Onboarding déjà vu : on n'y revient jamais.
  if (isOnboarding) {
    return loggedIn ? '/home' : '/login';
  }
  // Fin de la restauration : on sort du splash vers la bonne destination.
  if (isSplash) {
    if (authLoading) return null;
    return loggedIn ? '/home' : '/login';
  }
  // Restauration en cours : écran d'attente, sauf pour l'onboarding et
  // les écrans d'authentification qui, eux, peuvent s'afficher directement.
  if (authLoading) {
    return (isAuthScreen) ? null : '/splash';
  }
  // Connecté : les écrans d'authentification sont interdits.
  if (loggedIn && isAuthScreen) return '/home';
  // Non connecté : tout le reste est protégé.
  if (!loggedIn && !isAuthScreen) return '/login';

  return null;
}
