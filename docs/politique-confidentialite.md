# Politique de confidentialité — MYBUDGET

**Résumé en 3 lignes :** MyBudget collecte uniquement les données nécessaires au suivi de votre argent (compte, opérations, budgets, épargne). Vos données sont stockées en base PostgreSQL hébergée en Europe (Render / Neon) et ne sont ni vendues ni partagées. Vous pouvez exporter votre historique et supprimer votre compte à tout moment depuis l'app.

## Sommaire

- [Données collectées](#données-collectées)
- [Finalités](#finalités)
- [Lieu et durée de conservation](#lieu-et-durée-de-conservation)
- [Sécurité](#sécurité)
- [Services tiers](#services-tiers)
- [Vos droits](#vos-droits)
- [Contact](#contact)
- [État de ce document](#état-de-ce-document)

## Données collectées

| Donnée | Obligatoire | Exemple factice |
|---|---|---|
| Numéro de téléphone (ou e-mail historique) | oui | +229 00 00 00 00 |
| Nom d'affichage | oui | « Awa » |
| Mot de passe (hashé bcrypt, jamais en clair) | oui | — |
| Portefeuilles, montants (stockés en XOF), dates, catégories, modes de paiement | oui | 155 000 FCFA, 14/11/2026, Alimentation |
| Budgets, périodes (archives), objectifs d'épargne | oui | Budget Alimentation : 80 000 FCFA |
| Logs techniques serveur (route, statut, durée, IP via proxy) | oui | — |
| Rapports de plantage (message tronqué, écran, version) | optionnel | — |

**Aucune** localisation, **aucun** contact, **aucun** contenu de SMS ou de notifications n'est collecté.

## Finalités

- Faire fonctionner l'app : solde, opérations, budgets, épargne, statistiques.
- Sécurité : détection d'abus (rate limiting), restauration de session, réinitialisation du mot de passe.
- Stabilité : rapports de plantage anonymisés (via votre compte, sans contenu métier).

## Lieu et durée de conservation

- Hébergement de l'API : **Render** (région frankfurt, UE). Base : **Neon** (PostgreSQL, UE).
- Les données sont conservées tant que le compte est actif.
- Les archives de périodes sont conservées jusqu'à suppression du compte.
- Après suppression du compte : effacement en cascade (compte, transactions, budgets, périodes, objectifs, sessions). Irréversible.

## Sécurité

- Mot de passe hashé avec bcrypt ; jetons de session hashés SHA-256, rotés à chaque rafraîchissement, révoqués à chaque changement de mot de passe.
- HTTPS obligatoire en production (Render gère TLS).
- Accès aux données par le seul porteur du jeton ; aucun tiers n'y accède.
- Détail complet : [`securite-et-confidentialite.md`](securite-et-confidentialite.md).

## Services tiers

| Service | Rôle | Données |
|---|---|---|
| Render | hébergement API (Docker) | requête HTTP (pas de contenu métier côté Render au-delà du transit TLS) |
| Neon | base PostgreSQL | toutes les données métier au repos |
| Google Play / GitHub Releases | distribution de l'APK | aucun contenu métier |

Pas de Firebase, pas de SDK pub/mesure, pas de cookies, pas de traceur tiers.

## Vos droits

- **Accès** : profil → écran complet de votre compte ; export PDF/CSV depuis Profil → « Exporter » (l'export PDF utilise la devise active, nom `operations_AAAA-MM-JJ.pdf`).
- **Rectification** : modification du nom/prénom et des montants initiaux dans l'app (historisés).
- **Suppression** : deux niveaux, au choix —
  - Profil → Zone de danger → **Supprimer tout** : efface vos opérations, catégories personnalisées et préférences (la devise est remise sur FCFA) et l'historique, sans supprimer le compte ;
  - Profil → **Supprimer mes données** : efface aussi le compte, définitivement.
- **Portabilité** : export CSV (API) ou PDF (app) réutilisables dans un tableur.

## Contact

Le responsable du traitement est joignable depuis l'application : Profil → **Nous contacter** (ouvre WhatsApp). Aucune adresse publique n'est publiée.

## État de ce document

Document d'information rédigé pour les besoins de la distribution de l'app ; **à faire relire par un juriste avant toute publication publique** (Play Store, site). Ne constitue pas un texte juridique validé. Les champs `[À REMPLIR]` doivent être complétés avant publication.
