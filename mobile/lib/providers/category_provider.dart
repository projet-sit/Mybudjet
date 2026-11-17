import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import '../services/category_repository.dart';

/// Catégories affichées (défauts système + personnalisées utilisateur).
/// Cache d'abord pour un affichage instantané, revalidation en arrière-plan.
class CategoryController extends AsyncNotifier<List<Category>> {
  @override
  FutureOr<List<Category>> build() async {
    final cached = await CategoryRepository.instance.loadCache();
    if (cached.isNotEmpty) {
      unawaited(_refreshInBackground());
      return sortCategories(cached);
    }
    try {
      return await CategoryRepository.instance.fetchAll();
    } catch (_) {
      // Aucun cache et backend injoignable : l'écran affichera un message.
      return const [];
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      state = AsyncData(await CategoryRepository.instance.fetchAll());
    } catch (_) {
      // Le cache affiché reste la référence jusqu'à la prochaine ouverture.
    }
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await CategoryRepository.instance.fetchAll());
    } catch (_) {
      final cached = await CategoryRepository.instance.loadCache();
      state = AsyncData(sortCategories(cached));
    }
  }

  Future<void> refreshAfterLocalChange() async {
    try {
      state = AsyncData(await CategoryRepository.instance.fetchAll());
    } catch (_) {
      final cached = await CategoryRepository.instance.loadCache();
      state = AsyncData(sortCategories(cached));
    }
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoryController, List<Category>>(CategoryController.new);

/// Catégories de dépenses, triées (défauts → personnalisées → « Autres »).
final expenseCategoriesProvider = Provider<List<Category>>((ref) {
  final all = ref.watch(categoriesProvider).value ?? const <Category>[];
  return all.where((c) => c.type == 'expense').toList();
});

/// Catégories de revenus, triées.
final incomeCategoriesProvider = Provider<List<Category>>((ref) {
  final all = ref.watch(categoriesProvider).value ?? const <Category>[];
  return all.where((c) => c.type == 'income').toList();
});
