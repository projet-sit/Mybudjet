import 'package:flutter/material.dart';

/// Politique de confidentialité de MYBUDGET (Profil → Politique de confidentialité).
/// Rédigée à partir du fonctionnement réel de l'application :
/// stockage serveur (PostgreSQL auto-hébergé Render, authentification par jeton),
/// cache local (SharedPreferences), notifications locales, aucun analytics.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _updatedAt = '18 novembre 2026';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    TextStyle h2(BuildContext context) => TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
          height: 1.3,
        );

    TextStyle body(BuildContext context) => TextStyle(
          fontSize: 13,
          height: 1.55,
          color: scheme.onSurfaceVariant,
        );

    Widget section(String title, List<String> paragraphs, BuildContext context) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: h2(context)),
              const SizedBox(height: 8),
              for (final p in paragraphs) ...[
                Text(p, style: body(context)),
                if (p != paragraphs.last) const SizedBox(height: 10),
              ],
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Politique de confidentialité')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(
              'MYBUDGET — Politique de confidentialité',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dernière mise à jour : $_updatedAt',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            section(
              'Introduction',
              [
                'La présente politique décrit quelles données l’application MYBUDGET '
                    'collecte, comment elles sont utilisées et quels sont vos droits. '
                    'Elle s’applique à toutes les fonctionnalités de l’application.',
                'MYBUDGET est une application de suivi de revenus et de dépenses : '
                    'elle ne vous demande aucune information sans rapport avec la gestion '
                    'de votre budget, et n’affiche aucune publicité.',
              ],
              context,
            ),
            section(
              'Données collectées',
              [
                'Données de compte : le numéro de téléphone utilisé pour l’inscription '
                    'et la connexion, le nom affiché que vous renseignez, et le mot de '
                    'passe (stocké uniquement sous forme chiffrée, jamais en clair).',
                'Données de votre budget : vos opérations (type, montant, catégorie, '
                    'description facultative, date et heure, mode de paiement), vos '
                    'portefeuilles, catégories personnalisées, budgets par catégorie, '
                    'épargne et objectifs éventuels.',
                'Données locales sur votre appareil : une copie de vos données récentes '
                    '(cache pour un fonctionnement hors ligne), la photo de profil si vous '
                    'en définissez une (stockée uniquement sur l’appareil), vos préférences '
                    '(thème, langue, alertes de budget, devise) et un jeton de session '
                    'permettant de rester connecté.',
                'Données techniques minimales : en cas de plantage, un rapport anonymisé '
                    '(message d’erreur, écran concerné, version de l’application) est '
                    'envoyé au serveur pour diagnostic. Aucun identifiant publicitaire, '
                    'aucune géolocalisation et aucune liste de contacts ne sont collectés.',
              ],
              context,
            ),
            section(
              'Utilisation des données',
              [
                'Les données collectées sont utilisées exclusivement pour faire '
                    'fonctionner l’application : authentification, affichage de votre '
                    'portefeuille et de vos opérations, recherche, statistiques, alertes '
                    'de budget (notifications locales) et export PDF de vos opérations.',
                'Le jeton de session sert à sécuriser les échanges entre l’application et '
                    'le serveur. Il est conservé sur l’appareil et renouvelé '
                    'automatiquement.',
              ],
              context,
            ),
            section(
              'Stockage et sécurité',
              [
                'Vos données sont hébergées sur un serveur sécurisé (base de données '
                    'PostgreSQL) et échangées via des connexions chiffrées (HTTPS). '
                    'Les mots de passe sont hachés et ne peuvent être ni lus ni récupérés.',
                'Sur l’appareil, les données de cache sont conservées dans l’espace '
                    'privé de l’application ; les autres applications ne peuvent pas y '
                    'accéder. Un résumé de session permet de retrouver vos données en '
                    'cas de réinstallation, tant que la session est valide.',
                'La sécurité absolue n’existe pas : nous protégeons vos données avec '
                    'des mesures raisonnables, mais aucun système n’est infaillible.',
              ],
              context,
            ),
            section(
              'Partage des données',
              [
                'Nous ne vendons pas vos données et ne les cédons à aucun tiers, à '
                    'aucun prix, pour aucune finalité publicitaire.',
                'Aucune donnée personnelle n’est transmise à des régies publicitaires, '
                    'des courtiers en données ou des outils d’analyse tiers.',
                'Le seul partage possible est celui que vous déclenchez vous-même : '
                    'l’export PDF de vos opérations, si vous choisissez de l’envoyer ou '
                    'de le partager volontairement via une autre application.',
              ],
              context,
            ),
            section(
              'Vos droits',
              [
                'Export : vous pouvez générer à tout moment un relevé PDF complet de vos '
                    'opérations depuis le Profil (Exporter mes transactions).',
                'Suppression : vous pouvez supprimer l’intégralité de vos données depuis '
                    'le Profil → Zone de danger → Supprimer tout. Cette suppression est '
                    'définitive : vos opérations, vos catégories personnalisées et vos '
                    'préférences sont effacées du serveur et de l’appareil.',
                'Rectification : vous pouvez modifier ou supprimer chaque opération, '
                    'renommer vos catégories personnalisées et corriger vos informations '
                    'à tout moment dans l’application.',
                'Pour exercer tout autre droit, ou pour toute question, utilisez le '
                    'bouton « Nous contacter » dans le Profil : nous vous répondrons.',
              ],
              context,
            ),
            section(
              'Conservation des données',
              [
                'Vos données sont conservées tant que votre compte est actif et tant '
                    'que vous utilisez l’application.',
                'Les rapports d’erreurs techniques sont conservés le temps nécessaire '
                    'au diagnostic, puis supprimés.',
                'La suppression via « Supprimer tout » efface définitivement vos données '
                    'du serveur et de l’appareil ; la réinitialisation ne peut pas être '
                    'annulée.',
              ],
              context,
            ),
            section(
              'Modification de la politique',
              [
                'Cette politique peut évoluer (nouvelles fonctionnalités, obligations '
                    'légales). La date de dernière mise à jour, affichée en haut de cette '
                    'page, indique quand elle a été révisée.',
                'En cas de changement substantiel, nous vous en informerons dans '
                    'l’application avant son entrée en vigueur.',
              ],
              context,
            ),
            section(
              'Contact',
              [
                'Pour toute question relative à la présente politique ou à vos données, '
                    'utilisez le bouton « Nous contacter » dans le Profil. '
                    'Nous nous engageons à vous répondre dans un délai raisonnable.',
              ],
              context,
            ),
          ],
        ),
      ),
    );
  }
}
