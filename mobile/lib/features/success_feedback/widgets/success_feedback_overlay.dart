import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/success_event.dart';
import '../providers/success_feedback_provider.dart';
import 'success_icon.dart';

/// Overlay global de confirmation « coche verte ».
///
/// Affiché uniquement après l’émission d’un [SuccessEvent] par un cas d’usage
/// autorisé (dépense, revenu, portefeuille créé, opération d’épargne).
/// Les données reçues par synchronisation ou au démarrage ne passent jamais
/// par ici. Un tap n’importe où ferme l’animation immédiatement.
class SuccessFeedbackOverlay extends ConsumerWidget {
  const SuccessFeedbackOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(successFeedbackProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      child: event == null
          ? const SizedBox.shrink()
          : _SuccessPanel(key: ObjectKey(event), event: event),
    );
  }
}

class _SuccessPanel extends ConsumerWidget {
  const _SuccessPanel({super.key, required this.event});

  final SuccessEvent event;

  void _close(WidgetRef ref) => ref.read(successFeedbackProvider.notifier).clear();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scheme = Theme.of(context).colorScheme;
    final label = '${event.title} - ${event.subtitle}';

    if (reduceMotion) {
      // Réduction des animations : fondu simple de 150 ms, coche déjà dessinée.
      return _ReduceMotionPanel(
        event: event,
        label: label,
        onClose: () => _close(ref),
      );
    }

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _close(ref),
        child: Semantics(
          liveRegion: true,
          label: label,
          child: RepaintBoundary(
            child: Container(
              color: Colors.black.withValues(alpha: 0.18),
              alignment: const Alignment(0, 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SuccessIcon(),
                  const SizedBox(height: 16),

                  // Carte : apparaît en 0,70 → 1,20 s (fondu + léger glisser).
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1150),
                    curve: const Interval(0.58, 1.0, curve: Curves.easeOutCubic),
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - t.clamp(0.0, 1.0))),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      key: const ValueKey('success-card'),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scheme.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            event.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event.subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReduceMotionPanel extends StatelessWidget {
  const _ReduceMotionPanel({
    required this.event,
    required this.label,
    required this.onClose,
  });

  final SuccessEvent event;
  final String label;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Semantics(
          liveRegion: true,
          label: label,
          child: RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  alignment: const Alignment(0, 0.8),
                  child: child,
                ),
              ),
              child: Container(
                key: const ValueKey('success-card'),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SuccessIcon(animate: false),
                    const SizedBox(height: 10),
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
