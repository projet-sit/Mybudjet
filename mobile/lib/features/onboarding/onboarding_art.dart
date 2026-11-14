import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Illustrations CustomPaint de l'onboarding (aucune capture d'écran :
/// uniquement du dessin vectoriel). Palette = AppColors de l'app.
/// Les pages sont de simples "cartes" décoratives, sans données fictives.

// Dégradé du panneau : deepGreenLight → deepGreenDark (identique à l'identité MyBudget).
const panelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.deepGreenLight, AppColors.deepGreenDark],
);

const _gold = Color(0xFFF5B83E);
const _goldRing = Color(0xFFC77808);
const _goldInner = Color(0xFFFFD977);

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key, required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return switch (page) {
      0 => const CustomPaint(painter: _WalletArt(), size: Size.infinite),
      1 => const CustomPaint(painter: _BudgetArt(), size: Size.infinite),
      _ => const CustomPaint(painter: _PhoneSyncArt(), size: Size.infinite),
    };
  }
}

/// Halo translucide commun aux 3 illustrations (cercles décoratifs).
void _paintHalo(Canvas canvas, Size size) {
  final soft = Paint()..color = Colors.white.withValues(alpha: 0.18);
  canvas.drawCircle(Offset(size.width * 0.24, size.height * 0.62), size.width * 0.30, soft);
  final softer = Paint()..color = Colors.white.withValues(alpha: 0.12);
  canvas.drawCircle(Offset(size.width * 0.76, size.height * 0.34), size.width * 0.21, softer);
}

RRect _rr(Rect rect, double radius) =>
    RRect.fromRectAndRadius(rect, Radius.circular(radius));

void _shadow(Canvas canvas, Path path, {double blur = 16, double dy = 8, double a = 0.25}) {
  canvas.drawShadow(
    path,
    Colors.black.withValues(alpha: a),
    blur,
    false,
  );
}

/// Page 1 — portefeuille de dépenses (white card + 3 pièces).
class _WalletArt extends CustomPainter {
  const _WalletArt();

  void _coin(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(center, r, Paint()..color = _gold);
    canvas.drawCircle(
      center,
      r * 0.58,
      Paint()
        ..color = _goldRing
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.20,
    );
    canvas.drawCircle(center, r * 0.20, Paint()..color = _goldInner);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintHalo(canvas, size);
    final w = size.width;
    final h = size.height;

    // Pièces (haut).
    _coin(canvas, Offset(w * 0.31, h * 0.26), h * 0.080);
    _coin(canvas, Offset(w * 0.51, h * 0.155), h * 0.062);
    _coin(canvas, Offset(w * 0.67, h * 0.27), h * 0.050);

    // Portefeuille — rabat arrière.
    final flap = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.47),
      width: w * 0.42,
      height: h * 0.22,
    );
    canvas.drawRRect(_rr(flap, h * 0.075), Paint()..color = const Color(0xFFDCEBF5));

    // Portefeuille — corps principal.
    final body = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.575),
      width: w * 0.54,
      height: h * 0.37,
    );
    final bodyPath = Path()..addRRect(_rr(body, h * 0.105));
    _shadow(canvas, bodyPath, blur: 20, dy: 12, a: 0.3);
    canvas.drawRRect(_rr(body, h * 0.105), Paint()..color = Colors.white);

    // Languette bleue + point blanc.
    final clasp = Rect.fromCenter(
      center: Offset(body.right - w * 0.065, body.center.dy),
      width: w * 0.165,
      height: h * 0.16,
    );
    canvas.drawRRect(_rr(clasp, h * 0.08), Paint()..color = AppColors.deepGreenDark);
    canvas.drawCircle(clasp.center, h * 0.038, Paint()..color = Colors.white);

    // Capsule inférieure : pastille rouge (dépense) + barre douce.
    final pill = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.88),
      width: w * 0.34,
      height: h * 0.095,
    );
    final pillPath = Path()..addRRect(_rr(pill, h * 0.05));
    _shadow(canvas, pillPath, blur: 12, dy: 6, a: 0.2);
    canvas.drawRRect(_rr(pill, h * 0.05), Paint()..color = Colors.white);
    canvas.drawCircle(Offset(pill.left + w * 0.065, pill.center.dy), h * 0.030,
        Paint()..color = AppColors.expenseRed);
    canvas.drawRRect(
      _rr(
        Rect.fromLTWH(pill.left + w * 0.115, pill.center.dy - h * 0.009, w * 0.125, h * 0.018),
        h * 0.009,
      ),
      Paint()..color = AppColors.soft,
    );
  }

  @override
  bool shouldRepaint(covariant _WalletArt oldDelegate) => false;
}

/// Page 2 — anneau de budget (70%) + 3 barres de progression + cible.
class _BudgetArt extends CustomPainter {
  const _BudgetArt();

