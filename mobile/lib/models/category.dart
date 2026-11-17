import '../core/utils/category_names.dart';

/// Catégorie applicative : défaut système (isDefault true, liée via id) ou
/// personnalisée (liée à l'utilisateur).
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.isDefault,
    this.iconKey = 'label',
  });

  final String id;
  final String name;
  final String type; // 'expense' | 'income'
  final bool isDefault;
  final String iconKey;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        type: (json['type'] as String?) ?? 'expense',
        isDefault: (json['isDefault'] as bool?) ?? (json['is_default'] as bool? ?? false),
        iconKey: (json['iconKey'] as String?) ?? (json['icon_key'] as String? ?? 'label'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'isDefault': isDefault,
        'iconKey': iconKey,
      };

  String get normalized => normalizeCategoryName(name);
}

/// Tri affiché : défauts (ordre produit) → personnalisées (par nom) → « Autres ».
List<Category> sortCategories(List<Category> input) {
  final copy = [...input];
  int otherKey(Category c) => c.normalized == normalizeCategoryName(otherName) ? 1 : 0;
  int defaultIndex(Category c) {
    if (!c.isDefault || otherKey(c) == 1) return 999;
    final order = c.type == 'expense' ? expenseDefaultOrder : incomeDefaultOrder;
    final idx = order.map(normalizeCategoryName).toList().indexOf(c.normalized);
    return idx == -1 ? 500 : idx;
  }

  copy.sort((a, b) {
    if (otherKey(a) != otherKey(b)) return otherKey(a) - otherKey(b);
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    if (a.isDefault) return defaultIndex(a) - defaultIndex(b);
    return a.normalized.compareTo(b.normalized);
  });
  return copy;
}
