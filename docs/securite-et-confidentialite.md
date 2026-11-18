# Sécurité et confidentialité

## Sommaire

- [Résumé](#résumé)
- [Authentification et sessions](#authentification-et-sessions)
- [Contrôles côté backend](#contrôles-côté-backend)
- [Règles d'accès aux données](#règles-daccès-aux-données)
- [Données collectées](#données-collectées)
- [Traitement local sur l'appareil](#traitement-local-sur-lappareil)
- [Suppression du compte](#suppression-du-compte)
- [Sécurité des échanges](#sécurité-des-échanges)
- [Fichiers à ne JAMAIS committer](#fichiers-à-ne-jamais-committer)
- [État des anciens artefacts (Firestore, Ciel)](#état-des-anciens-artefacts-firestore-ciel)

## Résumé

Mots de passe hashés bcrypt, JWT access 1 h + refresh 30 j hashé SHA-256 et roté à chaque usage ; isolation stricte par utilisateur côté serveur ; suppression de compte définitive possible dans l'app. Pas de Firebase, pas de SDK de tracking, pas de publicité : les données ne servent qu'à faire fonctionner l'app.

## Authentification et sessions

- Inscription par **téléphone** (`^\+[1-9]\d{7,14}$`) + mot de passe ; e-mail optionnel (rétrocompatibilité).
- Mot de passe : bcrypt, coût par défaut de `bcryptjs` ; min 6 caractères.
- Access JWT : 1 h (`JWT_ACCESS_EXPIRES_IN`), refresh : 30 j (`JWT_REFRESH_EXPIRES_IN`), stocké hashé SHA-256, rotation à chaque refresh, révocation possible.
- Reset mot de passe : jeton à usage unique, 1 h, hashé SHA-256 ; **tous** les refresh tokens sont révoqués après changement.
- Aucune énumération possible : forgot-password renvoie la même réponse que l'e-mail existe ou non.
- Après 401 côté client : tentative de refresh unique ; sinon session effacée.

## Contrôles côté backend

- `helmet()` activé ; `express.json({ limit: '256kb' })` ; CORS configurable (`CORS_ORIGIN`, aujourd'hui `*` en prod — **à restreindre**).
- Rate limiting : global 120/min/IP ; `/auth/*` 30/15 min ; `/client-errors` 20/min. Réponse 429 `RATE_LIMITED`.
- `trust proxy: 1` (Render est un proxy).
- Erreurs 5xx : message générique en production, stack complète seulement dans les logs (`requestId`).
- Requêtes : `requestLogger` JSON (méthode, chemin, statut, durée, `requestId`).
- Plantages mobiles : `POST /client-errors` anonyme, corps tronqué (≤300/1500/80 caractères), aucun PII requis.

## Règles d'accès aux données

- Toute route `/api/v1/wallets/*` et `/auth/me` exige le JWT ; le `user_id` vient **uniquement** du token.
- Les transactions vérifient l'appartenance du portefeuille avant toute lecture/écriture (requête jointe).
- Budgets : unicité `(wallet_id, category)`.
- Isolation testée : A ne peut pas lire/écrire les données de B.
- Identifiants UUID validés par regex avant usage SQL ; requêtes paramétrées (`pg`) partout.

## Données collectées

| Donnée | Requise | Finalité |
|---|---|---|
| Téléphone (ou e-mail historique) | Oui | Connexion, reset de mot de passe |
| Nom d'affichage | Oui | Personnalisation |
| Devise (préférence d'affichage : XOF, EUR ou USD) | Non | Mise en forme des montants (conversion à l'affichage, stockage toujours en XOF) |
| Portefeuilles, transactions, budgets, périodes, objectifs, épargne | Oui | Fonctionnement de l'app |
| Catégories personnalisées (nom de catégorie choisi par l'utilisateur) | Oui (si créées) | Opérations, budgets, recherche, statistiques |
| Rapports de plantage (message, stack tronquée, écran, version) | Optionnel | Stabilité |

**Non collectés** : localisation, contacts, photos, micro, contenu des SMS/notifications, identifiants publicitaires.

## Traitement local sur l'appareil

- Cache « dernières données réelles » en SharedPreferences (solde, tableau de bord, budgets, transactions, session).
- File d'attente hors-ligne (`outbox_ops`).
- Aucune donnée n'est envoyée en clair ; aucun tracker publicitaire.
- À la déconnexion, la session est effacée du téléphone ; les données restent sur le serveur (réinstallables par reconnexion).

## Suppression et » Supprimer tout«

- Profil → Zone de danger → **Supprimer tout** : irréversible, en deux dialogues (télécharger en PDF / supprimer sans télécharger, puis confirmation finale) ; efface opérations, catégories personnalisées et préférences (devise remise sur XOF) sans supprimer le compte. Autres appareils : `data_epoch` incrémenté → cache local et file d'attente effacés au prochain contact.
- Profil → « Supprimer mes données » : irréversible, confirmation forte ; supprime en cascade le compte et toutes les données métier.
- Recommandation : exporter le PDF avant l'un ou l'autre.

## Notifications locales

- Seules les alertes de budget sont notifiées, via le système de notification Android — **jamais** via le contenu d'autres applications (MyBudget ne lit aucune notification/SMS de tiers).
- Une seule alerte par seuil (80 % / 100 %) et par période, désactivable d'un interrupteur.
- À la désinstallation, les notifications disparaissent avec l'app.

## Sécurité des échanges

- HTTPS obligatoire en production (Render fournit TLS). `usesCleartextTraffic="true"` dans le manifest Android = tolérance dev LAN uniquement ; toutes les URLs documentées sont HTTPS.
- Certificat TLS de Render géré par la plateforme (certificats managés).

## Fichiers à ne JAMAIS committer

| Fichier | Contenu |
|---|---|
| `mobile/.env`, `backend/.env*` | URLs, secrets |
| `mobile/android/key.properties` | mot de passe du keystore |
| `mobile/android/app/mybudget.jks` | clé de signature release |
| `keystore-backup/` | sauvegarde de la clé |
| `.neon`, `.env.local`, `.git-backups/` | jetons d'infra |

Ces fichiers sont listés dans `.gitignore`. Un audit périodique : `git ls-files | grep -E "\.env|\.jks|\.properties"` doit être vide.

## État des anciens artefacts (Firestore, Ciel)

- **`docs/firestore.rules`** : obsolète, le projet n'utilise pas Firestore. Ne pas s'en inspirer pour de nouveaux développements ; le fichier peut être supprimé.
- **Routes « Ciel »** (`/stats/monthly`, `/export/excel|csv`, `/alerts/check`, montées sur `/` et `/api/v1`) : héritage « ciel.app ». Requêtes SQL sur colonnes inexistantes, `firebase-admin` non installé, résultats vides ; `verifyIdToken` accepte tout token si `NODE_ENV != production`. **À désactiver en production réelle ou à supprimer.** Voir `docs/api/openapi.yaml` (`x-obsolete`) et `docs/depannage.md`.
- **`docs/maquette/`** : maquettes HTML/PNG historiques, non reliées au code.
- **`docs/PHASE1_ARCHITECTURE.md`** : document de phase 1 ; noter la mention assumée « Firebase a été abandonné au profit de PostgreSQL/JWT ».
