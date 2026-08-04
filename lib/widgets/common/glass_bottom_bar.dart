import 'package:flutter/material.dart';
import 'package:cupertino_native/cupertino_native.dart';

class GlassBottomBar extends StatelessWidget {
  final TabController tabController;

  const GlassBottomBar({
    super.key,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['Chats', 'Groups', 'Calls', 'Settings'];
    const icons = [
      'message.fill',
      'person.3.fill',
      'phone.fill',
      'gearshape.fill',
    ];

    return CNTabBar(
      items: List.generate(
        4,
        (index) => CNTabBarItem(
          label: labels[index],
          icon: CNSymbol(icons[index]),
        ),
      ),
      currentIndex: tabController.index,
      height: 85,
      onTap: (index) => tabController.animateTo(index),
    );
  }
}
