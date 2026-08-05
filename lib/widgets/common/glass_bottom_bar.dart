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
  double? _dragStartPosition;
  int? _dragStartIndex;
  // When true the animation listener is suppressed so it cannot jump the
  // indicator back to the previous tab before gliding to the new one.
  bool _suppressAnimation = false;

  @override
  void initState() {
    super.initState();
    _indicatorPosition = widget.tabController.index.toDouble();
    widget.tabController.animation?.addListener(_updateIndicator);
  }

  @override
  void dispose() {
    widget.tabController.animation?.removeListener(_updateIndicator);
    super.dispose();
  }

  void _updateIndicator() {
    if (mounted && !_suppressAnimation) {
      setState(() {
        _indicatorPosition = widget.tabController.animation?.value ?? 0.0;
      });
    }
  }

  void _handleDragStart(DragStartDetails details, double itemWidth) {
    setState(() {
      _suppressAnimation = true;
      _dragStartPosition = details.localPosition.dx;
      _dragStartIndex = widget.tabController.index;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details, double itemWidth, double maxWidth) {
    if (_dragStartPosition == null || _dragStartIndex == null) return;

    final delta = details.localPosition.dx - _dragStartPosition!;
    final newPosition = (_dragStartIndex! + delta / itemWidth).clamp(0.0, 3.0);

    if ((newPosition - _indicatorPosition).abs() > 0.01) {
      setState(() {
        _indicatorPosition = newPosition;
      });
    }
  }

  void _handleDragEnd(DragEndDetails details, double itemWidth) {
    if (_dragStartPosition == null || _dragStartIndex == null) return;

    final targetIndex = _indicatorPosition.round().clamp(0, 3);

    // Snap the indicator to the target immediately so there is no jump.
    setState(() {
      _indicatorPosition = targetIndex.toDouble();
      _dragStartPosition = null;
      _dragStartIndex = null;
    });

    if (targetIndex != widget.tabController.index) {
      // animateTo drives tabController.animation which would normally move
      // the indicator — keep suppression on until the animation settles.
      widget.tabController.animateTo(
        targetIndex,
        duration: const Duration(milliseconds: 1),
      );
    }

    // Re-enable the animation listener after the frame so any subsequent
    // tap-driven or swipe-driven tab changes animate normally.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _suppressAnimation = false);
    });
  }

  void _handleDragCancel() {
    // Snap back to the current tab if the drag was cancelled.
    final currentIndex = widget.tabController.index;
    setState(() {
      _indicatorPosition = currentIndex.toDouble();
      _suppressAnimation = false;
      _dragStartPosition = null;
      _dragStartIndex = null;
    });
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
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) => _handleDragStart(details, itemWidth),
                onHorizontalDragUpdate: (details) => _handleDragUpdate(details, itemWidth, constraints.maxWidth),
                onHorizontalDragEnd: (details) => _handleDragEnd(details, itemWidth),
                onHorizontalDragCancel: _handleDragCancel,
                onTapUp: (details) {
                  final tappedIndex = (details.localPosition.dx / itemWidth).floor().clamp(0, 3);
                  widget.tabController.animateTo(tappedIndex);
                },
                child: Stack(
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
                        );
                      }),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
