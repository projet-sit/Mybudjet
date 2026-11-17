# Changelog

Toutes les évolutions notables de MyBudget sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/), versionnage sémantique (`MAJOR.MINOR.PATCH`) ; le numéro de build Android suit `+N`.

## Sommaire

- [Non publié (Unreleased)](#non-publié-unreleased)
- [1.1.0 (2026-11-15)](#110-2026-11-15) — lecture : APK arm64 signé release
- [1.0.1 (2026-11-14)](#101-2026-11-14)
- [1.0.0 (2026-11-14)](#100-2026-11-14)

## Non publié (Unreleased)

### Ajouté

- **Catégories personnalisées** : création via « Autres » (champ inline + Valider), 2-30 caractères, doublons insensibles casse/accents (y compris avec les défauts : 409 + catégorie sélectionnée automatiquement), max 30 par type, ordre défauts → personnalisées → « Autres », renommage avec propagation aux opérations/budgets, suppression avec réaffectation à « Autres » (budgets liés supprimés avec confirmation), `category_id` sur transactions et budgets, recherche/stats/CSV/budgets compatibles, création hors-ligne avec id UUID client et fusion anti-doublon au retour du réseau.
- **« Réinitialiser tout » = compte comme neuf** : `POST /me/reset` — suppression définitive et atomique (une seule transaction PostgreSQL) de toutes les données du compte ; `data_epoch` incrémenté ; les autres appareils effacent leur cache au prochain contact ; le client purge cache + file d'attente et redirige vers la création du premier portefeuille ; export CSV proposé avant confirmation ; hors-ligne refusé.
- **Alertes de budget réelles** (Android 13+) : notification locale quand une opération fait atteindre 80 % puis 100 % d'un budget, une seule fois par seuil et par période ; l'interrupteur demande `POST_NOTIFICATIONS` à l'activation et coupe tout si elle est refusée.
- Écran « Aide et FAQ » dans l'app (Profil → Aide et FAQ) : 15 questions en accordéon, intégrées hors-ligne, français simple. Test de widget inclus (ouverture/fermeture, aucun overflow à 360×640).
- Inscription/connexion par téléphone (e-mail optionnel), réveil et ré-essai côté client pour la tolérance au cold start Render.
- Reset de mot de passe côté app (réveil serveur puis ré-essai automatique).
- Documentation complète du projet (`docs/`) : architecture, modèle de données, règles métier, hors-ligne, sécurité, déploiement, tests, dépannage, API OpenAPI 3.1, guide utilisateur, dossier de conception.
- Script `docs/build.ps1` pour régénérer diagrammes, site API et PDFs/DOCX.
- Migration SQL 010 (categories + `category_id` + `users.data_epoch`). Backfill idempotent des catégories historiques dans `npm run migrate` (jamais lancée en production depuis ce poste).
- Routeur GoRouter persistant (`refreshListenable`) : une seule pile, pas de redirection perdue en fin d'inscription.
- Outillage : test `npm run test:rollback` vérifiant l'atomicité de `/me/reset` sur une vraie PostgreSQL locale.

### Modifié

- README racine entièrement réécrit (installation, tests, build, déploiement, dépannage).
- `docs/politique-confidentialite.md` aligné sur la réalité (PostgreSQL + JWT, pas de Firebase).
- Routeur GoRouter persistant (`refreshListenable`) : une seule pile, pas de redirection perdue en fin d'inscription.
- « Historique des périodes » retiré de l'UI (non opérationnel avec l'ancien backend).
- Épargne recâblée sur les dépôts/retraits réels (`PATCH /savings` n'existe plus).
- Réinitialisation : l'ancienne logique « archive + annulation 10 s » est remplacée par la réinitialisation complète (« une seule logique de reset »).
- Aide et FAQ : 15 questions, incluant les catégories personnalisées et la réinitialisation complète.

## 1.1.0 (2026-11-15)

### Ajouté

- Périodes archivées + restauration d'une période (si la période courante est vide), annulation 10 s après remise à zéro.
- CI GitHub Actions : build de l'APK arm64 release + publication sur la release `latest` à chaque push sur `main`.
- Rapports de plantage mobiles via `POST /client-errors` (fire-and-forget).
- Tests e2e de bout en bout côté backend (pg-mem).

### Modifié

- Solde déduit de l'épargne dans l'affichage principal (« Reste » = solde − épargne).
- Dates : sérialisation `YYYY-MM-DD` corrigée côté client et serveur.
- Résilience hors-ligne : rollback de l'effet optimiste sur erreur métier, avis d'échec utilisateur, catch-all.
- Export PDF des transactions (remplace le partage CSV dans l'app).

## 1.0.1 (2026-11-14)

### Supprimé

- Google Sign-In retiré (mobile + backend + env associés).

## 1.0.0 (2026-11-14)

### Ajouté

- Import initial : application Flutter, backend Express + PostgreSQL, docker-compose local, installation par APK arm64.
- Authentification JWT maison, inscription par e-mail, portefeuilles, transactions, budgets (alertes 50/80/100 %), épargne (versement/retrait/tout récupérer), reset avec archivage, export, mode hors-ligne avec file d'attente.
- Backend hébergé sur Render, base PostgreSQL Neon, migrations automatiques au démarrage du conteneur.

[Non publié]: https://github.com/projet-sit/Mybudjet/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/projet-sit/Mybudjet/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/projet-sit/Mybudjet/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/projet-sit/Mybudjet/releases/tag/v1.0.0
