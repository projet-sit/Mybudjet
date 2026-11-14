import 'package:flutter/material.dart';

/// Catégories autorisées par le backend (aucune donnée fictive).
abstract final class ExpenseCategories {
  static const list = [
    ('Alimentation', Icons.restaurant),
    ('Transport', Icons.directions_car),
    ('Logement', Icons.home),
    ('Santé', Icons.favorite),
    ('Études', Icons.school),
    ('Communication', Icons.chat_bubble),
    ('Loisirs', Icons.sports_esports),
    ('Shopping', Icons.shopping_bag),
    ('Abonnements', Icons.subscriptions),
    ('Famille', Icons.family_restroom),
    ('Autres', Icons.more_horiz),
  ];

  static const paymentMethods = ['Espèces', 'Mobile Money', 'Carte', 'Virement'];
}

abstract final class IncomeCategories {
  static const list = ['Salaire', 'Business', 'Cadeau', 'Bourse', 'Autres'];
}
