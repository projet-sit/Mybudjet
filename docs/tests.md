# Tests

## Sommaire

- [Résumé](#résumé)
- [Tests mobile (Flutter)](#tests-mobile-flutter)
- [Tests backend (unitaires)](#tests-backend-unitaires)
- [Tests backend (e2e, pg-mem)](#tests-backend-e2e-pg-mem)
- [Tests d'intégration API (serveur local)](#tests-dintégration-api-serveur-local)
- [Recette manuelle](#recette-manuelle)
- [Ce que les tests ne couvrent pas](#ce-que-les-tests-ne-couvrent-pas)

## Résumé

Mobile : 82 tests passent (`flutter test`) dont redirections, overflow 360×640, outbox, recherche, PDF, FAQ, réinitialisation, alertes. Backend : 9 unitaires + 10 e2e (pg-mem) + 1 test d'atomicité sur vraie PostgreSQL (`test:rollback`). En complément : recette manuelle guidée sur un vrai téléphone.

## Tests mobile (Flutter)

Commande : `cd mobile && flutter test` (et `flutter analyze` pour l'analyse statique).

| Fichier | Sujet |
|---|---|
| `test/onboarding_test.dart` | 18 tests : `appRedirect` (toutes les règles), écrans d'onboarding, flux Passer→Inscription, **overflow 360×640** (+ 320×568, paysage, tablette) |
| `test/outbox_test.dart` | 13 tests : envoi, ordre, rollback 4xx, catégories hors-ligne (création, fusion 409, rollback, remapping d'id serveur), `clearAll` |
| `test/search_test.dart` | 17 tests : recherche insensible accents, montants, dates, surlignage, catégories personnalisées |
| `test/widget_test.dart` | 6 tests : tuile de transaction (couleurs, signes), formatage |
| `test/sync_state_test.dart` | 3 tests : libellés de synchro |
| `test/auth_session_test.dart` | 4 tests : parsing session/jetons |
| `test/pdf_export_test.dart` | 2 tests : PDF généré valide |
| `test/api_connection_test.dart` | 2 tests réseau **skippés par défaut** (`--dart-define=RUN_API_TESTS=true`) |
| `test/help_test.dart` | 3 tests : écran « Aide et FAQ » (liste, ouverture/fermeture, aucun overflow 360×640) |
| `test/reset_screen_test.dart` | 3 tests : « Réinitialiser tout » (bouton désactivé tant que « REINITIALISER » n'est pas exact, overflow 360×640) |
| `test/budget_alerts_test.dart` | 7 tests : évaluation des seuils 80 % / 100 %, déduplication par seuil et par période, interrupteur éteint |
| `test/category_names_test.dart` | 8 tests : normalisation/validation des noms, ordre d'affichage |

## Tests backend (unitaires)

```powershell
cd backend
npm test           # node --test test/unit/*.test.js
```

- `money.test.js` : validation/parsing de montants entiers.
- `ciel.test.js` : endpoints Ciel (héritage) — vérifie le comportement actuel (données vides).

## Tests backend (e2e, pg-mem)

```powershell
cd backend
npm run test:e2e        # node --test test/integration/*.test.js (10 tests)
npm run test:rollback   # atomicité du reset sur une vraie PostgreSQL locale (Docker requis)
```

`pg-mem` émule PostgreSQL (dont `gen_random_uuid()` et `to_char` personnalisé) ; le vrai `app.js` tourne sur un port aléatoire pour chaque scénario : health, inscription/connexion, portefeuille, dépense (solde 100 000 → 93 000 après 7 000), budget, épargne (dépôt/retrait/tout récupérer, surplus refusé), reset, **annulation 10 s**, **restauration** (409 puis 200), client-errors, **catégories personnalisées** (création via « Autres » simulée côté API, doublons casse/accents, limite 30/type, renommage avec propagation, suppression + réaffectation à « Autres », budget lié avec confirmation, export CSV), **réinitialisation complète** (`/me/reset`, vide toute la base du compte, conserve le compte, `data_epoch` incrémenté, isolation inter-utilisateurs).

> pg-mem ne supporte pas `ROLLBACK` ; l'atomicité réelle de `/me/reset` est vérifiée sur une vraie PostgreSQL locale (Docker `mybudget-db`) via `npm run test:rollback` (crée/détruit une base jetable `mybudget_rollback_test`, migre, force un échec avant commit pour prouver que rien n'est supprimé).

Note : les migrations sont jouées avec les index partiels et le trigger épargne **neutralisés** par pg-mem — la concurrence elle-même est couverte par `test/finance.test.js` sur serveur réel.

## Tests d'intégration API (serveur local)

```powershell
# Terminal 1
cd backend ; npm run dev
# Terminal 2
cd backend ; npm run test:integration   # utilise BASE_URL (def. http://localhost:3000/api/v1)
```

Couvre : health, inscription 201/409/400, **concurrence de 2 dépenses parallèles** (une 201, une 409), export CSV, isolation inter-utilisateurs (403/404).

## Recette manuelle

À exécuter sur un vrai téléphone (voir aussi [`TESTS_HORS_LIGNE.md`](TESTS_HORS_LIGNE.md)) :

1. **Création de compte** par téléphone + création de portefeuille (audit du flux jusqu'à l'accueil, zéro pop-up parasite).
2. **Saisie** : 5 dépenses/revenus, catégories, dates antérieures ; vérifier le Reste et le solde.
3. **Budgets** : créer un budget Alimentation à 50 % du montant déjà dépensé → vérifier les niveaux d'alerte ; dépasser 80 % → notification locale ; couper « Alertes de budget » → plus aucune notification.
4. **Épargne** : verser, retirer, tout récupérer ; vérifier que les stats excluent l'épargne.
5. **Catégorie personnalisée** : saisir une dépense avec « Autres » → taper « Coiffure » + Valider → vérifier qu'elle apparaît, qu'elle se réutilise, qu'on la retrouve dans Recherche et dans Mes catégories ; essayer un doublon (casse/accents) → l'existante est sélectionnée.
6. **Mode avion** : saisir 3 opérations hors-ligne, dont une catégorie personnalisée → réactiver le réseau → vérifier la synchronisation, l'ordre, et l'absence de doublon de catégorie.
7. **Réinitialiser tout** : après la réinitialisation, vérifier que le compte est vide, que le mot de passe fonctionne toujours, et qu'aucun retour en arrière ne ressuscite une opération ; sur un 2ᵉ téléphone même compte, vérifier l'effacement local.
8. **Déconnexion / reconnexion** : restauration de session ; suppression de compte (dernier recours).
9. **Réveil serveur** : premier appel après 15 min d'inactivité (<60 s attendu).
10. **FAQ** : Profil → Aide et FAQ, chaque accordéon s'ouvre sans overflow (360×640).
11. **APK** : installer l'APK `direct` sur un Android 13+ d'entrée de gamme (Tecno/Infinix) + vérifier la permission notifications à la première activation des alertes.

## Ce que les tests ne couvrent pas

- Pas de test de l'écran Paiement Mobile Money (n'existe pas).
- Pas de test de NotificationListenerService (n'existe pas).
- Pas d'e2e sur l'APK release obfusquée (couvert en CI uniquement au build).
- pg-mem ne couvre pas les vrais verrous `FOR UPDATE` (voir test d'intégration ci-dessus).
