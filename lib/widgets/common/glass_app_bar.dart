import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:provider/provider.dart';
import 'package:chat_app_flutter/providers/auth_provider.dart';
import 'avatar_helper.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onAvatarTap;
  final Widget? trailing;

  const GlassAppBar({
    super.key,
    required this.title,
    this.onAvatarTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return liquid.GlassContainer(
      useOwnLayer: true,
      quality: liquid.GlassQuality.standard,
      shape: const liquid.LiquidVerticalRoundedRectangle(
        topRadius: 0,
        bottomRadius: 18,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (title == 'Yapp')
                Image.asset('assets/yapp-logo.png', height: 42)
              else
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              if (trailing != null)
                trailing!
              else if (onAvatarTap != null)
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, _) {
                        final user = authProvider.currentUser;
                        final avatarUrl = user?.avatarUrl;
                        final initial = user?.fullName.isNotEmpty == true
                            ? user!.fullName[0].toUpperCase()
                            : (user?.username.isNotEmpty == true
                                  ? user!.username[0].toUpperCase()
                                  : '?');

                        return CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.transparent,
                          backgroundImage:
                              avatarUrl != null && avatarUrl.isNotEmpty
                              ? AvatarHelper.getAvatarProvider(avatarUrl)
                              : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? Text(
                                  initial,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 10);
}
