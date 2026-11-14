# MyBudget — règles et commandes projet

## Structure du projet

- **Mobile Flutter** : `E:\Mybudjet\mobile` (chemin ASCII — build directement ici, plus de copie `C:\temp\mybudget_ascii`).
- **Backend Node/Express + PostgreSQL** : `E:\Mybudjet\backend`.
- L'API est joignable depuis le téléphone uniquement en **même Wi-Fi** :
  `API_BASE_URL=http://192.168.100.26:3000/api/v1` (cf. `.env`).
  Le backend doit tourner sur le PC (mêmes réseau) pour que l'app s'y connecte ;
  sinon l'app affiche le bandeau « Hors ligne » avec les dernières données connues.
- Comportement hors-ligne : session, portefeuille et tableau de bord sont mis en
  cache en local (SharedPreferences) et revalidés en arrière-plan à l'ouverture.
- Onboarding (3 écrans, première ouverture uniquement, AVANT la connexion) :
  indicateur `onboarding_seen` dans SharedPreferences, lu avant `runApp`.
  Jamais ré-affiché après « Passer », « Commencer » ou « J'ai déjà un compte »,
  y compris après déconnexion. Route `/onboarding` via go_router.
- Qualité : `flutter analyze` propre exigé ; `flutter test` obligatoire
  (inclut les tests de redirection, du flux Passer→Inscription et de l'overflow 360×640).

## Partage avec des amis (APK publics)

- **Clé release** : `mobile/android/app/mybudget.jks` + `mobile/android/key.properties`
  (ignorés par git). Sauvegarde dans `E:\Mybudjet\keystore-backup\`. **Ne jamais perdre cette clé**
  — sans elle, les amis ne pourront plus mettre l'app à jour (uninstall/reinstall obligatoire).
- **APK arm64 signée release** : `E:\Mybudjet\app-arm64-v8a-direct-release-obfuscated.apk`
  (copie identique dans `E:\Mybudjet\flutter-apk\`). Installable en sideload
  (sources inconnues à autoriser). Fichiers `debug-symbols\` conservés pour la déobfuscation.
- **Backend public** : le backend Node est hébergé sur Render à l'URL `https://mybudjet-rslh.onrender.com/api/v1`.
  L'app mobile est buildée avec cette URL (`mobile/.env`). Le service est lié au repo GitHub projet-sit/Mybudjet ;
  chaque push sur `main` redéploie automatiquement le backend.
- **Déploiement définitif fait** : repo git `E:\Mybudjet` déjà poussé et le service Render `srv-dbs11cjbc2fs73a9c4d0` est `live`. Les amis installent l'APK mise à jour (`E:\Mybudjet\app-arm64-v8a-direct-release-obfuscated.apk`).
- `mobile/.env.lan.bak` = `.env` d'origine (adresse LAN `192.168.100.26:3000`, pour un usage sur le réseau domestique).
- JWT_SECRET backend : rotation aléatoire effectuée (les sessions existantes ont été invalidées).

## Format APK à produire à chaque fois (arm64 léger)

Build complet (arm64 léger, sans infos de debug) :

```powershell
cd E:\Mybudjet\mobile
flutter pub get
flutter analyze
flutter build apk --release --flavor direct --split-per-abi `
  --obfuscate --split-debug-info=build/debug-info

# Livré : APK arm64 uniquement (~19,7 Mo)
#   build\app\outputs\flutter-apk\app-arm64-v8a-direct-release.apk
#   + build\debug-info\*.symbols (à garder pour déobfusquer les stacktraces)
```

Équivalence du build précédent : minify + shrinkResources actifs dans android/app/build.gradle.kts.
Pas encore de key.properties → l'APK release est signée avec la clé debug (installe à côté via fichier/ADB, pas pour le Play Store).
