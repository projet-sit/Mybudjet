import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Photo de profil de l'utilisateur sur l'appareil.
/// Local au téléphone (jamais envoyée telle quelle) — pour la synchroniser
/// il faudrait un stockage d'images côté serveur.
class ProfilePhotoService {
  ProfilePhotoService._();
  static final ProfilePhotoService instance = ProfilePhotoService._();

  static const _prefsKey = 'profile_photo_path';
  static const _fileName = 'mybudget_avatar.jpg';

  final _picker = ImagePicker();

  /// Chemin de la photo locale ou null. Vérifie que le fichier existe bien.
  Future<String?> currentPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefsKey);
    if (path == null) return null;
    if (await File(path).exists()) return path;
    await prefs.remove(_prefsKey);
    return null;
  }

  /// Prend une photo avec l'appareil photo ou en choisit une dans la galerie.
  /// Retourne le nouveau chemin, ou null si l'utilisateur a annulé.
  Future<String?> pickAndSave(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (picked == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final target = File('${docs.path}/$_fileName');
    await File(picked.path).copy(target.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, target.path);
    return target.path;
  }

  /// Supprime la photo locale.
  Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefsKey);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Le fichier est illisible/déjà supprimé : on nettoie juste la référence.
      }
    }
    await prefs.remove(_prefsKey);
  }

  /// Initiale à afficher si pas de photo (prénom de l'utilisateur).
  static String initialOf(User? user) {
    final name = user?.displayName.trim() ?? '';
    return name.isEmpty ? 'M' : name[0].toUpperCase();
  }
}