  void _bar(Canvas canvas, Rect track, double fraction, Color fill) {
    canvas.drawRRect(_rr(track, track.height / 2), Paint()..color = AppColors.line);
    canvas.drawRRect(
      _rr(
        Rect.fromLTWH(track.left, track.top, track.width * fraction, track.height),
        track.height / 2,
      ),
      Paint()..color = fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintHalo(canvas, size);
    final w = size.width;
    final h = size.height;

    // Carte blanche.
    final card = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.52),
      width: w * 0.62,
      height: h * 0.62,
    );
    final cardPath = Path()..addRRect(_rr(card, h * 0.095));
    _shadow(canvas, cardPath, blur: 22, dy: 14, a: 0.3);
    canvas.drawRRect(_rr(card, h * 0.095), Paint()..color = Colors.white);

    // Anneau 70 % (illustration).
    final ringCenter = Offset(card.center.dx, card.top + card.height * 0.285);
    final ringR = card.width * 0.205;
    final ringStroke = card.width * 0.075;
    canvas.drawCircle(
      ringCenter,
      ringR,
      Paint()
        ..color = AppColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStroke,
    );
    final sweep = 2 * 3.1415926535 * 0.70;
    canvas.drawArc(
      Rect.fromCircle(center: ringCenter, radius: ringR),
      -3.1415926535 / 2,
      sweep,
      false,
      Paint()
        ..color = AppColors.deepGreenDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStroke
        ..strokeCap = StrokeCap.round,
    );
    final pct = TextPainter(
      text: TextSpan(
        text: '70%',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w800,
          fontSize: card.width * 0.155,
          color: AppColors.textDark,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pct.paint(canvas, ringCenter - Offset(pct.width / 2, pct.height / 2));

    // Barres de progression.
    final barWidth = card.width * 0.68;
    final barHeight = card.height * 0.062;
    final barLeft = card.center.dx - barWidth / 2;
    final barsTop = card.top + card.height * 0.60;
    const gap = 0.085;
    _bar(
      canvas,
      Rect.fromLTWH(barLeft, barsTop, barWidth, barHeight),
      0.74,
      AppColors.deepGreenLight,
    );
    _bar(
      canvas,
      Rect.fromLTWH(barLeft, barsTop + h * gap, barWidth, barHeight),
      0.44,
      AppColors.warning,
    );
    _bar(
      canvas,
      Rect.fromLTWH(barLeft, barsTop + h * gap * 2, barWidth, barHeight),
      0.90,
      AppColors.deepGreenDark,
    );

    // Cible / pièces (badge or en haut à droite de la carte).
    final target = Offset(card.right + w * 0.015, card.top + h * 0.02);
    canvas.drawCircle(target, h * 0.075, Paint()..color = _gold);
    canvas.drawCircle(target, h * 0.046, Paint()..color = _goldInner);
    canvas.drawCircle(target, h * 0.020, Paint()..color = _goldRing);
  }

  @override
  bool shouldRepaint(covariant _BudgetArt oldDelegate) => false;
}

/// Page 3 — téléphone hors-ligne : liste + nuage de synchronisation + bouclier.
class _PhoneSyncArt extends CustomPainter {
  const _PhoneSyncArt();

