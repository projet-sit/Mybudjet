import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../services/profile_photo_service.dart';

/// Photo de profil locale du téléphone (chemin du fichier ou null).
class ProfilePhotoController extends AsyncNotifier<String?> {
  @override
  FutureOr<String?> build() => ProfilePhotoService.instance.currentPath();

  Future<void> setFromPick(ImageSource source) async {
    final path = await ProfilePhotoService.instance.pickAndSave(source);
    if (path != null) {
      state = AsyncData(path);
    }
  }

  Future<void> clear() async {
    await ProfilePhotoService.instance.remove();
    state = const AsyncData(null);
  }
}

final profilePhotoProvider =
    AsyncNotifierProvider<ProfilePhotoController, String?>(ProfilePhotoController.new);
