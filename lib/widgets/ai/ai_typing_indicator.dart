import 'package:flutter/material.dart';

class AiTypingIndicator extends StatefulWidget {
  const AiTypingIndicator({super.key});

  @override
  State<AiTypingIndicator> createState() => _AiTypingIndicatorState();
}

class _AiTypingIndicatorState extends State<AiTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              final phase = (_controller.value + index / 3) % 1;
              return Transform.translate(
                offset: Offset(0, -5 * (1 - (2 * phase - 1).abs())),
                child: Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
