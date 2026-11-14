import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// File d'attente locale des opérations non encore synchronisées.
/// Identifiants UUID côté client : relancer ne crée jamais de doublon.
class SyncQueue {
  SyncQueue._internal();
  static final SyncQueue instance = SyncQueue._internal();

  static const _key = 'sync_pending_ops';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<String>> _load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _save(List<String> ids) async {
    final prefs = await _prefs;
    await prefs.setString(_key, jsonEncode(ids));
  }

  Future<int> count() async => (await _load()).length;

  Future<List<String>> ids() async => _load();

  Future<String> enqueue({String? id}) async {
    final opId = id ?? const Uuid().v4();
    final current = await _load();
    if (!current.contains(opId)) {
      current.add(opId);
      await _save(current);
    }
    return opId;
  }

  Future<void> dequeue(String id) async {
    final current = await _load();
    current.remove(id);
    await _save(current);
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_key);
  }

  /// Clé déterministe pour opérations détectées par notification.
  String deterministicId(String eventKey) => eventKey;
}
