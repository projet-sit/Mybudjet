import 'package:flutter_test/flutter_test.dart';

import 'package:mybudget/core/utils/category_names.dart';
import 'package:mybudget/models/category.dart';

Category _cat(String name, String type, {bool isDefault = false, String id = 'x'}) =>
    Category(id: id, name: name, type: type, isDefault: isDefault, iconKey: isDefault ? 'label' : 'label');

void main() {
  group('normalizeCategoryName', () {
    test('casse, accents et espaces multiples', () {
      expect(normalizeCategoryName('Études'), 'etudes');
      expect(normalizeCategoryName('  Coiffure  '), 'coiffure');
      expect(normalizeCategoryName('GROCERIE'), 'grocerie');
      expect(normalizeCategoryName('Santé   Publique'), 'sante publique');
      expect(normalizeCategoryName("L'Épicerie"), "l'epicerie");
    });
  });

  group('validateCategoryName', () {
    test('valide un nom correct (trim + réduction des espaces)', () {
      final check = validateCategoryName('  Coiffure  ');
      expect(check.ok, isTrue);
      expect(check.value, 'Coiffure');
    });

    test('refuse un nom trop court', () {
      expect(validateCategoryName('x').ok, isFalse);
      expect(validateCategoryName('').ok, isFalse);
      expect(validateCategoryName('   ').ok, isFalse);
    });

    test('refuse un nom trop long', () {
      expect(validateCategoryName('a' * 31).ok, isFalse);
      expect(validateCategoryName('a' * 30).ok, isTrue);
    });

    test('refuse les caractères interdits', () {
      expect(validateCategoryName('Coiffure!').ok, isFalse);
      expect(validateCategoryName('Coiff@re').ok, isFalse);
      expect(validateCategoryName('Coiffure.').ok, isFalse);
    });

    test('accepte apostrophes et tirets', () {
      expect(validateCategoryName("L'Épicerie").ok, isTrue);
      expect(validateCategoryName('Saint-Denis').ok, isTrue);
      expect(validateCategoryName('Noël 2026').ok, isTrue);
    });
  });

  group('sortCategories', () {
    test('défauts dans l’ordre produit, personnalisées avant « Autres », insensible casse', () {
      final input = [
        _cat('Autres', 'expense', isDefault: true, id: 'd11'),
        _cat('Coiffure', 'expense', id: 'c1'),
        _cat('AAAA', 'expense', id: 'c3'),
        _cat('Alimentation', 'expense', isDefault: true, id: 'd1'),
        _cat('Logement', 'expense', isDefault: true, id: 'd3'),
        _cat('Santé', 'expense', isDefault: true, id: 'd4'),
        _cat('Transport', 'expense', isDefault: true, id: 'd2'),
      ];
      final sorted = sortCategories(input).map((c) => c.name).toList();
      expect(sorted.indexOf('AAAA') > sorted.indexOf('Alimentation'), isTrue);
      expect(sorted.indexOf('AAAA') > sorted.indexOf('Transport'), isTrue);
      expect(sorted.indexOf('AAAA') > sorted.indexOf('Logement'), isTrue);
      expect(sorted.indexOf('AAAA') < sorted.indexOf('Coiffure'), isTrue);
      expect(sorted.last, 'Autres');
    });

    test('les revenus ont leur propre section', () {
      final input = [
        _cat('Autres', 'income', isDefault: true, id: 'i6'),
        _cat('Cadeau', 'income', isDefault: true, id: 'i3'),
        _cat('Salaire', 'income', isDefault: true, id: 'i1'),
        _cat('Freelance', 'income', id: 'i7'),
      ];
      final sorted = sortCategories(input).map((c) => c.name).toList();
      expect(sorted.first, 'Salaire');
      expect(sorted.indexOf('Freelance') > sorted.indexOf('Cadeau'), isTrue);
      expect(sorted.last, 'Autres');
    });
  });
}
