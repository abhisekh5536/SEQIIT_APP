import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'directory_screen.dart';
import 'home_screen.dart';
import 'notices_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  final ThemeController themeController;

  const MainShell({super.key, required this.themeController});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          const NoticesScreen(),
          const DirectoryScreen(),
          SettingsScreen(themeController: widget.themeController),
        ],
      ),
      bottomNavigationBar: _buildNavBar(context),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final p = Theme.of(context).colorScheme;
    final palette = AppTheme.paletteFor(Theme.of(context).brightness);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign_rounded),
            label: 'Notices',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Directory',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}