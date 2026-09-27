import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'directory_screen.dart';
import 'home_screen.dart';
import 'my_flat_screen.dart';
import 'notices_screen.dart';
import 'vehicles/guard/vehicle_gate_lookup_screen.dart';
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
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final isAdmin = AppSession.instance.isAdmin;
        final isGuard = AppSession.instance.isGuard;

        // A guard has no flat, so the third slot becomes the gate register
        // instead of "My Flat" — which would be empty for them.
        final pages = [
          const HomeScreen(),
          const NoticesScreen(),
          if (isGuard)
            // Its own header and SafeArea, like every other shell page, but
            // no back arrow — this is a tab, not a pushed route.
            const VehicleGateLookupScreen(showBack: false)
          else if (isAdmin)
            const DirectoryScreen()
          else
            const MyFlatScreen(),
          SettingsScreen(themeController: widget.themeController),
        ];

        final safeIndex = _index < pages.length ? _index : 0;

        return Scaffold(
          body: IndexedStack(
            index: safeIndex,
            children: pages,
          ),
          bottomNavigationBar:
              _buildNavBar(context, isAdmin, isGuard, safeIndex),
        );
      },
    );
  }

  Widget _buildNavBar(
      BuildContext context, bool isAdmin, bool isGuard, int selectedIndex) {
    final p = Theme.of(context).colorScheme;
    final palette = AppTheme.paletteFor(Theme.of(context).brightness);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign_rounded),
            label: 'Notices',
          ),
          if (isGuard)
            const NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield_rounded),
              label: 'Gate',
            )
          else if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Directory',
            )
          else
            const NavigationDestination(
              icon: Icon(Icons.home_work_outlined),
              selectedIcon: Icon(Icons.home_work_rounded),
              label: 'My Flat',
            ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
