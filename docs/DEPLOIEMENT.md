# Déploiement — MYBUDGET (Render + Neon, 100% gratuit)

Objectif : l'API accessible depuis n'importe quel réseau, persistance dans une base Postgres gratuite, sans carte bancaire.

Architecture : **Render** (héberge le backend Node dans Docker, gratuit, met en veille après 15 min d'inactivité) + **Neon** (PostgreSQL gratuit permanent, 1 Go, `sslmode=require`).

## Étape 1 — Compte GitHub (si tu n'en as pas)

Crée un compte sur https://github.com (inscription gratuite, sans carte) puis un repo **vide** `mybudget-api` (Public ou Private au choix).

## Étape 2 — Pousser le backend

```powershell
cd E:\Mybudjet\backend
git init
git add .
git commit -m "MYBUDGET API — backend"
git branch -M main
git remote add origin https://github.com/TON_COMPTE/mybudget-api.git
git push -u origin main
```

Le `.gitignore` (fourni) exclut `node_modules/`, `.env` et les logs — les secrets ne partent pas.

## Étape 3 — Base Neon (PostgreSQL gratuit permanent)

1. Crée un compte sur https://neon.tech (e-mail suffit) ;
2. **New Project** → `mybudget` → Postgres par défaut (pas besoin de choisir de version) ;
3. Copie la **connection string** affichée, format :
   `postgresql://user:pass@ep-xxx-pooler.eu-central-1.aws.neon.tech/neondb?sslmode=require`
   (l'option `sslmode=require` est importante — c'est elle qui active le SSL côté app) ;
4. Garde-la précieusement : c'est `DATABASE_URL` pour Render.

## Étape 4 — Render (service web gratuit)

1. Crée un compte sur https://render.com (connexion GitHub une clic) ;
2. **New +** → **Web Service** → **Connect** ton repo `mybudget-api` ;
3. Render détecte `Dockerfile` automatiquement : runtime `Docker`, Root Directory `backend` (si le repo est `mybudget-api` à la racine, laisser vide et ajuster `dockerfilePath`) ;
   - Alternative : **New +** → **Blueprint** recopie `render.yaml` (racine du repo) — mêmes réglages ;
4. **Plan Free** (gratuit), **Region** : voir ci-dessous (`frankfurt` pour l'Europe ouest / Benin), **Health Check Path** : `/api/v1/health` ;
5. Variables d'environnement (onglet Environment) :
   - `JWT_SECRET` → tu peux générer une valeur : dans PowerShell `[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')`
   - `DATABASE_URL` → la connection string Neon copiée plus haut
   - `NODE_ENV` → `production`
6. **Create Web Service** → build + déploiement automatique (le `Dockerfile` lance `migrate` puis le serveur : la base est migrée automatiquement au démarrage).
7. Vérifie : `https://<ton-nom-de-service>.onrender.com/api/v1/health` → `{"success":true,...}`

## Étape 5 — Rebuild de l'APK avec la nouvelle URL

Depuis ton poste, modifie `mobile/.env` :

```
API_BASE_URL=https://<ton-nom-de-service>.onrender.com/api/v1
GOOGLE_SERVER_CLIENT_ID=
```

puis :

```powershell
cd E:\Mybudjet\mobile
.\build-release.ps1
```

APK livré dans `E:\Mybudjet\app-arm64-v8a-direct-release-obfuscated.apk` (+`\flutter-apk\`). Les amis réinstallent cette version — l'ancienne (URL tunnel) ne communiquera plus avec le serveur.

## Points d'attention (vérité terrain)

- Le service gratuit Render **dort après 15 min sans trafic** ; le premier accès après une pause peut prendre ~1 minute (l'écran de démarrage attendra). C'est le prix du gratuit — à l'usage pour des amis c'est généralement acceptable ; sinon Render Starter 7 $/mois.
- **Permanence garantie uniquement si** : le service Render tourne (quota 750 h/mois gratuit — à lui tout seul ça couvre usage personnel) **et** Neon garde la base (gratuit permanent, contrairement au Postgres gratuit de Render qui est supprimé après 30 jours).
- Les comptes de tes amis sont créés chez eux comme chez toi (e-mail + mot de passe), uniques.
- Pas de Google Sign-In tant que `GOOGLE_SERVER_CLIENT_ID` reste vide, ce qui est le cas ici — l'app utilise le compte/mot de passe.

## Alternative sans GitHub

Déployer l'image Docker sur **SnapDeploy** (4 conteneurs gratuits, 100 h/mois, sleep après 15 min — pas de carte) ou **Railway** ($5 d'essai puis $1/mois gratuit limité) : identique dans l'esprit, Docker image ou repo en entrée. GitHub reste le chemin le plus simple.

## Renseignement de l'APK — raccourcis de commande

PowerShell + adb connectés (téléphone en USB) :

```powershell
adb devices
adb install -r "E:\Mybudjet\app-arm64-v8a-direct-release-obfuscated.apk"
# Pour réinstaller/afficher l'onboarding :
adb shell pm clear com.mybudget.mybudget
```
