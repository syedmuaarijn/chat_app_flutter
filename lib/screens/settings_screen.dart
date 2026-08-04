import 'package:chat_app_flutter/providers/auth_provider.dart';
import 'package:chat_app_flutter/providers/theme_provider.dart';
import 'package:chat_app_flutter/screens/profile_settings_screen.dart';
import 'package:chat_app_flutter/widgets/common/neon_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cupertino_native/cupertino_native.dart';
import '../widgets/common/glass_container.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassContainer(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primary.withValues(alpha: 0.18),
                  child: Icon(CupertinoIcons.person, color: colors.primary),
                ),
                title: Text(
                  'Profile Settings',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Change avatar, display name, and bio',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  color: colors.onSurfaceVariant,
                  size: 18,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileSettingsScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ThemeModeSelector(
                    selected: themeProvider.themeMode,
                    onChanged: themeProvider.setThemeMode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About Yapp',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Yapp: because silence is overrated.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            NeonButton(
              text: 'Logout',
              onPressed: () async {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSelector extends StatefulWidget {
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeModeSelector({required this.selected, required this.onChanged});

  @override
  State<_ThemeModeSelector> createState() => _ThemeModeSelectorState();
}

class _ThemeModeSelectorState extends State<_ThemeModeSelector> {
  double? _dragPosition;
  int? _dragIndex;

  int get _selectedIndex {
    const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    return modes.indexOf(widget.selected);
  }

  int get _activeIndex => _dragIndex ?? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    const icons = [
      CupertinoIcons.device_phone_portrait,
      CupertinoIcons.sun_max,
      CupertinoIcons.moon,
    ];
    const labels = ['System', 'Light', 'Dark'];

    return GlassContainer(
      height: 52,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / 3;
          final indicatorLeft = _dragPosition ?? (_selectedIndex * itemWidth);
          
          return GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() {
                _dragPosition = _selectedIndex * itemWidth;
                _dragIndex = _selectedIndex;
              });
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _dragPosition = (_dragPosition! + details.delta.dx)
                    .clamp(0.0, constraints.maxWidth - itemWidth);
                _dragIndex = ((_dragPosition! / itemWidth) + 0.5).floor().clamp(0, 2);
              });
            },
            onHorizontalDragEnd: (details) {
              final index = _activeIndex;
              setState(() {
                _dragPosition = null;
                _dragIndex = null;
              });
              if (index != _selectedIndex) {
                widget.onChanged(modes[index]);
              }
            },
            onHorizontalDragCancel: () {
              setState(() {
                _dragPosition = null;
                _dragIndex = null;
              });
            },
            onTapUp: (details) {
              final index = (details.localPosition.dx / itemWidth).floor().clamp(0, 2);
              widget.onChanged(modes[index]);
            },
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: indicatorLeft,
                  width: itemWidth,
                  child: const GlassContainer(
                    borderRadius: BorderRadius.all(Radius.circular(22)),
                    child: SizedBox.expand(),
                  ),
                ),
                Row(
                  children: List.generate(3, (index) {
                    final active = index == _activeIndex;
                    return Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icons[index],
                              size: 17,
                              color: active
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              labels[index],
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: active
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                    fontWeight: active
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
            ),
          );
        },
      ),
    );
  }
}
