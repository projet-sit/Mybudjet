# MYBUDGET

Application mobile de gestion de budget personnel (FCFA, entiers uniquement — jamais de flottants).
Mobile en **Flutter** (`mobile/`), backend **Node.js / Express + PostgreSQL** (`backend/`), hébergé sur **Render**.
Authentification **JWT maison** (access 1 h, refresh 30 j, hashé SHA-256 en base). **Pas de Firebase** : l'architecture initiale Firebase a été abandonnée en novembre 2026 (voir `docs/PHASE1_ARCHITECTURE.md`).
Règle d'or : `solde = montant initial + Σ revenus − Σ dépenses`, recalculé par le backend dans des transactions SQL avec verrou `FOR UPDATE`.

## Sommaire

- [Ce que fait l'app](#ce-que-fait-lapp)
- [Prérequis](#prérequis)
- [Installation sous Windows (pas à pas)](#installation-sous-windows-pas-à-pas)
- [Configuration](#configuration)
- [Lancement](#lancement)
- [Backend](#backend)
- [Tests](#tests)
- [Build de release (APK et AAB)](#build-de-release-apk-et-aab)
- [Structure du projet](#structure-du-projet)
- [Déploiement du backend (Render)](#déploiement-du-backend-render)
- [Dépannage rapide](#dépannage-rapide)
- [Documentation](#documentation)
- [Sécurité](#sécurité)
- [Contact](#contact)

**Résumé en 3 lignes** : MyBudget aide à suivre dépenses et revenus en FCFA, à gérer son épargne et ses budgets par catégorie, avec un mode hors-ligne complet. Le backend est une API Express + PostgreSQL auto-hébergée sur Render ; l'app mobile Flutter s'y connecte en HTTPS. Tout fonctionne sans Firebase ni aucun service externe payant.

## Ce que fait l'app

- Accueil avec solde / Reste (solde − épargne) / épargne / budget du mois
- Opérations (dépenses, revenus, épargne) avec recherche plein-historique, filtres, regroupement par jour
- Épargne : versement / retrait / tout récupérer, atomique, disponible hors-ligne
- Budgets par catégorie (alertes à 50 %, 80 % et 100 %)
- Statistiques par période, archives de périodes mensuelles (historique conservé)
- Hors-ligne : les écritures partent en file d'attente et se rejouent au retour du réseau
- Réinitialisation avec archivage + annulation 10 s
- Export PDF des transactions (l'export CSV est disponible côté API : `GET /api/v1/wallets/:id/export`)
- Aide et FAQ intégrée (Profil → Aide et FAQ), fonctionne hors-ligne

## Prérequis

| Outil | Version | Remarque |
|---|---|---|
| Flutter SDK | 3.22+ (testé avec 3.44.0 stable) | inclut Dart 3.12+ |
| Node.js | 20+ (testé avec 24.14.1) | backend |
| npm | 10+ | avec Node |
| Docker Desktop | récent | PostgreSQL 16 local (optionnel si tu utilises Render/Neon) |
| Git | récent | clone du dépôt |
| Android SDK / un appareil Android | — | pour installer l'APK |

Pas de compte Firebase, pas de Google Play Services nécessaires.

## Installation sous Windows (pas à pas)

```powershell
# 1. Récupérer le projet
git clone https://github.com/projet-sit/Mybudjet.git
cd Mybudjet

# 2. Base de données locale (PostgreSQL 16 dans Docker, port 5434)
docker compose up -d

# 3. Backend : dépendances + migrations + démarrage
cd backend
npm install
npm run migrate     # crée/actualise les tables
npm start            # http://localhost:3000/api/v1/health
cd ..

# 4. Mobile : dépendances
cd mobile
flutter pub get
flutter analyze      # doit afficher « No issues found! »
flutter test         # 60+ tests, doivent tous passer
flutter run          # sur un appareil/émulateur connecté
```

`flutter run` utilise l'URL déclarée dans `mobile/.env` (voir ci-dessous). Pour le dev local sur émulateur Android, utilise `http://10.0.2.2:3000/api/v1`.

## Configuration

### mobile/.env (non versionné)

```dotenv
# Production (backend hébergé sur Render)
API_BASE_URL=https://mybudjet-rslh.onrender.com/api/v1

# Dev local sur émulateur Android
# API_BASE_URL=http://10.0.2.2:3000/api/v1
# Dev local sur téléphone physique du même Wi-Fi
# API_BASE_URL=http://<IP-DU-PC>:3000/api/v1
```

### backend/.env (non versionné)

Copie `backend/.env.example` vers `backend/.env` et renseigne les **noms** suivants (jamais commités) :

| Nom | Rôle |
|---|---|
| `PORT` | Port d'écoute (défaut 3000) |
| `NODE_ENV` | `development` / `production` / `test` |
| `CORS_ORIGIN` | `*` ou liste CSV d'origines autorisées |
| `DATABASE_URL` | URL Postgres complète (prioritaire, ex. Neon avec `sslmode=require`) |
| `DB_HOST` `DB_PORT` `DB_NAME` `DB_USER` `DB_PASSWORD` | Paramètres Postgres locaux (docker-compose) |
| `DB_SSL` | `true` pour forcer SSL (ignoré si `DATABASE_URL` contient `sslmode=require`) |
| `JWT_SECRET` | Secret de signature des JWT — **obligatoire en production** |
| `JWT_ACCESS_EXPIRES_IN` | Durée access token (défaut `1h`) |
| `JWT_REFRESH_EXPIRES_IN` | Durée refresh token (défaut `30d`) |
| `RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX` | Fenêtre et quota du rate limiting global (défaut 60000 ms / 120) |
| `EXPOSE_DEV_RESET_TOKEN` | `true` uniquement en développement local pour tester le reset de mot de passe |

> Exemple factice (à remplacer) : `JWT_SECRET=exemple-factice-a-remplacer-000`, `DATABASE_URL=postgresql://exemple:exemple@localhost:5434/mybudget`.

### Firebase / Firestore

**Il n'y a rien à configurer** : le projet n'utilise ni Firebase, ni Firestore, ni Firebase Auth, ni FCM. Les anciennes traces (`docs/firestore.rules`, routes « Ciel ») sont obsolètes — voir [`docs/securite-et-confidentialite.md`](docs/securite-et-confidentialite.md).

## Lancement

### Mobile — flavors

Le projet définit deux flavors Gradle (dimension `store`), identiques pour l'instant (même `applicationId` `com.mybudget.mybudget`) :

```powershell
flutter run --flavor direct   # flavor utilisé pour les APK distribués
flutter run --flavor play     # identique ; prévu pour un futur dépôt Play Store
```

Sans `--flavor`, Flutter installe la variante par défaut. `web/` et `ios/` existent mais seul le build Android est maintenu et testé.

### Backend

```powershell
cd backend
npm run dev     # nodemon, http://localhost:3000/api/v1/health
# ou
npm start       # mode production local
```

## Backend

```powershell
cd backend
npm install
npm run migrate   # applique les migrations SQL (src/database/migrations/)
npm start
```

Endpoints principaux (tous préfixés `/api/v1`, authentification `Authorization: Bearer <accessToken>` sauf mention contraire) :

| Endpoint | Description |
|---|---|
| `GET /health` | Sonde publique (service, version, connexion DB) — utilisée par Render |
| `POST /auth/register` `POST /auth/login` `POST /auth/refresh` `POST /auth/logout` | Authentification JWT |
| `POST /auth/forgot-password` `POST /auth/reset-password` | Réinitialisation de mot de passe |
| `GET/PATCH/DELETE /auth/me` | Profil / mise à jour / suppression définitive du compte |
| `GET/POST /wallets` `GET /wallets/:id` | Portefeuilles |
| `GET /wallets/:id/initial-amount/history` `PATCH /wallets/:id/initial-amount` | Montant initial historisé |
| `POST /wallets/:id/savings/deposit` `withdraw` `withdraw-all` | Épargne (atomique) |
| `GET/POST /wallets/:id/transactions` `GET/PATCH/DELETE /wallets/:id/transactions/:txId` | Transactions (pagination, filtres, recherche) |
| `GET /wallets/:id/dashboard` `GET /wallets/:id/stats?period=week\|month\|year` | Tableau de bord + statistiques |
| `GET/POST/PATCH/DELETE /wallets/:id/budgets` | Budgets par catégorie (alertes 50/80/100 %) |
| `GET /wallets/:id/period` `POST /wallets/:id/period/next` `POST .../period/:periodId/undo` | Périodes mensuelles + annulation 10 s |
| `GET /wallets/:id/periods` `POST /wallets/:id/periods/:periodId/restore` | Archives de périodes |
| `POST /wallets/:id/reset` | Remise à zéro (archive, épargne conservée par défaut) |
| `GET/POST/PATCH/DELETE /wallets/:id/goals` + `contribute` `withdraw` | Objectifs d'épargne |
| `GET /wallets/:id/export` | Export CSV complet |
| `POST /client-errors` | Remontée de plantages mobiles (anonyme, fire-and-forget) |

Documentation OpenAPI complète : [`docs/api/openapi.yaml`](docs/api/openapi.yaml) (lue en ligne : `docs/api/index.html`).

## Tests

```powershell
# Mobile : widgets + recherche + outbox hors-ligne + dates + overflow 360x640
cd mobile
flutter test

# Backend : tests unitaires (node:test)
cd backend
npm test            # money + ciel (9 tests)

# Backend : end-to-end de bout en bout (pg-mem, vrai serveur Express en mémoire)
npm run test:e2e    # 6 tests (inscription, épargne, reset, undo, restore…)

# Tout
npm run test:all
```

`npm run test:integration` cible un serveur déjà lancé en local (`BASE_URL`, défaut `http://localhost:3000/api/v1`) — non couvert par `npm test`.

## Build de release (APK et AAB)

### APK arm64 léger (distribution aux testeurs)

```powershell
cd mobile
flutter pub get
flutter analyze
flutter build apk --release --flavor direct --split-per-abi `
  --obfuscate --split-debug-info=build/debug-info
# → build\app\outputs\flutter-apk\app-arm64-v8a-direct-release.apk (~20 Mo)
```

### AAB (Play Store)

```powershell
cd mobile
flutter build appbundle --release --flavor play `
  --obfuscate --split-debug-info=build/debug-info
# → build\app\outputs\bundle\playRelease\app-play-release.aab (≈ 53 Mo, testé le 17/11/2026)
```

> La signature release utilise `android/key.properties` (non versionné) ; sans ce fichier, la release retombe sur la clé debug.

La clé de signature (`mobile/android/app/mybudget.jks` + `key.properties`) est **indispensable** pour les mises à jour : elle est sauvegardée dans `keystore-backup/` (non versionné). Ne la perdre **en aucun cas**.

L'APK arm64 est distribuée via GitHub Releases (`releases/latest` et tags `v*`).

## Structure du projet

```
mobile/lib
  core/        thème MYBUDGET + date_format + recherche (transaction_search) + widgets
  features/    auth, onboarding, home, history, stats, budgets, savings, periods, reset, profile, help (FAQ), shell
  models/      Transaction, DashboardData, StatsData, Budget, Period*, Wallet, User
  providers/   Riverpod (auth, wallet, transactions, dashboard, stats, budgets, sync, onboarding, prefs, shell)
  routing/     GoRouter avec gardes d'authentification
  services/    api_client (Dio), outbox (file d'attente), cache hors-ligne, repositories,
               error_reporter (crash reports), transaction_pdf_export_service
  widgets/     logo, transaction_tile
backend/src
  controllers / services / repositories / validators / routes / middlewares
  config/      db.js (Pool pg), env.js
  database/    migrate.js + migrations (001→009 ; 004 absent)
backend/test
  unit/        tests unitaires (money, ciel)
  integration/ harness pg-mem + tests d'API de bout en bout
docs/          documentation (architecture, données, métier, API, guide, conception)
```

## Déploiement du backend (Render)

Le backend est hébergé sur **Render** (plan gratuit) via `render.yaml` à la racine : runtime Docker, `healthCheckPath: /api/v1/health`, région `frankfurt`. Chaque push sur `main` redéploie automatiquement. La base est migrée au démarrage du conteneur (`node src/database/migrate.js && node src/server.js`).

- **URL de prod** : `https://mybudjet-rslh.onrender.com/api/v1`
- **Plan gratuit** : le service s'endort après ~15 min d'inactivité ; le premier appel le réveille (~30–60 s). Pour éviter tout sommeil (et tout risque de mise en veille du plan gratuit), passer au plan payant ou utiliser un cron externe.
- **Mise en veille à éviter** : cron externe qui ping `GET https://mybudjet-rslh.onrender.com/api/v1/health` toutes les 5–10 min (ex. cron-job.org).
- **Variables d'environnement** (onglet Environment du service) : `NODE_ENV=production`, `PORT=10000`, `DATABASE_URL` (Neon, `sslmode=require`), `JWT_SECRET`, `CORS_ORIGIN`.
- **Logs structurés JSON** : chaque requête journalisée (`requestId`, statut, durée) ; 5xx avec stack ; plantages client via `POST /client-errors`.
- **CORS** : `CORS_ORIGIN=*` aujourd'hui ; restreindre en production réelle.
- Procédure Neon + Render détaillée : [`docs/DEPLOIEMENT.md`](docs/DEPLOIEMENT.md).

## Dépannage rapide

| Symptôme | Piste |
|---|---|
| `docker compose up` échoue sur le port 5434 | Un autre PostgreSQL occupe le port : arrête-le ou change le mapping dans `docker-compose.yml` |
| `npm run migrate` → `ECONNREFUSED` | La base n'est pas démarrée : `docker compose up -d` puis réessaie |
| Écran « Hors ligne » sur le téléphone alors que le réseau marche | Vérifie `mobile/.env` (`API_BASE_URL`) et que le téléphone est sur le même Wi-Fi que le PC, ou utilise l'URL Render |
| Premier appel très lent (30–60 s) | Normal en plan gratuit Render : le service se réveille. L'app le réveille discrètement au démarrage |
| `flutter analyze` échoue | Lance `flutter pub get` ; si ça persiste, supprime `.dart_tool` puis `flutter pub get` |
| Build Gradle échoue | Voir [`docs/depannage.md`](docs/depannage.md) |
| APK qui ne s'installe pas (« application non installée ») | Désinstalle l'ancienne version signée avec une autre clé, puis installe la nouvelle |

## Documentation

- [`docs/README.md`](docs/README.md) — index de la documentation + build des diagrammes/exports
- [`docs/architecture.md`](docs/architecture.md) · [`docs/modele-de-donnees.md`](docs/modele-de-donnees.md) · [`docs/regles-metier.md`](docs/regles-metier.md)
- [`docs/hors-ligne-et-synchronisation.md`](docs/hors-ligne-et-synchronisation.md) · [`docs/detection-notifications.md`](docs/detection-notifications.md)
- [`docs/securite-et-confidentialite.md`](docs/securite-et-confidentialite.md) · [`docs/politique-confidentialite.md`](docs/politique-confidentialite.md)
- [`docs/DEPLOIEMENT.md`](docs/DEPLOIEMENT.md) · [`docs/tests.md`](docs/tests.md) · [`docs/depannage.md`](docs/depannage.md)
- [`docs/api/openapi.yaml`](docs/api/openapi.yaml) — référence de l'API (OpenAPI 3.1)
- `docs/export/guide-utilisateur.pdf` — guide utilisateur · `docs/export/dossier-de-conception.pdf` — dossier de conception
- [`CHANGELOG.md`](CHANGELOG.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md)

## Sécurité

- Aucun secret dans le dépôt : `.env`, `key.properties`, `mybudget.jks`, `keystore-backup/` sont ignorés par git.
- Mots de passe hashés bcrypt ; refresh tokens hashés SHA-256 ; révocation globale à chaque changement de mot de passe.
- Isolation stricte par utilisateur côté serveur (chaque requête joint le `user_id` du JWT) ; les montants sont des entiers FCFA avec contraintes `CHECK` en base.
- Voir [`docs/securite-et-confidentialite.md`](docs/securite-et-confidentialite.md).

## Contact

[À REMPLIR] — e-mail de contact du mainteneur.

*MyBudget — l'argent, clair et simple. Montants en FCFA, entiers uniquement.*
