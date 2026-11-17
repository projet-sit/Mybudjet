# Déploiement (Render + Neon)

## Sommaire

- [Résumé](#résumé)
- [Architecture de production](#architecture-de-production)
- [Le contrat Render (`render.yaml`)](#le-contrat-render-renderyaml)
- [Variables d'environnement](#variables-denvironnement)
- [Déploiement depuis zéro (étape par étape)](#déploiement-depuis-zéro-étape-par-étape)
- [Health check](#health-check)
- [Plan gratuit et mise en veille](#plan-gratuit-et-mise-en-veille)
- [Migrations au démarrage](#migrations-au-démarrage)
- [Logs et monitoring](#logs-et-monitoring)
- [Retour arrière](#retour-arrière)
- [Alternatives et raccourcis APK](#alternatives-et-raccourcis-apk)
- [Points d'attention (vérité terrain)](#points-dattention-vérité-terrain)

## Résumé

Le backend est un conteneur Docker déployé sur **Render** (plan gratuit, région frankfurt) depuis la racine du repo via `render.yaml`. La base **Neon** (PostgreSQL gratuit permanent) est connectée via `DATABASE_URL` (`sslmode=require`). Chaque push sur `main` redéploie ; le service s'endort après ~15 min d'inactivité et se réveille au premier appel. **Objectif** : API accessible depuis n'importe quel réseau, sans carte bancaire.

## Architecture de production

```
Téléphone ──HTTPS──▶ mybudjet-rslh.onrender.com (Render, Docker node:20-alpine)
                         │  node src/database/migrate.js && node src/server.js
                         └─▶ Neon PostgreSQL (DATABASE_URL, sslmode=require)
```

Objectif : l'API accessible depuis n'importe quel réseau, persistance dans une base Postgres gratuite, sans carte bancaire.

## Le contrat Render (`render.yaml`)

```yaml
services:
  - type: web
    name: mybudget-api
    runtime: docker
    dockerfilePath: ./backend/Dockerfile
    dockerContext: ./backend
    plan: free
    region: frankfurt
    healthCheckPath: /api/v1/health
    envVars: NODE_ENV=production, PORT=10000, DATABASE_URL (sync:false), JWT_SECRET (sync:false), CORS_ORIGIN=*
```

Le `Dockerfile` : `node:20-alpine`, `npm ci --omit=dev`, `CMD: node src/database/migrate.js && node src/server.js` — la base est **migrée automatiquement** à chaque démarrage.

## Variables d'environnement

À renseigner dans l'onglet **Environment** du service Render (ne jamais les committer) :

| Nom | Exemple factice (à remplacer) | Obligatoire |
|---|---|---|
| `NODE_ENV` | `production` | oui |
| `PORT` | `10000` | oui |
| `DATABASE_URL` | `postgresql://user:pass@ep-xxx-pooler.eu-central-1.aws.neon.tech/neondb?sslmode=require` | oui |
| `JWT_SECRET` | `exemple-factice-a-remplacer-000` | oui (sinon refus de démarrer) |
| `CORS_ORIGIN` | `*` (ou liste CSV de domaines) | oui |
| `JWT_ACCESS_EXPIRES_IN` | `1h` | non (défaut) |
| `JWT_REFRESH_EXPIRES_IN` | `30d` | non (défaut) |
| `RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX` | `60000` / `120` | non (défauts) |

Secrets factices uniquement ci-dessus — les vraies valeurs vivent chez Render et Neon.

## Déploiement depuis zéro (étape par étape)

### Étape 1 — Repository

Le projet est déjà poussé sur `https://github.com/projet-sit/Mybudjet` (branche `main`, contient `mobile/` et `backend/`).

### Étape 2 — Base Neon (PostgreSQL gratuit permanent)

1. Crée un compte sur https://neon.tech (e-mail suffit) ;
2. **New Project** → `mybudget` → Postgres par défaut ;
3. Copie la **connection string** affichée, format :
   `postgresql://user:pass@ep-xxx-pooler.eu-central-1.aws.neon.tech/neondb?sslmode=require`
   (l'option `sslmode=require` est importante — c'est elle qui active le SSL côté app) ;
4. Garde-la précieusement : c'est `DATABASE_URL` pour Render.

### Étape 3 — Render (service web gratuit)

1. Crée un compte sur https://render.com (connexion GitHub en un clic) ;
2. **New +** → **Blueprint** → connecter le repo `projet-sit/Mybudjet` (Render lit automatiquement `render.yaml` à la racine) ;
3. Render détecte `Dockerfile` dans `./backend` ;
4. **Plan Free**, **Region** : `frankfurt`, **Health Check Path** : `/api/v1/health` ;
5. Variables d'environnement (onglet Environment) :
   - `JWT_SECRET` → génère une valeur : dans PowerShell `[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')`
   - `DATABASE_URL` → la connection string Neon copiée plus haut
   - `NODE_ENV` → `production`
6. **Create** → build + déploiement automatique ; la base est migrée automatiquement au démarrage ;
7. Vérifie : `https://mybudjet-rslh.onrender.com/api/v1/health` → `{"success":true,...}`.

### Étape 4 — Rebuild de l'APK avec la nouvelle URL

Depuis ton poste, modifie `mobile/.env` :

```
API_BASE_URL=https://mybudjet-rslh.onrender.com/api/v1
```

puis :

```powershell
cd E:\Mybudjet\mobile
flutter build apk --release --flavor direct --split-per-abi `
  --obfuscate --split-debug-info=build/debug-info
```

APK livré dans `build\app\outputs\flutter-apk\app-arm64-v8a-direct-release.apk` (+ `flutter-apk\`, release GitHub `latest` via la CI).

## Health check

`GET /api/v1/health` — public, sans auth :

```json
{ "success": true, "data": { "service": "MYBUDGET API", "version": "1.1.0", "status": "ok", "nodeEnv": "production", "database": "connecté", "time": "…" } }
```

Render interroge ce chemin pour déterminer « live » vs « failed deploy ».

## Plan gratuit et mise en veille

- **Sommeil après ~15 min** d'inactivité ; premier appel = 30–60 s de cold start. L'app appelle `/health` discrètement au démarrage et au retour au premier plan.
- Pour ne pas dormir : plan payant, ou cron externe (ex. cron-job.org) qui ping `/api/v1/health` toutes les 5–10 min.
- La mise en veille ne traverse pas : les données Neon sont persistantes.
- Signaux d'alerte : erreurs 5xx répétées dans les logs, `database` ≠ `connecté`.

## Migrations au démarrage

`migrate.js` lit `schema_migrations` et applique les fichiers manquants (001→010) dans l'ordre. Ne jamais modifier une migration déjà appliquée ; ajouter 011+ si besoin. **Migration 010 (catégories personnalisées)** : additive et sans perte — création de `categories` + colonnes `category_id` + `users.data_epoch`, rattachement des catégories historiques (`backfill_categories.js`, idempotent, exécuté automatiquement par `migrate`). **Ne jamais la lancer manuellement contre la production depuis un poste de dev** : elle s'applique automatiquement au prochain déploiement Render (`node src/database/migrate.js && node src/server.js`), ou sur demande explicite du mainteneur.

Les migrations sont jouées avant le serveur : en cas d'échec, le deploy échoue au démarrage (visible dans les logs Render).

## Logs et monitoring

- Chaque requête : ligne JSON (`requestId`, méthode, chemin, statut, durée).
- 5xx : stack complète dans les logs (jamais envoyée au client).
- Plantages mobiles : `POST /client-errors` → logs warn avec écran et version.
- Pas de Sentry ; pour aller plus loin, brancher `ErrorReporter` sur un service externe (une ligne).

## Retour arrière

- **Render** : bouton « Rollback deploy » sur un deploy précédent en un clic.
- **Base** : les migrations ne sont pas réversibles automatiquement ; garder une sauvegarde (Neon fournit des branches/snapshots).
- **App** : republier l'APK arm64 sur GitHub Releases (`latest`).

## Alternatives et raccourcis APK

**Déployer l'image Docker ailleurs (sans GitHub)** : SnapDeploy (conteneurs gratuits, sleep après 15 min) ou Railway (crédit d'essai puis limites mensuelles) : identique dans l'esprit, image Docker en entrée. GitHub + Render reste le chemin le plus simple.

**Installer/maj l'APK par USB (PowerShell + adb)** :

```powershell
adb devices
adb install -r "E:\Mybudjet\app-arm64-v8a-direct-release-obfuscated.apk"
# Réafficher l'onboarding :
adb shell pm clear com.mybudget.mybudget
```

## Points d'attention (vérité terrain)

- Le service gratuit Render **dort après 15 min sans trafic** ; le premier accès peut prendre ~1 minute.
- **Permanence garantie uniquement si** : Render tourne (quota gratuit ~750 h/mois) **et** Neon garde la base (gratuit permanent ; contrairement au Postgres gratuit de Render, supprimé après 30 jours).
- Les comptes des utilisateurs sont uniques (téléphone + mot de passe).
- Pas de Google Sign-In : l'app utilise le téléphone + mot de passe uniquement.
- Variables critiques : sans `JWT_SECRET`, le serveur refuse de démarrer en production ; sans `DATABASE_URL` (ou `sslmode=require`), la connexion Neon échoue.
