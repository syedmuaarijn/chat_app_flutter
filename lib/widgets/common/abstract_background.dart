import 'dart:ui';

import 'package:flutter/material.dart';

class AbstractBackground extends StatelessWidget {
  const AbstractBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageAsset = isDark
        ? 'assets/dark-mode-bg.png'
        : 'assets/light-mode-bg.png';

    return Stack(
      fit: StackFit.expand,
      children: [
        // ImageFiltered blurs the source only; liquid-glass surfaces remain
        // responsible for their own refraction and accessibility behaviour.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Image.asset(
            imageAsset,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Container(
          color: isDark
              ? Colors.black.withValues(alpha: 0.26)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}
