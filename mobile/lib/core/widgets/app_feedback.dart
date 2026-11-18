import 'package:flutter/material.dart';

/// Retours utilisateur homogènes (snackbars avec icône).
/// Les confirmations d'opération réussie ne sont pas affichées.

// ---------- Snackbars ----------

void showErrorSnackBar(BuildContext context, String message) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.errorContainer,
      content: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600))),
        ],
      ),
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message, {IconData icon = Icons.info_outline_rounded}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.secondaryContainer,
      content: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600))),
        ],
      ),
    ),
  );
}

void showWarningSnackBar(BuildContext context, String message) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.tertiaryContainer,
      content: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w600))),
        ],
      ),
    ),
  );
}
