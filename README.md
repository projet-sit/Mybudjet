# MYBUDGET

Application de gestion de budget personnel (FCFA, entiers uniquement — jamais de flottants).

- **Mobile** : Flutter + Riverpod + GoRouter + Dio (dossier `mobile/`)
- **Backend** : Node.js / Express + PostgreSQL (dossier `backend/`, Docker port **5434**)
- **Auth** : JWT (access 1 h, refresh 30 j haché SHA-256 en base)
- Règle d'or : `solde = montant initial + Σ revenus − Σ dépenses`, recalculé par le backend dans des transactions SQL avec verrou `FOR UPDATE` (concurrence sûre).
- Aucune donnée fictive : tout solde provient uniquement des données saisies par l'utilisateur.

## Prérequis

- Flutter 3.22+ / Node 20+
- Docker Desktop (pour PostgreSQL)

## Démarrage

### 1. Base de données

```bash
cd backend
docker compose up -d          # PostgreSQL 16 sur localhost:5434
npm install
npm run migrate               # migrations 001→003 (users, wallets, transactions, budgets)
```

### 2. Backend

```bash
cd backend
npm run dev                   # http://localhost:3000/api/v1/health
```

### 3. Mobile

```bash
cd mobile
flutter pub get
flutter run                   # Android : API_BASE_URL = http://10.0.2.2:3000/api/v1
```

`mobile/.env` :
```
API_BASE_URL=http://10.0.2.2:3000/api/v1
```

## Tests

```bash
# Backend (20 vérifications : scénario financier, concurrence, isolation…)
cd backend && node test/finance.test.js

# Mobile (réseau + widgets ; backend démarré requis)
cd mobile && flutter test
```

## API principale

| Endpoint | Description |
|---|---|
| `POST /auth/register` `POST /auth/login` `POST /auth/refresh` `POST /auth/logout` | Authentification JWT |
| `POST /auth/forgot-password` `POST /auth/reset-password` | Réinitialisation |
| `GET/POST/PATCH/DELETE /wallets[...]` | Portefeuille + montant initial (historisé) |
| `GET/POST/PATCH/DELETE /wallets/:id/transactions` | Transactions paginées/filtrées |
| `GET /wallets/:id/dashboard` `GET /wallets/:id/stats?period=week|month|year` | Tableau de bord + statistiques |
| `GET/POST/PATCH/DELETE /wallets/:id/budgets` | Budgets par catégorie (alertes 50/80/100 %) |
| `GET /wallets/:id/export` | Export CSV complet |

## Génération de l'APK

```bash
cd mobile
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

## Structure

```
mobile/lib
  core/       thème MYBUDGET (vert profond #0B5D3B, blanc cassé #F7F7F2)
  features/   auth, onboarding, home, history, stats, budgets, profile, shell
  models/     Transaction, DashboardData, StatsData, Budget
  providers/  Riverpod (auth, wallet, transactions, dashboard, stats, budgets)
  routing/    GoRouter avec gardes d'authentification
  services/   api_client (Dio), repositories, cache hors-ligne
backend/src
  controllers / services / repositories / validators / routes / middlewares
  database/migrations (001_core, 002_wallets, 003_transactions_budgets)
```
=======
# Mybudjet
Application de suivie financier 
>>>>>>> origin/main
