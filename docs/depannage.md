# Dépannage — erreurs fréquentes

## Sommaire

- [Résumé](#résumé)
- [Build Gradle / Android](#build-gradle--android)
- [Flutter](#flutter)
- [Backend / base de données](#backend--base-de-données)
- [Application sur le téléphone](#application-sur-le-téléphone)
- [Render (production)](#render-production)
- [Documentation](#documentation)

## Résumé

La majorité des problèmes viennent du `.env` mobile (mauvaise URL), du service Render endormi, ou du cache Flutter corrompu. La fiche ci-dessous liste les cas réels rencontrés sur ce projet, avec correctifs.

## Build Gradle / Android

| Symptôme | Cause | Correctif |
|---|---|---|
| `Gradle task assembleDebug failed` + `SDK location not found` | SDK absent | Installer Android Studio → SDK Manager ; créer `android/local.properties` (généré auto) |
| `Namespace not specified` / `package=` conflit | cache Gradle / AGP | `cd android && ./gradlew clean` ; `flutter clean && flutter pub get` |
| `keystore password was incorrect` | `key.properties` erroné | Restaurer la sauvegarde `keystore-backup/key.properties` ; sinon **impossible de signer en release** |
| `duplicate classes` / `multidex` | minify + deps | Vérifier `isMinifyEnabled=true` et `proguard-rules.pro` ; `flutter clean` puis rebuild |
| `Installed build tools revision … is corrupted` | SDK corrompu | SDK Manager → cocher/décocher Build-Tools 34/35 ; ou supprimer le dossier `build-tools/<version>` |
| APK installée mais écran blanc au lancement | `.env` absent dans l'APK | `mobile/.env` est bien déclaré en asset ; rebuild |
| `usesCleartextTraffic` rejeté par Play | politique | Le flavor `direct` est le seul distribué actuellement |

## Flutter

```powershell
flutter clean ; flutter pub get ; flutter analyze
# Si .dart_tool est corrompu :
Remove-Item -Recurse -Force .dart_tool ; flutter pub get
```

- **`flutter analyze` → unused import / lints** : corriger ou ajouter `// ignore:` justifié en commentaire.
- **`pub get` qui bloque sur la version d'un SDK** : SDK Dart minimum = `^3.12.0` ; vérifier `flutter --version` et mettre Flutter à jour.
- **Tests qui échouent avec `A Timer is still pending`** : vérifier l'utilisation de `pumpAndSettle` avec les timers récurrents.
- **Overflow « RenderFlex overflowed »** : tester à 360×640 (voir `onboarding_test.dart` et `help_test.dart`) ; utiliser `Expanded`, `Flexible`, `FittedBox` avec parcimonie, jamais de hauteur fixe.

## Backend / base de données

| Symptôme | Cause | Correctif |
|---|---|---|
| `npm run migrate` → `ECONNREFUSED 5434` | docker-compose non démarré | `docker compose up -d` puis réessayer |
| `role "mybudget" does not exist` | volume persistant d'une autre config | `docker compose down -v` **(efface les données locales !)** puis `up -d` |
| `JWT_SECRET manquant` au démarrage prod | variable absente | la renseigner dans `backend/.env` ou chez Render (obligatoire en production) |
| `relation "…" does not exist` | migrations non jouées | `npm run migrate` |
| `Port 3000 already in use` | ancien `node src/server.js` orphelin | tuer le processus (PowerShell : `Get-NetTCPConnection -LocalPort 3000`) |
| `duplicate key value violates unique constraint "budgets_wallet_id_category_key"` | budget déjà existant | 409 côté API (normal) — l'UI propose édition, pas création en double |
| Erreur `BALANCE_INSUFFICIENT` à la saisie | le **Reste** (solde − épargne) est insuffisant | retirer de l'épargne d'abord ou réduire le montant |

## Application sur le téléphone

| Symptôme | Cause | Correctif |
|---|---|---|
| Écran « Hors ligne » permanent alors que le réseau marche | mauvaise URL API (ex. ancien LAN 192.168.100.26) ou serveur endormi | pointer `mobile/.env` vers l'URL Render, rebuild ; attendre le réveil (<60 s) |
| App très lente au premier démarrage | cold start Render (plan gratuit) | normal ; l'app le réveille discrètement |
| « Application non installée » | conflit de signature avec l'ancienne APK | désinstaller l'ancienne, puis installer |
| Crash au lancement sur Android 13+ | permissions restreintes (rare) | MyBudget n'utilise **pas** de service d'écoute de notifications ; vérifier la version de l'APK et les logs via `POST /client-errors` |
| Catégorie personnalisée invisible après synchro | la fusion exige une récupération complète (déconnexion/reconnexion ou redémarrage) | rouvrir l'app ; la réconciliation se fait au prochain démarrage |
| Notifications de budget absentes | interrupteur coupé ou permission Android refusée | Profil → Alertes de budget → activer et autoriser les notifications |
| « Connexion requise pour réinitialiser » | hors-ligne au moment du reset | se connecter à Internet et réessayer |
| Dépenses qui n'apparaissent pas après saisie hors-ligne | outbox pas encore rejouée | rouvrir le réseau, rouvrir l'écran ; vérifier le badge de synchro |
| Mot de passe oublié n'arrive pas | aucun fournisseur e-mail n'est intégré ; en dev le jeton est logué côté serveur | contact support [À REMPLIR] |

## Render (production)

- **Déploiement échoue au build** : vérifier les logs Render (Dockerfile = `npm ci --omit=dev`) ; souvent une dépendance absente — ajouter à `dependencies` (pas `devDependencies`).
- **Health check rouge** : `/api/v1/health` doit répondre 200 ; vérifier `DATABASE_URL` (SSL `sslmode=require`) et que la migration n'échoue pas (logs au démarrage).
- **Service qui dort** : cron externe (cron-job.org) qui ping le health check toutes les 5–10 min, ou plan payant.
- **500 en cascade après un deploy** : rollback (bouton « Rollback deploy » dans Render) puis analyse des logs (`requestId`).

## Documentation

```powershell
# Vérifier les liens internes
npm --prefix docs run check:links

# Vérifier l'OpenAPI
npm --prefix docs run lint:api

# Régénérer les exports
.\docs\build.ps1
```

- **Lien cassé** : chemins relatifs depuis le fichier `.md` concerné ; les guides utilisent `docs/…` depuis la racine.
- **Redocly échoue sur les codes d'erreur** : comparer avec les codes réels émis par `errorHandler` (`RATE_LIMITED`, `NOT_FOUND`, `BALANCE_INSUFFICIENT`, `BUDGET_EXISTS`, `SAVINGS_LOCKED`, `UNDO_EXPIRED`, `RESTORE_BLOCKED`, …).
- **PDF/Word « vide »** : Pandoc exige que le Markdown commence par un titre ; les `---` (front matter) sont proscrits pour le Word.
