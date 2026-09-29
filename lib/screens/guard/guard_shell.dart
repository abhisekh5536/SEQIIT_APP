import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/security_models.dart';
import '../../services/app_session.dart';
import '../../services/guard_service.dart';
import '../../services/security_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import 'guard_alerts_screen.dart';
import 'guard_home_screen.dart';
import 'guard_profile_screen.dart';
import 'guard_register_screen.dart';
import 'widgets/guard_widgets.dart';

/// The gate app: its own shell rather than more `isGuard` branches in the
/// resident/admin one. Four tabs — Gate · Inside · Alerts · Me.
///
/// Also owns the SOS listener, so an alert rings whichever tab is open.
class GuardShell extends StatefulWidget {
  final ThemeController themeController;

  const GuardShell({super.key, required this.themeController});

  @override
  State<GuardShell> createState() => _GuardShellState();
}

class _GuardShellState extends State<GuardShell> {
  int _index = 0;
  StreamSubscription<SosAlert>? _sosSub;

  /// Alerts already shown in a dialog, so the realtime updates that follow
  /// an insert do not stack a second dialog on the first.
  final Set<String> _announced = {};

  @override
  void initState() {
    super.initState();
    GuardService.instance.loadGates();

    final societyId = AppSession.instance.societyId;
    if (societyId != null) {
      SecurityService.instance.initRealtime(societyId);
    }
    _sosSub = SecurityService.instance.onSosAlertReceived.listen(_onSos);
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    super.dispose();
  }

  void _onSos(SosAlert alert) {
    if (!mounted || !alert.isActive || _announced.contains(alert.id)) return;
    _announced.add(alert.id);
    openSosAlert(context, alert);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.paletteFor(Theme.of(context).brightness);
    final scheme = Theme.of(context).colorScheme;

    final pages = [
      GuardHomeScreen(onOpenTab: (i) => setState(() => _index = i)),
      const GuardRegisterScreen(),
      const GuardAlertsScreen(),
      GuardProfileScreen(themeController: widget.themeController),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.92),
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: AnimatedBuilder(
          animation: SecurityService.instance,
          builder: (context, _) {
            final openSos = SecurityService.instance.activeSosAlerts
                .where((a) => a.isOpen)
                .length;
            return NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.shield_outlined),
                  selectedIcon: Icon(Icons.shield_rounded),
                  label: 'Gate',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.groups_2_outlined),
                  selectedIcon: Icon(Icons.groups_2_rounded),
                  label: 'Inside',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: openSos > 0,
                    label: Text('$openSos'),
                    child: const Icon(Icons.crisis_alert_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: openSos > 0,
                    label: Text('$openSos'),
                    child: const Icon(Icons.crisis_alert_rounded),
                  ),
                  label: 'Alerts',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.badge_outlined),
                  selectedIcon: Icon(Icons.badge_rounded),
                  label: 'Me',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
