import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fou d'architecture : l'émission de SuccessEvent ne peut se faire
/// que depuis les cas d'usage autorisés (voir docs/animation-confirmation.md).
///
/// Interdit notamment : écrans (profil, réglages, épargne...), widgets,
/// listeners de synchronisation, code photo de profil.
void main() {
  const allowedEmissionFiles = {
    'lib/providers/transaction_provider.dart',
    'lib/providers/wallet_provider.dart',
  };

  test('successFeedbackProvider.emit n’est appelé que depuis les cas d’usage autorisés', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'le test doit être lancé depuis mobile/');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (!content.contains('successFeedbackProvider')) continue;
      if (!content.contains('.emit(')) continue;

      final normalized = entity.path.replaceAll('\\', '/');
      if (allowedEmissionFiles.contains(normalized)) continue;
      if (normalized.startsWith('lib/features/success_feedback/')) continue;
      offenders.add(normalized);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Succès émis hors cas d’usage autorisés : ${offenders.join(", ")}',
    );
  });

  test('la feature success_feedback et ses émissions ne sont jamais importées par le flux photo ou le profil', () {
    final watchList = <String>[
      'lib/features/profile/profile_screen.dart',
      'lib/features/profile/',
    ];

    final offenders = <String>[];
    for (final watch in watchList) {
      final type = FileSystemEntity.typeSync(watch);
      final files = <File>[];
      if (type == FileSystemEntityType.directory) {
        for (final entity in Directory(watch).listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
        }
      } else if (type == FileSystemEntityType.file) {
        files.add(File(watch));
      }
      for (final file in files) {
        final content = file.readAsStringSync();
        if (content.contains('success_feedback') || content.contains('successFeedbackProvider')) {
          offenders.add(file.path.replaceAll('\\', '/'));
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Le flux photo/profil ne doit pas importer success_feedback : ${offenders.join(", ")}',
    );
  });
}
