import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Logo MYBUDGET — goutte d'eau sur dégradé MyBudget (maquette « MyBudget »).
class MyBudgetLogo extends StatelessWidget {
  const MyBudgetLogo({super.key, this.size = 56, this.light = false});

  final double size;

  /// Variante claire pour les fonds bleus (en-têtes).
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: light
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.deepGreenLight, AppColors.deepGreen],
              ),
        color: light ? Colors.white.withValues(alpha: 0.2) : null,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: light ? Border.all(color: Colors.white.withValues(alpha: 0.35)) : null,
        boxShadow: light
            ? null
            : [
                BoxShadow(
                  color: AppColors.deepGreen.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Icon(
        Icons.water_drop_rounded,
        size: size * 0.52,
        color: Colors.white,
      ),
    );
  }
}
