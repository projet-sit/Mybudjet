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

Mobile : 60+ tests (`flutter test`) dont redirections, overflow 360×640, outbox, recherche, PDF, FAQ. Backend : 9 tests unitaires + 6 e2e (pg-mem, sans Docker). En complément : recette manuelle guidée sur un vrai téléphone.

## Tests mobile (Flutter)

Commande : `cd mobile && flutter test` (et `flutter analyze` pour l'analyse statique).

| Fichier | Sujet |
|---|---|
| `test/onboarding_test.dart` | 18 tests : `appRedirect` (toutes les règles), écrans d'onboarding, flux Passer→Inscription, **overflow 360×640** (+ 320×568, paysage, tablette) |
| `test/outbox_test.dart` | 9 tests : envoi, ordre, conservation sur erreur réseau, rollback sur 4xx, overlay, backup reset |
| `test/search_test.dart` | 16 tests : recherche insensible accents, montants, dates, surlignage |
| `test/widget_test.dart` | 6 tests : tuile de transaction (couleurs, signes), formatage |
| `test/sync_state_test.dart` | 3 tests : libellés de synchro |
| `test/auth_session_test.dart` | 4 tests : parsing session/jetons |
| `test/pdf_export_test.dart` | 2 tests : PDF généré valide |
| `test/api_connection_test.dart` | 2 tests réseau **skippés par défaut** (`--dart-define=RUN_API_TESTS=true`) |
| `test/help_test.dart` | 3 tests : écran « Aide et FAQ » (liste, ouverture/fermeture d'une question, aucun overflow 360×640) |

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
npm run test:e2e   # node --test test/integration/*.test.js
```

`pg-mem` émule PostgreSQL (dont `gen_random_uuid()` et `to_char` personnalisé) ; le vrai `app.js` tourne sur un port aléatoire pour chaque scénario : health, inscription/connexion, portefeuille, dépense (solde 100 000 → 93 000 après 7 000), budget, épargne (dépôt/retrait/tout récupérer, surplus refusé), reset, **annulation 10 s**, **restauration** (409 puis 200), client-errors.

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
3. **Budgets** : créer un budget Alimentation à 50 % du montant déjà dépensé → vérifier les niveaux d'alerte.
4. **Épargne** : verser, retirer, tout récupérer ; vérifier que les stats excluent l'épargne.
5. **Mode avion** : saisir 3 opérations hors-ligne → réactiver le réseau → vérifier la synchronisation (badge « Synchronisé ») et l'ordre.
6. **Remise à zéro** : hors-ligne puis en ligne ; vérifier l'archivage et l'annulation 10 s.
7. **Déconnexion / reconnexion** : restauration de session ; suppression de compte (dernier recours).
8. **Réveil serveur** : premier appel après 15 min d'inactivité (<60 s attendu).
9. **FAQ** : Profil → Aide et FAQ, chaque accordéon s'ouvre sans overflow (360×640).
10. **APK** : installer l'APK `direct` sur un Android 13+ d'entrée de gamme (Tecno/Infinix).

## Ce que les tests ne couvrent pas

- Pas de test de l'écran Paiement Mobile Money (n'existe pas).
- Pas de test de NotificationListenerService (n'existe pas).
- Pas d'e2e sur l'APK release obfusquée (couvert en CI uniquement au build).
- pg-mem ne couvre pas les vrais verrous `FOR UPDATE` (voir test d'intégration ci-dessus).
