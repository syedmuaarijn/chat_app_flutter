import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

class GlassBottomBar extends StatefulWidget {
  final TabController tabController;

  const GlassBottomBar({
    super.key,
    required this.tabController,
  });

  @override
  State<GlassBottomBar> createState() => _GlassBottomBarState();
}

class _GlassBottomBarState extends State<GlassBottomBar> {
  double _indicatorPosition = 0.0;

  @override
  void initState() {
    super.initState();
    widget.tabController.animation?.addListener(_updateIndicator);
  }

  @override
  void dispose() {
    widget.tabController.animation?.removeListener(_updateIndicator);
    super.dispose();
  }

  void _updateIndicator() {
    if (mounted) {
      setState(() {
        _indicatorPosition = widget.tabController.animation?.value ?? 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Chats', 'Groups', 'Calls', 'Settings'];
    const outlinedIcons = [
      HugeIcons.strokeRoundedChat01,
      HugeIcons.strokeRoundedUserGroup,
      HugeIcons.strokeRoundedCall02,
      HugeIcons.strokeRoundedSetting07,
    ];
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = widget.tabController.index;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: liquid.GlassContainer(
        useOwnLayer: true,
        quality: liquid.GlassQuality.standard,
        shape: const liquid.LiquidRoundedSuperellipse(borderRadius: 28),
        child: SizedBox(
          height: 82,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / 4;
              return Stack(
                children: [
                  Positioned(
                    left: _indicatorPosition * itemWidth + 4,
                    top: 6,
                    child: liquid.GlassContainer(
                      width: itemWidth - 8,
                      height: 66,
                      useOwnLayer: true,
                      quality: liquid.GlassQuality.standard,
                      shape: const liquid.LiquidRoundedSuperellipse(
                        borderRadius: 22,
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(4, (index) {
                      final selected = index == currentIndex;
                      final iconColor = isDark ? Colors.white : Colors.black87;
                      final labelColor = isDark ? Colors.white : Colors.black87;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => widget.tabController.animateTo(index),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              HugeIcon(
                                icon: outlinedIcons[index],
                                color: selected ? iconColor : colors.onSurfaceVariant,
                                size: 23,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                labels[index],
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: selected
                                          ? labelColor
                                          : colors.onSurfaceVariant,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
