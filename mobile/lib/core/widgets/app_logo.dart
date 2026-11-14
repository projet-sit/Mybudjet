import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon-mybudget-foreground.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
