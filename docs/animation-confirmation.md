# Animation de confirmation « coche verte »

Animation 1,2 s affichée après un enregistrement réussi. Elle remplace l'ancienne
dialog « Effectué » (supprimée). Aucun bouton, aucun toast parasite.

## Événements autorisés (liste FERMÉE)

| Icône / carte          | Déclencheur                                             | Sous-titre        |
|------------------------|---------------------------------------------------------|-------------------|
| « Dépense enregistrée » | `transactionsProvider.createTransaction` (type dépense) | montant formaté   |
| « Revenu enregistré »   | `transactionsProvider.createTransaction` (type revenu)  | montant formaté   |
| « Portefeuille créé »   | `walletControllerProvider.create`                       | nom du portefeuille |
| « Versement enregistré »| `walletControllerProvider.setSavings` (delta > 0)       | montant du versement |
| « Retrait enregistré »  | `walletControllerProvider.setSavings` (0 < delta < 0)   | montant du retrait |
| « Épargne récupérée »   | `walletControllerProvider.setSavings` (nouveau montant = 0 depuis > 0, « Tout récupérer ») | montant récupéré |

L'émission a lieu **après validation locale réussie** — y compris hors-ligne
(la synchronisation est alors en attente, l'icône de synchro du haut change
seule ; l'animation est identique).

## Événements INTERDITS (jamais d'animation)

L'animation ne se déclenche JAMAIS après :

- ajout, changement ou suppression de la **photo de profil** ;
- modification du profil (nom, e-mail, mot de passe), d'un réglage ou d'un interrupteur ;
- **modification ou suppression** d'une opération, d'un portefeuille ou d'une catégorie ;
- réinitialisation, export, déconnexion ;
- arrivée de données par **synchronisation**, depuis un autre appareil ou au
  **démarrage** (listeners / invalidations) ;
- **échec d'enregistrement** (aucun événement émis ; le bouton « Enregistrer »
  tremble légèrement et un message clair s'affiche).

Pour ces cas, l'app garde le retour existant (snackbar discret) ou n'affiche rien.

## Architecture

Feature `lib/features/success_feedback/` :

- `models/success_event.dart` — enum `SuccessEventType` + `SuccessEvent`
  (titre et sous-titre déjà formatés via `formatMoneyCurrent` / nom du portefeuille) ;
- `providers/success_feedback_provider.dart` — `SuccessFeedbackController`
  (Riverpod `Notifier<SuccessEvent?>`). `emit(event)` publie et auto-efface au
  bout de ~1,2 s ; un tap n'importe où appelle `clear()`. Deux enregistrements
  rapides : le second remplace le premier, **pas de file d'attente** ;
- `widgets/success_icon.dart` — `SuccessIcon` (carré arrondi vert `#059669`,
  rayon 28, coche blanche tracée en `CustomPainter` avec `PathMetric.extractPath`,
  onde verte claire) ; `HapticFeedback.lightImpact()` à la fin du tracé ;
- `widgets/success_feedback_overlay.dart` — `SuccessFeedbackOverlay`, branché
  **une seule fois** au niveau racine (`MaterialApp.router` → `builder` dans
  `lib/main.dart`), au-dessus de toute la navigation ;
- `RepaintBoundary` ; un seul `AnimationController` côté icône ; coche et carré
  sans image ni Lottie ; aucune nouvelle dépendance.

Après l'animation : le **Reste** défile vers sa nouvelle valeur (compteur animé
≈ 0,6 s, `_ResteCounter` dans `home_screen.dart`), et la ligne créée glisse dans
« Dernières opérations » avec un surlignage bleu clair estompé en ~1 s
(`_HighlightedTransactionRow`, indexé par `lastCreatedTransactionIdProvider`).
Ce surlignage ne concerne que l'opération créée dans la session.

### Points d'émission (les seuls endroits du code qui appellent `.emit`)

- `lib/providers/transaction_provider.dart` → `createTransaction`
  (`expenseAdded` / `incomeAdded`), après succès local ou serveur ;
- `lib/providers/wallet_provider.dart` → `create` (`walletCreated`),
  `setSavings` (`savingsDeposited` / `savingsWithdrawn` / `savingsRecovered`).

Le code photo, le profil, les réglages, les listeners de synchro, le démarrage
(`refresh`, `refreshAll`, invalidations) n'importent pas la feature et ne peuvent
pas émettre. `test/success_feedback_architecture_test.dart` fait échouer la suite
si `.emit(` apparaît ailleurs que dans les fichiers autorisés, ou si le flux
photo/profil importe `success_feedback`.

## Comportement

- Appui sur « Enregistrer » : le panneau se ferme, puis l'animation démarre.
- Tap n'importe où : fermeture immédiate, aucun bouton sous-jacent déclenché.
- Hors-ligne : même animation ; la sync se fera au retour du réseau.
- Échec : pas de coche ; le bouton tremble + message clair (snackbar rouge).
- Réduire les animations (`MediaQuery.disableAnimations`) : fondu 150 ms +
  coche déjà dessinée, pas de rebond ni d'onde ; haptique inchangée.
- Accessibilité : `Semantics(liveRegion: true)` annonce
  « Dépense enregistrée — 5 000 FCFA », etc. Aucun son.
- Thème clair/sombre : le vert reste `#059669`, voile noir à 35 %.

## Tests

- `test/success_feedback_test.dart` — chaque événement autorisé (titre +
  sous-titre), fermeture au tap n'importe où (tap-to-close), expiration ~1,2 s, double enregistrement
  rapide (une seule animation, la dernière), reduce-motion, annonce
  `liveRegion`, aucun overflow à 360×640, non-déclenchement sans émission.
- `test/success_feedback_architecture_test.dart` — garde-fou : `.emit(` limité
  aux cas d'usage autorisés ; flux photo/profil jamais lié à la feature.

Non couverts automatiquement (à vérifier sur téléphone, cf. VÉRITÉ MANUELLE en bas) :
persistance hors-ligne réelle, sync au retour du réseau.

## Ajouter un nouvel événement

1. Ajouter la valeur dans `SuccessEventType` (liste fermée — changement
   volontaire obligatoire).
2. Ajouter son `title` dans `SuccessEvent` (et l'éventuel formatage de sous-titre).
3. Émettre **uniquement** dans le cas d'usage correspondant, après validation
   locale du succès (jamais dans un écran/widget/listener, jamais au démarrage).
4. Ajouter le cas dans `test/success_feedback_test.dart` (titre attendu).
5. Mettre à jour ce fichier + une ligne dans `CHANGELOG.md`.

## Vérification manuelle sur téléphone

- Ajouter une dépense, un revenu, un portefeuille, un versement, un retrait
  d'épargne et « Tout récupérer » : animation OK à chaque fois.
- Ajouter, changer, supprimer la photo de profil, modifier le nom, changer un
  réglage, modifier/supprimer une opération, réinitialiser : aucune animation.
- Ajouter une dépense en mode avion : animation OK ; au retour du réseau, la
  synchronisation se fait et l'opération apparaît sur l'appareil/serveur.
