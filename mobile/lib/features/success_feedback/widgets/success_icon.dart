import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Icône de confirmation : carré arrondi vert #059669 avec coche blanche
/// tracée progressivement.
///
/// - 0 → 0,35 s : carré apparaît du centre (easeOutBack).
/// - 0,35 → 0,70 s : coche tracée via [PathMetric.extractPath].
/// - Onde cercle vert clair s'élargissant une fois.
/// - Mode reduce-motion : icône statique + fondu 150 ms.
class SuccessIcon extends StatefulWidget {
  const SuccessIcon({super.key, this.size = 96, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<SuccessIcon> createState() => _SuccessIconState();
}

class _SuccessIconState extends State<SuccessIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _squareScale;
  late final Animation<double> _checkProgress;
  late final Animation<double> _waveProgress;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _controller = AnimationController(vsync: this, duration: Duration.zero)..forward();
      _squareScale = const AlwaysStoppedAnimation<double>(1.0);
      _checkProgress = const AlwaysStoppedAnimation<double>(1.0);
      _waveProgress = const AlwaysStoppedAnimation<double>(1.0);
      return;
    }

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _squareScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.40, curve: Curves.easeOutBack),
    );
    _checkProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 0.75, curve: Curves.easeInOut),
    );
    _waveProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.95, curve: Curves.easeOutCubic),
    );

    // Retour haptique léger à la fin du tracé de la coche.
    _checkProgress.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.lightImpact();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _SuccessIconPainter(
          squareScale: _squareScale,
          checkProgress: _checkProgress,
          waveProgress: _waveProgress,
        ),
      ),
    );
  }
}

class _SuccessIconPainter extends CustomPainter {
  _SuccessIconPainter({
    required this.squareScale,
    required this.checkProgress,
    required this.waveProgress,
  }) : super(repaint: Listenable.merge([squareScale, checkProgress, waveProgress]));

  final Animation<double> squareScale;
  final Animation<double> checkProgress;
  final Animation<double> waveProgress;

  static const Color _green = Color(0xFF059669);
  static const Color _waveGreen = Color(0xFF34D399);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ---------- Onde ----------
    final waveT = waveProgress.value.clamp(0.0, 1.0);
    if (waveT > 0) {
      final waveRadius = size.width * (0.35 + 0.75 * waveT);
      final waveOpacity = (1.0 - waveT) * 0.45;
      if (waveOpacity > 0) {
        canvas.drawCircle(
          center,
          waveRadius,
          Paint()
            ..color = _waveGreen.withValues(alpha: waveOpacity)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // ---------- Carré arrondi ----------
    final scale = squareScale.value.clamp(0.0, 1.12);
    final radius = size.width * 0.28;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-center.dx, -center.dy);

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Fond vert #059669
    canvas.drawRRect(rrect, Paint()..color = _green);

    // ---------- Coche blanche ----------
    final t = checkProgress.value.clamp(0.0, 1.0);
    if (t > 0) {
      final path = Path()
        ..moveTo(size.width * 0.27, size.height * 0.53)
        ..lineTo(size.width * 0.44, size.height * 0.67)
        ..lineTo(size.width * 0.74, size.height * 0.36);

      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.single;
        final drawn = metric.length * t;
        final drawnPath = metric.extractPath(0, drawn);
        canvas.drawPath(
          drawnPath,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * 0.088
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SuccessIconPainter oldDelegate) => true;
}
