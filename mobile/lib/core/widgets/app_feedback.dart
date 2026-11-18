import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Système de retour utilisateur (Success UX) — composant unique et réutilisable.
///
/// - [SuccessDialog] : confirmation visuelle animée d'une opération RÉUSSIE
///   (cercle vert clair + coche verte dessinée progressivement, rebond, fondu).
///   Jamais affichée en cas d'échec.
/// - [showSuccessDialog] : helper maison (titre, message, durée, action optionnelle).
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
/// - Se ferme automatiquement après [duration] (défaut 1,7 s).
/// - Un appui sur le fond ou « C'est compris » ferme immédiatement.
/// - Si [actionLabel] est fourni (ex. « Annuler » pour restaurer une suppression),
///   un bouton d'action est affiché et la boîte ne se ferme PAS automatiquement.
Future<void> showSuccessDialog(
  BuildContext context, {
  required String title,
  required String message,
  Duration duration = const Duration(milliseconds: 1700),
  String? actionLabel,
  VoidCallback? onAction,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Fermer',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return SuccessDialog(
        title: title,
        message: message,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
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

/// Boîte de confirmation animée : cercle vert + coche verte, titre, message.
class SuccessDialog extends StatefulWidget {
  const SuccessDialog({
    super.key,
    required this.title,
    required this.message,
    this.duration = const Duration(milliseconds: 1700),
    this.actionLabel,
    this.onAction,
    this.onClose,
  });

  final String title;
  final String message;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
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
      curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
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
    if (widget.actionLabel != null) return; // une action est proposée : on attend l'utilisateur
    _autoCloseTimer = Timer(widget.duration + const Duration(milliseconds: 350), () {
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
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('success-dialog'),
          width: math.min(320, MediaQuery.sizeOf(context).width - 64),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: scheme.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 32,
                offset: const Offset(0, 10),
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
                  key: const ValueKey('success-circle'),
                  size: const Size(96, 96),
                  painter: _SuccessCirclePainter(
                    progress: _checkProgress,
                    ringColor: AppColors.incomeGreen,
                    checkColor: AppColors.incomeGreen,
                    fillColor: AppColors.incomeGreen.withValues(alpha: 0.13),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FadeTransition(
                opacity: _textOpacity,
                child: Column(
                  children: [
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.45, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (widget.actionLabel != null) ...[
                    Flexible(
                      child: TextButton(
                        onPressed: widget.onAction,
                        child: Text(widget.actionLabel!, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.incomeGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: widget.onClose,
                      child: const Text('C’est compris'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cercle vert (anneau + fond teinté) avec coche verte dessinée progressivement.
class _SuccessCirclePainter extends CustomPainter {
  _SuccessCirclePainter({
    required this.progress,
    required this.ringColor,
    required this.checkColor,
    required this.fillColor,
  });

  final Animation<double> progress;
  final Color ringColor;
  final Color checkColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Fond teinté
    canvas.drawCircle(center, radius, Paint()..color = fillColor);

    // Anneau
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    // Coche verte, dessinée progressivement
    final t = progress.value.clamp(0.0, 1.0);
    if (t <= 0) return;

    final start = Offset(size.width * 0.28, size.height * 0.54);
    final elbow = Offset(size.width * 0.44, size.height * 0.68);
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
        ..color = checkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _SuccessCirclePainter oldDelegate) =>
      oldDelegate.progress.value != progress.value ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.checkColor != checkColor;
}
