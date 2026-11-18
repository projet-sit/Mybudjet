import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Système de retour utilisateur (Success UX) — composant unique et réutilisable.
///
/// - [SuccessDialog] : confirmation visuelle animée d'une opération RÉUSSIE
///   (carré arrondi vert + coche blanche dessinée progressivement).
///   Jamais affichée en cas d'échec.
/// - [showSuccessDialog] : helper maison (durée configurable).
/// - [showErrorSnackBar] / [showInfoSnackBar] / [showWarningSnackBar] :
///   snackbars homogènes avec icône pour les autres retours.

// ---------- Feedback helpers ----------

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
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
            ),
          ),
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
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
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
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Affiche la boîte de confirmation de succès.
///
/// - Élément minimal : le cercle avec la coche animée, et « Effectué ».
/// - Se ferme automatiquement après [duration] (défaut 2,2 s),
///   et au toucher en dehors. Aucun bouton.
Future<void> showSuccessDialog(
  BuildContext context, {
  Duration duration = const Duration(milliseconds: 2200),
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Fermer',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return SuccessDialog(
        duration: duration,
        onClose: () => Navigator.of(dialogContext).pop(),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(curved), child: child),
      );
    },
  );
}

/// Boîte de confirmation animée : cercle plein vert + coche blanche et
/// l'intitulé « Effectué ». Aucun bouton, aucun détail d'opération.
class SuccessDialog extends StatefulWidget {
  const SuccessDialog({
    super.key,
    this.duration = const Duration(milliseconds: 2200),
    this.onClose,
  });

  final Duration duration;
  final VoidCallback? onClose;

  @override
  State<SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<SuccessDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _circleScale;
  late final Animation<double> _checkProgress;
  late final Animation<double> _textOpacity;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _circleScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _checkProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.32, 0.75, curve: Curves.easeInOut),
    );
    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
      _scheduleAutoClose();
      HapticFeedback.lightImpact();
    });
  }

  void _scheduleAutoClose() {
    _autoCloseTimer = Timer(widget.duration, () {
      if (mounted) widget.onClose?.call();
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('success-dialog'),
          width: math.min(320, MediaQuery.sizeOf(context).width - 64),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          decoration: BoxDecoration(
            // Carte blanche unie + texte sombre : toujours lisible,
            // quel que soit le fond (comme l'icône fournie).
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5E5E5), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _circleScale.value,
                    child: Opacity(
                      opacity: _circleScale.value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  );
                },
                child: CustomPaint(
                  key: const ValueKey('success-icon'),
                  size: const Size(88, 88),
                  painter: _SuccessIconPainter(
                    progress: _checkProgress,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FadeTransition(
                opacity: _textOpacity,
                child: const Text(
                  'Effectué',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: Color(0xFF111111),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carré arrondi vert (fond dégradé haut clair -> bas foncé) avec coche blanche
/// tracée progressivement — style moderne "iOS" type image fournie.
class _SuccessIconPainter extends CustomPainter {
  _SuccessIconPainter({required this.progress});

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.23));

    // Fond vert dégradé (haut #36D64B -> bas #1FB33B)
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF36D64B), Color(0xFF1FB33B)],
    );
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(rect));

    // Reflet subtil en haut (style moderne sobre)
    final gloss = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.07, size.height * 0.06, size.width * 0.86, size.height * 0.40),
      Radius.circular(size.width * 0.18),
    );
    canvas.drawRRect(gloss, Paint()..color = Colors.white.withValues(alpha: 0.12));

    // Coche blanche, tracée progressivement
    final t = progress.value.clamp(0.0, 1.0);
    if (t <= 0) return;

    final start = Offset(size.width * 0.27, size.height * 0.54);
    final elbow = Offset(size.width * 0.44, size.height * 0.69);
    final end = Offset(size.width * 0.74, size.height * 0.34);

    final firstLen = (elbow - start).distance;
    final secondLen = (end - elbow).distance;
    final total = firstLen + secondLen;
    final drawn = t * total;

    final path = Path()..moveTo(start.dx, start.dy);
    if (drawn <= firstLen) {
      final f = drawn / firstLen;
      path.lineTo(start.dx + (elbow.dx - start.dx) * f, start.dy + (elbow.dy - start.dy) * f);
    } else {
      path.lineTo(elbow.dx, elbow.dy);
      final f = ((drawn - firstLen) / secondLen).clamp(0.0, 1.0);
      path.lineTo(elbow.dx + (end.dx - elbow.dx) * f, elbow.dy + (end.dy - elbow.dy) * f);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.088
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _SuccessIconPainter oldDelegate) =>
      oldDelegate.progress.value != progress.value;
}
