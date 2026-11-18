/// Événements pouvant déclencher l'animation de confirmation « coche verte ».
///
/// Cette liste est FERMÉE. Toute modification doit être accompagnée d'une
/// mise à jour de [title]/[subtitle] et de la documentation.
enum SuccessEventType {
  expenseAdded,
  incomeAdded,
  walletCreated,
  savingsDeposited,
  savingsWithdrawn,
  savingsRecovered,
}

/// Charge utile d'un événement de succès.
///
/// [detail] : libellé déjà formaté dans la devise active
/// (ex. « 5 000 FCFA » pour un montant, ou le nom d'un portefeuille).
class SuccessEvent {
  const SuccessEvent({required this.type, required this.detail});

  final SuccessEventType type;
  final String detail;

  /// Titre court affiché dans la carte de confirmation.
  String get title => switch (type) {
        SuccessEventType.expenseAdded => 'Dépense enregistrée',
        SuccessEventType.incomeAdded => 'Revenu enregistré',
        SuccessEventType.walletCreated => 'Portefeuille créé',
        SuccessEventType.savingsDeposited => 'Versement enregistré',
        SuccessEventType.savingsWithdrawn => 'Retrait enregistré',
        SuccessEventType.savingsRecovered => 'Épargne récupérée',
      };

  /// Sous-titre concis (montant ou nom).
  String get subtitle => detail;
}