  @override
  void paint(Canvas canvas, Size size) {
    _paintHalo(canvas, size);
    final w = size.width;
    final h = size.height;

    // Nuage (gauche).
    final cloud = Offset(w * 0.185, h * 0.30);
    final cloudPaint = Paint()..color = Colors.white;
    canvas.drawCircle(cloud + Offset(-w * 0.045, h * 0.010), h * 0.055, cloudPaint);
    canvas.drawCircle(cloud + Offset(0, -h * 0.025), h * 0.070, cloudPaint);
    canvas.drawCircle(cloud + Offset(w * 0.048, h * 0.010), h * 0.058, cloudPaint);
    canvas.drawRRect(
      _rr(Rect.fromCenter(center: cloud + Offset(0, h * 0.032), width: w * 0.150, height: h * 0.048), h * 0.024),
      cloudPaint,
    );

    // Flèches circulaires (synchronisation) sous le nuage.
    final sync = Offset(w * 0.185, h * 0.47);
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.020
      ..strokeCap = StrokeCap.round;
    final arcRect = Rect.fromCenter(center: sync, width: h * 0.148, height: h * 0.148);
    canvas.drawArc(arcRect, 3.5, 4.4, false, arcPaint);
    canvas.drawArc(arcRect, 3.5 + 3.1416, 4.4, false, arcPaint);
    // Têtes de flèche.
    final head = Path();
    head.moveTo(sync.dx - h * 0.048, sync.dy + h * 0.030);
    head.lineTo(sync.dx - h * 0.075, sync.dy + h * 0.072);
    head.lineTo(sync.dx - h * 0.020, sync.dy + h * 0.076);
    head.close();
    canvas.drawPath(head, Paint()..color = Colors.white.withValues(alpha: 0.92));
    final head2 = Path();
    head2.moveTo(sync.dx + h * 0.048, sync.dy - h * 0.030);
    head2.lineTo(sync.dx + h * 0.075, sync.dy - h * 0.072);
    head2.lineTo(sync.dx + h * 0.020, sync.dy - h * 0.076);
    head2.close();
    canvas.drawPath(head2, Paint()..color = Colors.white.withValues(alpha: 0.92));

    // Téléphone — corps.
    final phone = Rect.fromCenter(
      center: Offset(w * 0.545, h * 0.49),
      width: w * 0.315,
      height: h * 0.72,
    );
    final phonePath = Path()..addRRect(_rr(phone, h * 0.105));
    _shadow(canvas, phonePath, blur: 22, dy: 12, a: 0.32);
    canvas.drawRRect(_rr(phone, h * 0.105), Paint()..color = Colors.white);

    // Encoche (capsule).
    canvas.drawRRect(
      _rr(
        Rect.fromCenter(
          center: Offset(phone.center.dx, phone.top + h * 0.045),
          width: phone.width * 0.36,
          height: h * 0.022,
        ),
        h * 0.011,
      ),
      Paint()..color = AppColors.line,
    );

    // Bloc d'en-tête (bleu clair) + 2 barres.
    final header = Rect.fromCenter(
      center: Offset(phone.center.dx, phone.top + h * 0.165),
      width: phone.width * 0.78,
      height: h * 0.155,
    );
    canvas.drawRRect(_rr(header, h * 0.045), Paint()..color = AppColors.soft.withValues(alpha: 0.38));
    canvas.drawRRect(
      _rr(
        Rect.fromLTWH(header.left + h * 0.035, header.top + h * 0.035, phone.width * 0.24, h * 0.026),
        h * 0.013,
      ),
      Paint()..color = AppColors.deepGreenDark,
    );
    canvas.drawRRect(
      _rr(
        Rect.fromLTWH(header.left + h * 0.035, header.top + h * 0.080, phone.width * 0.34, h * 0.026),
        h * 0.013,
      ),
      Paint()..color = AppColors.textDark,
    );

    // 3 lignes d'opérations (+ / − / −).
    final rows = <(Color, bool)>[
      (AppColors.incomeGreen, true),
      (AppColors.expenseRed, false),
      (AppColors.expenseRed, false),
    ];
    final rowX = phone.left + h * 0.055;
    for (var i = 0; i < rows.length; i++) {
      final rowY = phone.top + h * (0.36 + i * 0.125);
      final (color, positive) = rows[i];
      canvas.drawCircle(Offset(rowX, rowY), h * 0.031, Paint()..color = color);
      final sign = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.008
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(rowX - h * 0.013, rowY),
        Offset(rowX + h * 0.013, rowY),
        sign,
      );
      if (positive) {
        canvas.drawLine(
          Offset(rowX, rowY - h * 0.013),
          Offset(rowX, rowY + h * 0.013),
          sign,
        );
      }
      canvas.drawRRect(
        _rr(Rect.fromLTWH(rowX + h * 0.048, rowY - h * 0.016, phone.width * 0.40, h * 0.024), h * 0.012),
        Paint()..color = AppColors.textDark,
      );
      canvas.drawRRect(
        _rr(Rect.fromLTWH(rowX + h * 0.048, rowY + h * 0.016, phone.width * 0.28, h * 0.016), h * 0.008),
        Paint()..color = AppColors.textMuted.withValues(alpha: 0.55),
      );
    }

    // Bouclier (droite) + coche verte.
    final shield = Rect.fromCenter(
      center: Offset(w * 0.845, h * 0.615),
      width: w * 0.150,
      height: h * 0.165,
    );
    final shieldPath = Path()
      ..moveTo(shield.center.dx, shield.top)
      ..quadraticBezierTo(shield.center.dx + shield.width * 0.52, shield.top + shield.height * 0.16,
          shield.right, shield.top + shield.height * 0.28)
      ..quadraticBezierTo(shield.right, shield.bottom - shield.height * 0.32,
          shield.center.dx, shield.bottom)
      ..quadraticBezierTo(shield.left, shield.bottom - shield.height * 0.32,
          shield.left, shield.top + shield.height * 0.28)
      ..quadraticBezierTo(shield.center.dx - shield.width * 0.52, shield.top + shield.height * 0.16,
          shield.center.dx, shield.top)
      ..close();
    _shadow(canvas, shieldPath, blur: 12, dy: 6, a: 0.25);
    canvas.drawPath(shieldPath, Paint()..color = Colors.white);
    final check = Path()
      ..moveTo(shield.center.dx - shield.width * 0.22, shield.center.dy + h * 0.008)
      ..lineTo(shield.center.dx - shield.width * 0.055, shield.center.dy + h * 0.040)
      ..lineTo(shield.center.dx + shield.width * 0.26, shield.center.dy - h * 0.038);
    canvas.drawPath(
      check,
      Paint()
        ..color = AppColors.incomeGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.016
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PhoneSyncArt oldDelegate) => false;
}
