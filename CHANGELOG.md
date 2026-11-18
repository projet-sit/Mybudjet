# Changelog

Toutes les évolutions notables de MyBudget sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/), versionnage sémantique (`MAJOR.MINOR.PATCH`) ; le numéro de build Android suit `+N`.

## Sommaire

- [1.2.0 (2026-11-18)](#120-2026-11-18)
- [1.1.0 (2026-11-15)](#110-2026-11-15) - lecture : APK arm64 signé release
- [1.0.1 (2026-11-14)](#101-2026-11-14)
- [1.0.0 (2026-11-14)](#100-2026-11-14)

## 1.3.3 (2026-11-18)

### Modifié

- Message de succès : carré arrondi vert (fond dégradé haut clair -> bas foncé, reflet subtil) + coche blanche tracée progressivement ; carte blanche unie lisible sur tout fond ; animations sobre (easeOutBack).

## 1.3.2 (2026-11-18)

### Corrigé

- « Nous contacter » : numéro du support au format béninois international (+229 01 92 09 87 52) — le bouton WhatsApp ouvre bien la bonne conversation.

## 1.3.1 (2026-11-18)

### Modifié

- Message de succès : cercle plein vert + coche blanche animée, « Effectué » en bas, aucun bouton, aucun détail d'opération ; fermeture automatique (~2,2 s) ou au toucher en dehors.

## 1.3.0 (2026-11-18)

### Ajouté

- **Règle « Budget du mois » côté serveur** : une dépense supérieure au reste du budget est refusée (409 `BUDGET_EXCEEDED`), à la création ET à la modification (l'ancien montant est inclus dans le reste) ; revenus non limités ; comparaison en XOF entiers ; le contrôle existe aussi dans le formulaire (bouton désactivé + message sous le montant). Exception : budget non défini (base ≤ 0) = non limité.
- Success UX : coche verte dans cercle plein vert (V blanc), auto-fermeture 2,2 s, aucun bouton, message décrivant l'opération avec le montant (ex. « Dépense de 2 000 FCFA ajoutée »).
- Aperçu en direct dans « Autres » : « Essence · 2 000 FCFA » pendant la frappe (catégorie créée/réutilisée uniquement à la validation de l'opération ; aucune catégorie partielle si échec/annulation).

### Modifié

- Formulaires d'ajout de dépense et de revenu : suppression du champ facultatif « Dans quoi as-tu dépensé ? » (les anciennes descriptions restent lisibles pour l'historique).
- Sélecteur de devise : uniquement nom + symbole des devises ; plus aucune date de taux affichée (rafraîchissement silencieux).
- Suppression de l'entrée/l'écran « Mes catégories » du Profil (renommage/suppression maintenant uniquement via les formulaires et l'historique).
- Messages de succès affichés uniquement après confirmation réelle du serveur ; opérations hors ligne = feedback « Enregistrée hors-ligne » (pas de faux succès) ; capture d'« Annuler » après suppression via snackbar (restauration).

## 1.2.1 (2026-11-18)

### Modifié

- **Performances** : démarrage parallélisé (dotenv, formatage date locale, devise, préférences lus en même temps — première frame plus rapide d'autant), plugin de notifications locales initialisé en arrière-plan, revalidation au retour au premier plan (solde + badge synchro en parallèle), liste des opérations de l'historique en `ListView.builder` (mise en page paresseuse jours par jours) au lieu d'enfants tous construits à l'avance.

## 1.2.0 (2026-11-18)

### Ajouté

- **Devises au choix** : Franc CFA (XOF, défaut, entiers), Euro (EUR, parité fixe 1 EUR = 655,957 XOF), Dollar américain (USD, taux variable récupéré via open.er-api.com, mis en cache avec date de mise à jour, taux de secours en dur hors ligne). Conversion uniquement à l'affichage et à la saisie (stockage toujours en XOF) ; la date de dernière mise à jour du taux USD est affichée dans le panneau Devise ; confirmation « Les montants seront convertis au taux du jour » au changement ; tous les montants de l'app (opérations, soldes, totaux, budgets, épargne, stats, export PDF) sont reconvertis ; saisie avec décimales pour €/$ (le FCFA garde les entiers et le pavé `000`).
- **Success UX** : boîte de confirmation animée (cercle vert + coche verte dessinée progressivement, rebond + fondu) affichée après chaque opération réellement réussie : création de compte, connexion, enregistrement de portefeuille, ajout/modification d'opération, création de catégorie, budgets, épargne, suppression, restauration, export PDF, mot de passe, suppression de compte/données. Jamais affichée en cas d'échec ; retour haptique ; action optionnelle (ex. « Annuler » après suppression). Composant unique réutilisable `core/widgets/app_feedback.dart`.
- **Zone de danger** : « Supprimer tout » — dialogue « Télécharger mes données en PDF / Supprimer sans télécharger / Annuler », puis confirmation finale (« Cette action est irréversible. Toutes vos opérations, catégories personnalisées et préférences seront supprimées. ») ; efface tout et remet la devise sur FCFA, l'app repart de l'état initial.
- **Politique de confidentialité** dans le Profil (écran défilable, rédaction alignée sur le fonctionnement réel : stockage serveur + cache local, JWT, aucune vente ni partage, vos droits, nous contacter).
- **Nous contacter** (Profil) : ouvre WhatsApp avec un message pré-rempli (numéro jamais affiché, présent uniquement dans `core/constants.dart`).
- Export PDF entièrement réécrit : noir et blanc strict, A4 portrait, en-tête « MYBUDGET — Relevé des opérations », date/heure, devise, période couverte, résumé revenus/dépenses/solde, tableau Date|Type|Catégorie|Description|Montant avec en-tête répété à chaque page, « Page X / Y » en pied, nom de fichier `operations_AAAA-MM-JJ.pdf`, repli hors ligne sur le cache local.
- Recherche opérations : filtre en temps réel (~300 ms) par catégorie, note, montant et date — insensible casse/accents ; « Aucune opération trouvée » si rien ne correspond.
- **Catégories personnalisées** : création via « Autres » (champ inline + Valider), 2-30 caractères, **première lettre en majuscule**, doublons insensibles casse/accents (y compris avec les défauts : 409 + catégorie sélectionnée automatiquement), max 30 par type, ordre défauts → personnalisées → « Autres », renommage avec propagation aux opérations/budgets, suppression avec réaffectation à « Autres » (budgets liés supprimés avec confirmation), `category_id` sur transactions et budgets, recherche/stats/CSV/budgets compatibles, création hors-ligne avec id UUID client et fusion anti-doublon au retour du réseau.
- Écran « Aide et FAQ » dans l'app (Profil → Aide et FAQ) : 15 questions en accordéon, intégrées hors-ligne, français simple. Test de widget inclus (ouverture/fermeture, aucun overflow à 360×640).
- Champ libre « Dans quoi as-tu dépensé ? » / « D'où vient cet argent ? » dans la feuille d'ajout/modification : la note est enregistrée avec l'opération et affichée dans la liste (utile quand aucune catégorie ne convient).
- Photo de profil dans Profil : galerie ou appareil photo (permission Android demandée), stockée localement sur le téléphone, jamais envoyée au serveur ; « Retirer la photo » pour revenir à l'initiale.
- Inscription/connexion par téléphone (e-mail optionnel), réveil et ré-essai côté client pour la tolérance au cold start Render.
- Reset de mot de passe côté app (réveil serveur puis ré-essai automatique).
- Documentation complète du projet (`docs/`) : architecture, modèle de données, règles métier, hors-ligne, sécurité, déploiement, tests, dépannage, API OpenAPI 3.1, guide utilisateur (captures d'écran), dossier de conception.
- Script `docs/build.ps1` pour régénérer diagrammes, site API et PDFs/DOCX.
- Migration SQL 010 (categories + `category_id` + `users.data_epoch`). Backfill idempotent des catégories historiques dans `npm run migrate` (jamais lancée en production depuis ce poste).
- Routeur GoRouter persistant (`refreshListenable`) : une seule pile, pas de redirection perdue en fin d'inscription.
- Outillage : test `npm run test:rollback` vérifiant l'atomicité de `/me/reset` sur une vraie PostgreSQL locale.

### Modifié

- **Recherche opérations (correctif majeur)** : la recherche par catégorie/description/montant ne tournait plus indéfiniment — la cause était une exception de locale non initialisée dans l'isolate de `compute()`, désormais sans aucune dépendance intl (formatage manuel), avec `try/catch/finally` et repli synchrone ; debounce 300 ms.
- **Export PDF** : réécrit (voir « Ajouté ») ; disponible aussi hors ligne (repli sur le cache local) ; utilisé par l'option « Télécharger mes données en PDF » de la Zone de danger.
- **« Réinitialiser tout »** devient **« Supprimer tout »** (Zone de danger du Profil, menu ⋯ de la carte budget) : flux à deux dialogues (PDF optionnel en premier, confirmation finale exacte), plus sans saisie de `REINITIALISER`.
- README racine entièrement réécrit (installation, tests, build, déploiement, dépannage).
- `docs/politique-confidentialite.md` aligné sur la réalité (PostgreSQL + JWT, pas de Firebase).
- « Historique des périodes » retiré de l'UI (non opérationnel avec l'ancien backend).
- Épargne recâblée sur les dépôts/retraits réels (`PATCH /savings` n'existe plus).
- Réinitialisation : l'ancienne logique « archive + annulation 10 s » est remplacée par la réinitialisation complète (« une seule logique de reset »).

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
