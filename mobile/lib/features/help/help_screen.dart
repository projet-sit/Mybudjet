import 'package:flutter/material.dart';

/// Donnée d'une question fréquente. Texte intégré à l'application :
/// l'écran fonctionne entièrement hors-ligne, sans aucun appel extérieur.
class FaqItem {
  const FaqItem(this.question, this.answer);
  final String question;
  final String answer;
}

const List<FaqItem> faqItems = [
  FaqItem(
    'À quoi sert un portefeuille ?',
    'Le portefeuille est ton compte principal. Tu y notes tes revenus et tes dépenses, et MyBudget calcule ton solde tout seul. Tu peux en créer un dès l’inscription.',
  ),
  FaqItem(
    'Comment noter une dépense ?',
    'Depuis l’accueil, touche le bouton +. Choisis « Dépense », saisis le montant en FCFA, la catégorie, puis la date. Valide : la dépense est enregistrée et ton solde se met à jour.',
  ),
  FaqItem(
    'Comment noter un revenu ?',
    'Même principe : bouton +, puis « Revenu ». Saisis le montant, la catégorie (Salaire, Business, Cadeau, Bourse ou Autres) et la date.',
  ),
  FaqItem(
    'Que veut dire « Reste » ?',
    'Le Reste, c’est l’argent réellement disponible : ton solde moins ton épargne. C’est ce montant que tu peux dépenser sans toucher à ta réserve.',
  ),
  FaqItem(
    'À quoi sert l’épargne ?',
    'L’épargne te permet de mettre de côté, dans le même portefeuille, sans créer de compte supplémentaire. Depuis « Mon épargne », tu peux verser, retirer ou tout récupérer en une fois.',
  ),
  FaqItem(
    'L’épargne est-elle une dépense ?',
    'Non. Une mise de côté n’apparaît pas dans tes dépenses ni dans tes statistiques de dépenses. Elle reste à part, sous « Épargne ».',
  ),
  FaqItem(
    'Comment fixer un budget par catégorie ?',
    'Va dans l’onglet Budgets, choisis une catégorie (par exemple Alimentation) et un montant limite pour le mois. MyBudget te signale quand tu atteins 50 %, 80 % puis 100 % de ton budget.',
  ),
  FaqItem(
    'Comment remettre mes comptes à zéro ?',
    'Profil → « Réinitialiser tout à 0 ». Un avertissement demande confirmation. La période en cours est archivée (ton historique est conservé) et ton épargne est gardée par défaut.',
  ),
  FaqItem(
    'Puis-je utiliser MyBudget sans internet ?',
    'Oui. Tu peux noter une dépense ou un revenu sans réseau : ils sont gardés sur ton téléphone et envoyés automatiquement dès que la connexion revient.',
  ),
  FaqItem(
    'Mes données sont-elles privées ?',
    'Oui. Tes données sont liées à ton compte et protégées par ton mot de passe. Personne d’autre n’y a accès. Ne partage jamais ton mot de passe.',
  ),
  FaqItem(
    'Comment changer de téléphone ?',
    'Installe MyBudget sur le nouveau téléphone, puis connecte-toi avec ton numéro et ton mot de passe habituels : ton solde, tes opérations et tes budgets reviennent.',
  ),
  FaqItem(
    'Comment exporter mes données ?',
    'Profil → « Exporter mes transactions » génère un fichier PDF avec tout ton historique, que tu peux partager ou garder. Un export CSV existe aussi pour réutiliser tes données dans un tableur.',
  ),
  FaqItem(
    'Mes dernières opérations n’apparaissent pas, que faire ?',
    'Si tu viens de les saisir sans connexion, patiente : elles reviennent automatiquement dès que ton téléphone est connecté. Sinon, rouvre l’écran concerné pour l’actualiser.',
  ),
  FaqItem(
    'J’ai oublié mon mot de passe, que faire ?',
    'Sur l’écran de connexion, touche « Mot de passe oublié » et suis les étapes. Ton mot de passe sera remplacé, et toutes tes sessions seront déconnectées pour des raisons de sécurité.',
  ),
  FaqItem(
    'Comment supprimer mon compte ?',
    'Profil → « Supprimer mes données ». La suppression est définitive : ton compte et toutes tes opérations sont effacés. Pense à exporter ton historique avant, tu ne pourras plus le récupérer.',
  ),
];

/// Écran « Aide et FAQ » (Profil → Aide et FAQ).
/// 12 à 15 questions en accordéon. Texte intégré : fonctionne hors-ligne.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _openIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aide et FAQ'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Les questions qu’on nous pose le plus',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < faqItems.length; i++)
              _FaqTile(
                item: faqItems[i],
                isOpen: _openIndex == i,
                onToggle: () => setState(() => _openIndex = _openIndex == i ? null : i),
              ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item, required this.isOpen, required this.onToggle});

  final FaqItem item;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.question,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            Divider(height: 1, color: scheme.outline),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Text(
                item.answer,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
