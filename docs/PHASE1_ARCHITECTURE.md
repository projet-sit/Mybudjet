# MYBUDGET — Documentation Technique (Phase 1 : Analyse et Architecture)

Version : 1.2 — Date : 12/11/2026
⚠️ **Changement majeur** : Firebase a été abandonné au profit de **PostgreSQL (Docker)** + authentification **JWT**.
Statut : Architecture validée ; Phases 1-3 terminées.

---

## 1. Environnement vérifié

| Outil | Version | Statut |
|---|---|---|
| Flutter | 3.44.0 (stable) | ✅ |
| Dart | 3.12.0 | ✅ `dart analyze` : 0 erreur |
| Node.js | 24.14.1 | ✅ |
| PostgreSQL | 16 (Docker `mybudget-db`) | ✅ port 5434 |
| Docker Compose | v5.6.0 | ✅ |

Référence UI : `Kit UI financier MYBUDGET en français.png` (racine du projet).
Identité graphique : vert profond `#0B5D3B`, blanc cassé `#F7F7F2`, rouge dépenses `#E5484D`, vert revenus `#16A34A`, cartes arrondies 16-24, navigation 5 onglets + FAB.

---

## 2. Architecture globale (rev. PostgreSQL/JWT)

```
┌─────────────────────┐        HTTPS / REST (JSON)        ┌──────────────────────┐
│  Flutter (mobile)   │ ───────────────────────────────►  │  Node.js + Express   │
│  UI + Riverpod      │   Authorization: Bearer <JWT>     │  Logique métier      │
│  GoRouter (gardes)  │ ◄───────────────────────────────  │  bcrypt, JWT,        │
│  Dio (HTTP)         │        JSON + codes HTTP          │  validations         │
└─────────────────────┘                                   └──────────┬───────────┘
                                                                       │ pg (node-postgres)
                                                                       ▼
                                                          ┌──────────────────────┐
                                                          │ PostgreSQL 16 (Docker)│
                                                          │ users, refresh_tokens,│
                                                          │ password_reset_tokens │
                                                          │ wallets, transactions │
                                                          │ budgets (phases 4/5/9)│
                                                          └──────────────────────┘
```

