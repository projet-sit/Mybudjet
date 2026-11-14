import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/logo.dart';

/// Écran d'attente — dégradé MyBudget, logo goutte, chargement.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.deepGreenLight, AppColors.deepGreen, AppColors.deepGreenDark],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MyBudgetLogo(size: 96),
              const SizedBox(height: 24),
              const Text(
                'MYBUDGET',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vos finances, simples et claires.',                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
