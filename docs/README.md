# Documentation MyBudget — index et build

## Sommaire

- [Résumé](#résumé)
- [Index des documents](#index-des-documents)
- [Regénérer les exports (`docs/build.ps1`)](#regénérer-les-exports-docsbuildps1)
- [Scripts npm](#scripts-npm)
- [Conventions](#conventions)

## Résumé

Toute la documentation du projet vit ici. Les fichiers `.md` sont la source ; les exports (`api/index.html`, `diagrams/*.png|svg`, `export/*.pdf|docx`) sont **générés** et régénérables via `docs/build.ps1`. Le dossier `export/` n'est pas versionné, sauf le guide utilisateur.

## Index des documents

| Document | Contenu |
|---|---|
| [`../README.md`](../README.md) | Présentation, installation, lancement, build, dépannage |
| [`architecture.md`](architecture.md) | Couches mobile/backend, Riverpod, go_router, flux « ajouter une dépense » |
| [`modele-de-donnees.md`](modele-de-donnees.md) | Schéma PostgreSQL réel (tables, index, triggers, snapshots) |
| [`regles-metier.md`](regles-metier.md) | Solde, Reste, épargne, budgets 50/80/100 %, périodes, dates, devises (XOF/EUR/USD) |
| [`hors-ligne-et-synchronisation.md`](hors-ligne-et-synchronisation.md) | Persistance locale, outbox, indicateur de synchro, règles anti-erreur |
| [`detection-notifications.md`](detection-notifications.md) | Détection par notifications : **non implémentée** (état réel) |
| [`securite-et-confidentialite.md`](securite-et-confidentialite.md) | Auth, isolation, données collectées, suppression de compte |
| [`politique-confidentialite.md`](politique-confidentialite.md) | Texte public (brouillon à faire valider) |
| [`DEPLOIEMENT.md`](DEPLOIEMENT.md) | Déploiement Render + Neon (Procédure complète, health check, veille, migration, rollback) |
| [`tests.md`](tests.md) | Tests mobile/backend, e2e pg-mem, recette manuelle |
| [`depannage.md`](depannage.md) | Erreurs fréquentes et correctifs |
| [`api/openapi.yaml`](api/openapi.yaml) | Référence complète de l'API (OpenAPI 3.1) |
| [`api/index.html`](api/index.html) | Référence API lisible (générée, statique — pas de Swagger UI exposée) |
| [`dossier-de-conception.md`](dossier-de-conception.md) | Dossier de conception (source Pandoc/md-to-pdf) |
| [`guide/guide-utilisateur.md`](guide/guide-utilisateur.md) + [`captures-a-faire.md`](guide/captures-a-faire.md) | Guide utilisateur + captures attendues |
| [`export/guide-utilisateur.pdf`](export/guide-utilisateur.pdf) | Version PDF du guide (versionnée) |
| [`TESTS_HORS_LIGNE.md`](TESTS_HORS_LIGNE.md), [`PHASE1_ARCHITECTURE.md`](PHASE1_ARCHITECTURE.md) | Documents d'origine (conservés) |
| [`firestore.rules`](firestore.rules) | **Obsolète** — le projet n'utilise pas Firestore. Ne pas réutiliser. |

## Regénérer les exports (`docs/build.ps1`)

```powershell
.\docs\build.ps1                    # tout
.\docs\build.ps1 -SkipDiagrams      # sans les diagrammes
.\docs\build.ps1 -SkipApi           # sans l'OpenAPI
.\docs\build.ps1 -SkipExports       # sans Word/PDF
```

Prérequis : Node 20+, `npm`, `npx`, **Pandoc**, Google Chrome (détecté automatiquement pour le rendu PDF/mmdc).

Le script est **idempotent** : il régénère toujours les mêmes artefacts. Messages `✔`/`✘` par étape ; arrêt non zéro si une étape échoue.

## Scripts npm

Depuis la racine :

```powershell
npm run docs:build         # .\docs\build.ps1
npm run docs:lint          # redocly lint (0 erreur exigée)
npm run docs:api           # régénère api/index.html
npm run docs:check-links   # liens internes (markdown-link-check)
```

Depuis `docs/` : `npm run lint:api`, `npm run build:api`, `npm run export:pdf`, `npm run check:links`.

## Conventions

- Chaque document commence par un sommaire et un résumé de 3 lignes.
- Les diagrammes sont écrits en Mermaid **dans** les `.md` ; leur source de vérité pour les exports est `diagrams/*.mmd` (garder les deux cohérents).
- Secrets : jamais. Les exemples de config utilisent des valeurs factices marquées.
- Ce qui n'existe pas encore est marqué « À confirmer » ou « non implémenté » — jamais présenté comme disponible.
- `[À REMPLIR]` = information manquante à compléter par le mainteneur (voir le rapport final).