### Responsabilités
- **Flutter** : UI, navigation (GoRouter + gardes d'auth), état (Riverpod `AsyncNotifier`), stockage local de session (SharedPreferences), appels API via Dio.
- **Node.js/Express** : authentification (bcrypt + JWT access/refresh), validation systématique, **transactions atomiques PostgreSQL** pour le moteur financier, agrégations statistiques.
- **PostgreSQL** : source de vérité ; contraintes d'intégrité (UNIQUE, FK, CHECK).

---

## 3. Structure des dossiers (réalisée)

```
E:\Dépense\
├── docs/
├── docker-compose.yml           # PostgreSQL 16 (mybudget-db, port 5434)
├── mobile/
│   ├── lib/
│   │   ├── core/theme/app_theme.dart      # thème (vert profond, blanc cassé…)
│   │   ├── config/app_env.dart            # URL API
│   │   ├── models/user.dart               # User + AuthSession
│   │   ├── services/                      # api_client (Dio), auth_repository, token_storage
│   │   ├── providers/auth_provider.dart   # AuthController (AsyncNotifier Riverpod)
│   │   ├── features/                      # splash, auth (login/register/forgot), home, diagnostic
│   │   ├── widgets/logo.dart
│   │   └── routing/app_router.dart        # GoRouter + redirect d'authentification
│   └── test/api_connection_test.dart
└── backend/
    ├── docker-compose.yml → racine E:\Dépense
    ├── src/
    │   ├── config/            # env.js, db.js (pool pg + withTransaction)
    │   ├── controllers/       # authController.js
    │   ├── services/          # authService.js
    │   ├── repositories/      # userRepository, tokenRepository
    │   ├── routes/            # health.js, auth.js
    │   ├── middlewares/       # authenticate (JWT), errorHandler
    │   ├── validators/        # (validations dans authService — Phase 4/5 : validators/)
    │   ├── utils/             # ApiError, response, money
    │   ├── database/          # init.sql (schéma), migrate.js (npm run migrate)
    │   ├── app.js / server.js
    ├── .env / .env.example
```

---

## 4. Modèle de données PostgreSQL (implémenté)

### `users`
`id UUID PK, display_name, email UNIQUE, password_hash (bcrypt), photo_url, currency (XOF), created_at, updated_at`

### `refresh_tokens`
`id, user_id FK, token_hash UNIQUE (SHA-256), expires_at, revoked_at, created_at`
→ déconnexion = révocation ; réinitialisation de mot de passe = révocation de toutes les sessions.

### `password_reset_tokens`
`id, user_id FK, token_hash UNIQUE, expires_at (1 h), used_at, created_at`

### À venir (Phase 4+)
- `wallets` : `id, user_id FK, name, initial_amount BIGINT, start_date, currency, balance BIGINT, created_at, updated_at`
- `transactions` : `id, wallet_id FK, type ('expense'|'income'), amount BIGINT CHECK > 0, category, description, date, time, payment_method, created_at, updated_at`
- `initial_amount_history`, `budgets`

Invariant du solde : `balance == initial_amount + Σ(income) − Σ(expense)` — muté uniquement dans une transaction SQL atomique (Phase 5).

---

## 5. Routes API (`/api/v1`, réponse : `{ success, data | error{code,message} }`)

### Implémentées (Phases 2-3)
| Méthode | Route | Auth | Description |
|---|---|---|---|
| GET | `/health` | Non | État serveur + PostgreSQL |
| POST | `/auth/register` | Non | Inscription → user + tokens (limiteur 30/15 min) |
| POST | `/auth/login` | Non | Connexion → user + tokens |
| POST | `/auth/refresh` | Non | Rotation du refresh token |
| POST | `/auth/logout` | Non | Révocation du refresh token |
| POST | `/auth/forgot-password` | Non | Émission du token de reset (dev : retourné directement) |
| POST | `/auth/reset-password` | Non | Nouveau mot de passe + révocation des sessions |
| GET/PATCH | `/auth/me` | ✅ JWT | Profil / modification (nom, avatar, devise) |

### À venir
- Phase 4 : `/wallets` (CRUD + initial-amount + historique + recalculate)
- Phase 5 : `/wallets/:id/transactions` (CRUD paginé + atomique)
- Phase 6 : `/wallets/:id/dashboard`, Phase 8 : `/wallets/:id/stats`, Phase 9 : `/budgets`

---

## 6. Gestion des erreurs

Codes : `VALIDATION_ERROR` (400), `UNAUTHORIZED` (401), `FORBIDDEN` (403), `NOT_FOUND` (404), `EMAIL_ALREADY_IN_USE` / `BALANCE_INSUFFICIENT` / `CONFLICT` / `RESET_TOKEN_INVALID` (409), `RATE_LIMITED` (429), `INTERNAL_ERROR` (500).
Côté Flutter : messages FR mappés depuis l'API + messages réseau (DioException).

---

## 7. Sécurité (rev. JWT)

1. Mots de passe **bcrypt** (10 rounds) — jamais de mdp en clair.
2. **Access token JWT** 1 h + **refresh token** 30 j (hashé SHA-256 en base, révocable).
3. Middleware `authenticate` : vérifie JWT + charge le profil à chaque requête protégée.
4. Anti-énumération : `forgot-password` répond identiquement que l'e-mail existe ou non.
5. Reset token à usage unique, expirable (1 h) ; changement de mdp ⇒ toutes sessions révoquées.
6. helmet, cors, express-rate-limit (global 120/min, auth 30/15 min), limite JSON 256 Ko.
7. Secrets dans `.env` (jamais commité) ; `JWT_SECRET` obligatoire en production.

---

## 8. Plan des phases

| Phase | État |
|---|---|
| 1 — Architecture | ✅ |
| 2 — Configuration (Flutter, Node, PostgreSQL Docker) | ✅ |
| 3 — Authentification (inscription, connexion, déconnexion, reset, profil, isolation) | ✅ |
| 4 — Portefeuille & montant initial | à venir |
| 5 — Moteur de transactions (atomique, prioritaire) | à venir |
| 6-12 | à venir |
