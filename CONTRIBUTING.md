# Contribuer à MyBudget

Merci de ta contribution ! Ce guide explique comment travailler sur le projet sans casser l'existant.

## Sommaire

- [Avant de commencer](#avant-de-commencer)
- [Environnement de développement](#environnement-de-développement)
- [Règles d'or du code](#règles-dor-du-code)
- [Flux de travail](#flux-de-travail)
- [Tests et qualité](#tests-et-qualité)
- [Documentation](#documentation)
- [Sécurité](#sécurité)

**Résumé en 3 lignes** : installe l'environnement (`flutter pub get`, `npm install`), garde `flutter analyze` et `flutter test` propres, et respecte les règles d'or (entiers FCFA, jamais de secret, jamais de chiffre inventé dans l'UI). Toute fonctionnalité serveur passe par une migration SQL et des tests e2e. Les PR doivent être petites et ciblées.

## Avant de commencer

1. Lis le [README](README.md) et [`docs/architecture.md`](docs/architecture.md).
2. Choisis une branche descriptive : `feat/<sujet>`, `fix/<sujet>`, `docs/<sujet>`.
3. Ne développe pas sur `main` directement.

## Environnement de développement

```powershell
docker compose up -d                       # PostgreSQL local (port 5434)
cd backend; npm install; npm run migrate; npm run dev
cd ..\mobile; flutter pub get
```

## Règles d'or du code

- **Montants** : entiers FCFA uniquement. Jamais de flottant, jamais de `double` pour un montant. La base impose `CHECK`.
- **Pas de données fictives** : tout solde affiché provient du serveur ou du cache des dernières données réelles.
- **Dates** : `YYYY-MM-DD` côté échange/stockage, affichage `JJ/MM/AAAA` en heure locale.
- **Hors-ligne** : toute écriture passe par l'outbox (`lib/services/outbox.dart`) ou par un appel serveur déjà optimisé ; jamais d'écriture réseau brute depuis un widget.
- **Erreurs** : une erreur serveur n'est jamais présentée comme « Hors ligne ». Réseau/timeout = silencieux ou bannière neutre ; erreur métier = message français clair.
- **Secrets** : rien dans git (`.env`, `key.properties`, `*.jks`). Exemples factices marqués comme tels dans les docs.
- **UI** : français simple, pas de jargon technique visible par l'utilisateur, pas de mention de version/réseau dans les écrans.

## Flux de travail

1. `git checkout -b feat/mon-sujet`
2. Implémente + tests (backend : `npm run test:e2e` ; mobile : `flutter test`)
3. `flutter analyze` sans issue
4. Message de commit clair : `type: résumé` (ex. `fix: date serialization (YYYY-MM-DD)`)
5. `git push` → ouvre une PR vers `main`
6. La CI build l'APK arm64 et publie une préversion si les secrets sont en place

## Tests et qualité

| Zone | Commande | Exigence |
|---|---|---|
| Mobile | `flutter analyze` | 0 issue |
| Mobile | `flutter test` | tous verts (overflow 360×640 inclus) |
| Backend unit | `npm test` | tous verts |
| Backend e2e | `npm run test:e2e` | tous verts (pg-mem, sans Docker) |
| API | `npm --prefix docs run lint:api` | 0 erreur Redocly |
| Docs | `npm --prefix docs run check:links` | 0 lien cassé |

Toute migration SQL se fait dans `backend/src/database/migrations/` (numéro croissant, jamais de modification d'un fichier déjà migré).

## Documentation

- Toute nouvelle route Express doit apparaître dans [`docs/api/openapi.yaml`](docs/api/openapi.yaml) (+ régénérer `docs/api/index.html` via `docs/build.ps1`).
- Toute nouvelle règle métier doit être documentée dans [`docs/regles-metier.md`](docs/regles-metier.md).
- Les diagrammes Mermaid vivent dans les `.md` ; régénère les PNG/SVG avec `docs/build.ps1`.
- Documente ce qui existe, pas ce qui est prévu. Dans le doute : « À confirmer ».

## Sécurité

- N'ajoute jamais de log d'identifiants ou de jetons.
- Toute route protégée passe par `authenticate` (JWT) ou `verifyIdToken`.
- Les suppressions définitives exigent une confirmation explicite côté UI.
- En cas de faille : voir [`docs/securite-et-confidentialite.md`](docs/securite-et-confidentialite.md) et ne pas ouvrir d'issue publique.
