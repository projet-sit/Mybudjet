@echo off
REM Démarre la stack MyBudget : PostgreSQL (Docker) + backend Node + tunnel public Cloudflare.
REM À relancer après chaque redémarrage du PC (ou depuis le démarrage automatique Windows).

echo === PostgreSQL (port 5434) ===
docker start mybudget-db

echo.
echo === Backend Node (port 3000) ===
start "mybudget-backend" cmd /k "cd /d E:\Mybudjet\backend && node src/server.js"

echo.
echo === Tunnel public Cloudflare ===
REM L'URL CHANGERA à chaque relance. Met à jour mobile/.env puis recompile l'APK
REM si tu veux une APK avec la nouvelle URL.
start "mybudget-tunnel" cmd /k ""C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel --url http://localhost:3000 2>&1 | tee E:\Mybudjet\backend\tunnel.log"

echo.
echo === Statut ===
echo health local : http://localhost:3000/api/v1/health
echo Tunnel URL   : voir E:\Mybudjet\backend\tunnel.log (ligne "Your quick Tunnel")
pause
