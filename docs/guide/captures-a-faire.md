# Captures à ajouter au guide utilisateur

Le guide (`docs/guide/guide-utilisateur.md`) utilise des repères `[Capture : …]` en attendant les vrais écrans. Voici les captures à réaliser, dans l'ordre, sur un appareil en thème clair (et, si possible, en thème sombre) à 360×640 :

| # | Fichier suggéré | Écran / moment | Notes |
|---|---|---|---|
| 1 | `guide/img/accueil.png` | Accueil avec solde / Reste / Épargne renseignés | Données fictives clairement marquées |
| 2 | `guide/img/inscription.png` | Écran de création de compte | Données fictives |
| 3 | `guide/img/portefeuille.png` | Création du portefeuille | Données fictives |
| 4 | `guide/img/depense.png` | Feuille d'ajout d'une dépense (remplie) | ex. Transport, 2 500 FCFA — exemple fictif |
| 5 | `guide/img/revenu.png` | Feuille d'ajout d'un revenu (remplie) | ex. Salaire, 150 000 FCFA — exemple fictif |
| 6 | `guide/img/budgets.png` | Onglet Budgets, un budget à 80 % | ex. Alimentation 80 000 FCFA — exemple fictif |
| 7 | `guide/img/epargne.png` | Écran Mon épargne | Données fictives |
| 8 | `guide/img/recherche.png` | Recherche avec résultats | Données fictives |
| 9 | `guide/img/reset.png` | Boîte de réinitialisation double confirmation | Sans données sensibles |
| 10 | `guide/img/supprimer.png` | Boîte de suppression de compte | Sans données sensibles |
| 11 | `guide/img/faq.png` | Profil → Aide et FAQ, une question ouverte | Nouvel écran |
| 12 | `guide/img/synchro.png` | Badge « Synchronisé / En attente / Hors-ligne » | Mode avion utile |

**Contraste :** captures bien lisibles, sans nom ni montant réel d'une vraie personne.
**Nommage :** kebab-case, dossier `docs/guide/img/`.
**Export :** après ajout, référencer les images dans le guide (`![Accueil](img/accueil.png)`) puis régénérer le PDF avec `docs/build.ps1`.
