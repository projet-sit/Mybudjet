# MYBUDGET

Application de gestion de budget personnel (FCFA, entiers uniquement — jamais de flottants).

- **Mobile** : Flutter + Riverpod + GoRouter + Dio (`mobile/`)
- **Backend** : Node.js / Express + PostgreSQL — hébergé sur Render (`backend/`), déploiement auto sur push `main`
- **Auth** : JWT (access 1 h, refresh 30 j haché SHA-256 en base)
- Règle d'or : `solde = montant initial + Σ revenus − Σ dépenses`, recalculé par le backend dans des transactions SQL avec verrou `FOR UPDATE` (concurrence sûre).
- Aucune donnée fictive : tout solde provient uniquement des données saisies par l'utilisateur.

## Ce que fait l'app

- Accueil avec solde / Reste / épargne / budget du mois
- Opérations (dépenses, revenus, épargne) avec recherche plein-historique, filtres, regroupement par jour
- Épargne (versement / retrait / tout récupérer, atomique, hors-ligne inclus)
- Budgets par catégorie (alertes 50/80/100 %)
- Statistiques par période, archives de périodes (historique mensuel conservé)
- Hors-ligne complet : les écritures partent en file d'attente, se rejouent au retour du réseau
- Réinitialisation avec archivage + annulation 10 s
- Export PDF / CSV

## Prérequis

- Flutter 3.22+ · Node 20+ · Docker Desktop (pour le PostgreSQL local)

## Démarrage

### 1. Base de données locale

```bash
docker compose up -d          # PostgreSQL 16 sur localhost:5434
cd backend && npm install && npm run migrate
```

### 2. Backend

```bash
cd backend && npm run dev     # http://localhost:3000/api/v1/health
```

### 3. Mobile

```bash
cd mobile
flutter pub get
flutter run                  # Android emulator : http://10.0.2.2:3000/api/v1
```

`mobile/.env` :

```
API_BASE_URL=https://mybudjet-rslh.onrender.com/api/v1   # production
# API_BASE_URL=http://10.0.2.2:3000/api/v1              # émulateur Android
```

## Tests

```bash
# Backend : unit + intégration de bout en bout (pg-mem, sans Docker)
cd backend
npm run test          # tests unitaires
npm run test:e2e      # flux complet HTTP réel (inscription, épargne, reset, restore…)
npm run test:all      # tout

# Mobile : widgets + recherche + outbox hors-ligne + dates
cd mobile && flutter test
```

## API principale

| Endpoint | Description |
|---|---|
| `POST /auth/register` `POST /auth/login` `POST /auth/refresh` `POST /auth/logout` | Authentification JWT |
| `POST /auth/forgot-password` `POST /auth/reset-password` | Réinitialisation |
| `GET/POST/PATCH/DELETE /wallets[...]` | Portefeuille + montant initial (historisé) |
| `POST /wallets/:id/savings/deposit` · `withdraw` · `withdraw-all` | Épargne (atomique, `savings_deposit`/`savings_withdrawal`) |
| `GET/POST/PATCH/DELETE /wallets/:id/transactions` | Transactions paginées/filtrées |
| `GET /wallets/:id/dashboard` `GET /wallets/:id/stats?period=week\|month\|year` | Tableau de bord + statistiques |
| `GET/POST/PATCH/DELETE /wallets/:id/budgets` | Budgets par catégorie (alertes 50/80/100 %) |
| `GET /wallets/:id/periods` · `POST /wallets/:id/period/:periodId/undo` · `POST /wallets/:id/periods/:periodId/restore` | Périodes : archives, annulation 10 s, restauration |
| `POST /wallets/:id/reset` | Remise à zéro (archive, épargne conservée par défaut) |
| `POST /client-errors` | Rapport de plantage mobile (fire-and-forget) |
| `GET /wallets/:id/export` | Export CSV complet |

## Production — notes opérationnelles

- **Render (plan gratuit)** : le service s'endort après inactivité ; le premier appel le réveille (~30–60 s). L'app le réveille discrètement au démarrage et au retour au premier plan. Pour éviter tout sommeil, créer un cron externe (ex. cron-job.org) qui ping `GET https://mybudjet-rslh.onrender.com/api/v1/health` toutes les 5–10 min.
- **Migrations** : jouées automatiquement au démarrage du conteneur (`node src/database/migrate.js && node src/server.js`). 008 ajoute les types `savings_deposit` / `savings_withdrawal`.
- **Logs structurés JSON** : chaque requête journalisée (`requestId`, statut, durée) ; erreurs 5xx avec stack ; crashs client via `POST /client-errors`.
- **Restauration d'une période archivée** : uniquement si la période courante est vide ; refus serveur sinon. Une restauration ramène solde/épargne/dates à l'état exact de la période archivée.
- **Clé de signature** : `mobile/android/app/mybudget.jks` + `key.properties` (ignorés par git) — sauvegarde dans `keystore-backup/`. **Ne jamais perdre** : les APK ne pourront plus se mettre à jour.
- **Suppression de compte** : définitive, avec confirmation forte. Export PDF/CSV possible avant suppression.
- **Monitoring** : aucun SDK externe requis ; les logs Render suffisent à détecter erreurs 5xx et crashs clients. Pour aller plus loin : brancher `POST /client-errors` sur Sentry/Logtail (une ligne dans `ErrorReporter`).
- **CORS** : `CORS_ORIGIN=*` en Render ; restreindre aux domaines de l'app en prod réelle.

## Télécharger l'app (APK)

**Lien stable (toujours la dernière version)** :

```
https://github.com/projet-sit/Mybudjet/releases/download/latest/app-arm64-v8a-direct-release-obfuscated.apk
```

Version actuelle : **v1.1.0** — `https://github.com/projet-sit/Mybudjet/releases/download/v1.1.0/app-arm64-v8a-direct-release-obfuscated.apk`

SHA-256 : `7e891ee04b3ee8fb284ce5920058cb05e0059a7e85d8ec685059da573190ca08`

Android arm64, signé avec la clé de release (mise à jour directe par dessus les APK précédents).

## APK de production

```bash
cd mobile
flutter build apk --release --flavor direct --split-per-abi --obfuscate --split-debug-info=build/debug-info
# → build/app/outputs/flutter-apk/app-arm64-v8a-direct-release.apk (~20 Mo)
```

## Structure

```
mobile/lib
  core/       thème MYBUDGET + date_format + recherche (transaction_search)
  features/   auth, onboarding, home, history, stats, budgets, savings, periods, reset, profile, shell
  models/     Transaction, DashboardData, StatsData, Budget, Period*, Wallet, User
  providers/  Riverpod (auth, wallet, transactions, dashboard, stats, budgets, sync, periods)
  routing/    GoRouter avec gardes d'authentification
  services/   api_client (Dio), outbox (file d'attente), cache hors-ligne, repositories,
              error_reporter (crash reports)
backend/src
  controllers / services / repositories / validators / routes / middlewares
  database/migrations (001→008)
backend/test
  unit/        tests unitaires
  integration/ harness pg-mem (vrai serveur Express en mémoire) + tests d'API de bout en bout
```
