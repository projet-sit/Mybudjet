# Détection automatique par notifications — ÉTAT RÉEL : NON IMPLÉMENTÉE

## Sommaire

- [Résumé](#résumé)
- [Ce qui existe aujourd'hui](#ce-qui-existe-aujourdhui)
- [Ce qui n'existe pas (et pourquoi)](#ce-qui-nexiste-pas-et-pourquoi)
- [Pourquoi NotificationListenerService est sensible](#pourquoi-notificationlistenerservice-est-sensible)
- [Si c'est développé un jour](#si-cest-développé-un-jour)
- [Alternatives actuelles](#alternatives-actuelles)

## Résumé

MyBudget **ne détecte pas** les notifications de paiement (Mobile Money, SMS, etc.). Aucune permission Android de lecture de notifications n'est déclarée, aucun service n'écoute les notifications, et l'interrupteur « Alertes de budget » du profil ne fait qu'activer/désactiver un booléen local. Cette page documente l'état réel pour éviter toute ambiguïté ; ce n'est pas une fonctionnalité planifiée ou annoncée.

## Ce qui existe aujourd'hui

- **« Alertes de budget »** (Profil) : interrupteur qui enregistre la clé locale `budget_alerts` (SharedPreferences, défaut activé). Aucun mécanisme de notification n'est branché : pas d'icône de notification, pas de son, pas de canal Android.
- Niveaux d'alerte **50 % / 80 % / 100 %** calculés par le backend et affichés dans l'onglet Budgets (progress bars, libellés).
- Aucune notification n'est envoyée par le serveur (pas de FCM, pas d'e-mail d'alerte).

## Ce qui n'existe pas (et pourquoi)

- **NotificationListenerService** : non utilisé, non déclaré dans `AndroidManifest.xml`.
- Aucune permission `BIND_NOTIFICATION_LISTENER_SERVICE`, `POST_NOTIFICATIONS`, `READ_SMS`, etc.
- Aucun code de détection de SMS/notifications dans `lib/` (recherche : 0 résultat).
- Aucun envoi serveur (les routes « Ciel » `/alerts/check` prétendent simuler des alertes FCM mais sont obsolètes et vides — voir `docs/api/openapi.yaml`, section `x-obsolete`).

## Pourquoi NotificationListenerService est sensible

Lire les notifications donne accès au contenu de toutes les apps (codes OTP, messages, montants) :

- Permission « restreinte » depuis Android 13 : l'utilisateur doit l'accorder manuellement dans les **Paramètres restreints** (impossible via la boîte de dialogue normale).
- Risque pour la confidentialité (tout transite localement si bien fait — sinon exfiltration).
- Pour le Play Store : politique stricte sur les services d'écoute de notifications.

## Si c'est développé un jour

Le design envisagé (non prioritaire, **non planifié**) serait :

1. Service Android `NotificationListenerService` limité à une liste blanche de paquets (opérateurs Mobile Money).
2. Tout le traitement local : le texte de la notification est parsé sur le téléphone, **jamais envoyé** tel quel au serveur.
3. L'utilisateur confirme explicitement chaque transaction détectée (bouton « Ajouter »).
4. Flavor `direct` uniquement (hors Play Store, qui interdit ces pratiques).
5. Écran d'explication + bascule dans le profil.

Jusqu'à livraison effective, toute mention « détection automatique » dans les supports serait fausse.

## Alternatives actuelles

- Saisie manuelle via le bouton **+** (le chemin rapide, 3 taps).
- Hors-ligne : la saisie fonctionne sans réseau et se synchronise ensuite.
- Export PDF/CSV pour vérifier ses montants contre ses relevés Mobile Money.

## À confirmer

- Rien, au-delà de ce document : le périmètre est volontairement arrêté.
