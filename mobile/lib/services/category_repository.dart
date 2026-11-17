import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category.dart';
import 'api_client.dart';

/// Accès réseau + cache local des catégories (défauts + personnalisées).
/// En cas de doute sur le réseau, le cache reste la source d'affichage.
class CategoryRepository {
  CategoryRepository._();
  static final CategoryRepository instance = CategoryRepository._();

  static const _cacheKey = 'cache_categories';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Charge depuis le réseau puis met en cache. En échec réseau : repli cache.
  Future<List<Category>> fetchAll({String? type}) async {
    try {
      final res = await ApiClient.instance.dio.get(
        '/categories',
        queryParameters: type == null ? null : {'type': type},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      final rows = (data['categories'] as List)
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      await saveCache(rows);
      return sortCategories(rows);
    } on DioException {
      final cached = await loadCache();
      if (cached.isNotEmpty) return sortCategories(cached);
      rethrow;
    }
  }

  /// Lecture cache (sans réseau). Utilisée pour l'aperçu instantané.
  Future<List<Category>> loadCache() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCache(List<Category> all) async {
    final prefs = await _prefs;
    await prefs.setString(
      _cacheKey,
      jsonEncode(all.map((c) => c.toJson()).toList()),
    );
  }

  /// Crée une catégorie personnalisée. En doublon serveur → renvoie l'existante
  /// avec `existed=true` (l'appelant sélectionne la catégorie et affiche le message métier).
  Future<CategoryCreateResult> create({
    required String type,
    required String name,
    required String clientId,
  }) async {
    try {
      final res = await ApiClient.instance.dio.post(
        '/categories',
        data: {'id': clientId, 'type': type, 'name': name},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      final category = Category.fromJson(Map<String, dynamic>.from(data['category'] as Map));
      final fused = data['fused'] == true;
      await refreshAndCache(upsert: category);
      return CategoryCreateResult(category: category, existed: false, fused: fused);
    } on DioException catch (e) {
      final existing = _detailsCategory(e);
      if (e.response?.statusCode == 409 && existing != null) {
        return CategoryCreateResult(category: existing, existed: true, fused: false);
      }
      rethrow;
    }
  }

  /// Renomme une catégorie personnalisée. En doublon → `existed=true` avec l'existante.
  Future<CategoryCreateResult> rename(String id, String name) async {
    try {
      final res = await ApiClient.instance.dio.patch('/categories/$id', data: {'name': name});
      final data = res.data['data'] as Map<String, dynamic>;
      final category = Category.fromJson(Map<String, dynamic>.from(data['category'] as Map));
      await refreshAndCache(upsert: category);
      return CategoryCreateResult(category: category, existed: false, fused: false);
    } on DioException catch (e) {
      final existing = _detailsCategory(e);
      if (e.response?.statusCode == 409 && existing != null) {
        return CategoryCreateResult(category: existing, existed: true, fused: false);
      }
      rethrow;
    }
  }

  /// Suppression. Si des budgets sont liés et non confirmés → [BudgetLinkedException].
  Future<void> delete(String id, {bool confirmBudgets = false}) async {
    try {
      await ApiClient.instance.dio.delete(
        '/categories/$id',
        queryParameters: confirmBudgets ? {'confirmBudgets': '1'} : null,
      );
      await refreshAndCache(removeId: id);
    } on DioException catch (e) {
      final error = _errorObject(e);
      if (e.response?.statusCode == 409 && error?['code'] == 'CATEGORY_HAS_BUDGET') {
        final details = error?['details'];
        final budgets = (details is Map && details['budgets'] is List)
            ? (details['budgets'] as List)
                .map((b) => BudgetLink(
                      name: (b as Map)['category'] as String? ?? '',
                      limitAmount: (b)['limitAmount'] as num? ?? 0,
                    ))
                .toList()
            : const <BudgetLink>[];
        throw BudgetLinkedException(budgets);
      }
      rethrow;
    }
  }

  /// Met à jour le cache depuis le réseau, ou localement en hors-ligne.
  Future<void> refreshAndCache({Category? upsert, String? removeId}) async {
    try {
      await fetchAll();
    } catch (_) {
      final cached = await loadCache();
      var merged = [...cached];
      if (upsert != null) {
        merged.removeWhere((c) => c.id == upsert.id);
        merged.add(upsert);
      }
      if (removeId != null) merged.removeWhere((c) => c.id == removeId);
      await saveCache(merged);
    }
  }

  /// Supprime tout le cache des catégories (réinitialisation complète).
  Future<void> clearCache() async {
    final prefs = await _prefs;
    await prefs.remove(_cacheKey);
  }

  // ----- helpers erreurs -----

  Map<String, dynamic>? _errorObject(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final error = data['error'];
    return error is Map ? Map<String, dynamic>.from(error) : null;
  }

  Category? _detailsCategory(DioException e) {
    final error = _errorObject(e);
    final details = error?['details'];
    if (details is! Map) return null;
    final existing = details['category'];
    return existing is Map ? Category.fromJson(Map<String, dynamic>.from(existing)) : null;
  }
}

class CategoryCreateResult {
  const CategoryCreateResult({required this.category, required this.existed, required this.fused});
  final Category category;
  final bool existed;
  final bool fused;
}

class BudgetLink {
  const BudgetLink({required this.name, required this.limitAmount});
  final String name;
  final num limitAmount;
}

class BudgetLinkedException implements Exception {
  const BudgetLinkedException(this.budgets);
  final List<BudgetLink> budgets;
}
