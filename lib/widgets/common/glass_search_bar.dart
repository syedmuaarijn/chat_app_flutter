import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'glass_container.dart';

class GlassSearchBar extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  const GlassSearchBar({
    super.key,
    this.hintText = "Search...",
    this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: GlassContainer(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        borderRadius: BorderRadius.circular(25),
        child: Row(
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedSearch01, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.only(bottom: 2), // Adjust for vertical alignment
                ),
              ),
            ),
            if (controller != null && controller!.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller?.clear();
                  if (onChanged != null) onChanged!("");
                },
                child: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
          ],
        ),
      ),
    );
  }
}
