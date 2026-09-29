import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_session.dart';
import '../../services/guard_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/resident_widgets.dart';
import 'widgets/guard_widgets.dart';

/// The guard's own page: who they are on record, which gate this phone is
/// at, appearance, and sign-out. Shows "Security Guard", not "Member".
class GuardProfileScreen extends StatefulWidget {
  final ThemeController themeController;
  final bool showBack;

  const GuardProfileScreen({
    super.key,
    required this.themeController,
    this.showBack = false,
  });

  @override
  State<GuardProfileScreen> createState() => _GuardProfileScreenState();
}

class _GuardProfileScreenState extends State<GuardProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        showGateSnack(context, 'Could not sign out. Try again.', danger: true);
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final session = AppSession.instance;
    final guard = session.guardProfile;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GateHeader(title: 'Me', showBack: widget.showBack),
            const SizedBox(height: 14),
            Surface(
              child: Row(
                children: [
                  ResidentAvatar(initials: guard?.initials ?? 'G', size: 60),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guard?.fullName ?? session.displayName ?? 'Guard',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: p.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Security Guard',
                            style: TextStyle(
                              color: p.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          session.societyName,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  if (guard?.agencyName != null)
                    _info(
                      p,
                      Icons.business_center_outlined,
                      'Agency',
                      guard!.agencyName!,
                    ),
                  if (guard?.employeeCode != null)
                    _info(
                      p,
                      Icons.badge_outlined,
                      'Badge no.',
                      guard!.employeeCode!,
                    ),
                  if (guard != null) ...[
                    _info(p, Icons.phone_outlined, 'Phone', guard.phone),
                    _info(
                      p,
                      Icons.alternate_email_rounded,
                      'Sign-in email',
                      guard.email,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const GateSectionTitle('On duty'),
            AnimatedBuilder(
              animation: GuardService.instance,
              builder: (context, _) {
                final gate = GuardService.instance.currentGate;
                return Surface(
                  onTap: () => showGateSwitcher(context),
                  child: Row(
                    children: [
                      Icon(Icons.sensor_door_rounded, color: p.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gate?.name ?? 'No gate chosen',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Entries from this phone are recorded at this gate',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Change',
                        style: TextStyle(
                          color: p.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const GateSectionTitle('Appearance'),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: widget.themeController,
              builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    widget.themeController.setMode(s.first),
              ),
            ),
            const SizedBox(height: 20),
            const GateSectionTitle('More'),
            Surface(
              padding: EdgeInsets.zero,
              // ListTile paints its ink on the nearest Material; without this
              // one the Surface's background would hide it.
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('Society notices'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pushNamed(context, '/notices'),
                    ),
                    Divider(height: 1, color: p.hairline),
                    AnimatedBuilder(
                      animation: NotificationsService.instance,
                      builder: (context, _) {
                        final unread =
                            NotificationsService.instance.unreadCount;
                        return ListTile(
                          leading: const Icon(Icons.notifications_none_rounded),
                          title: const Text('Notification history'),
                          trailing: unread > 0
                              ? Badge(label: Text('$unread'))
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              Navigator.pushNamed(context, '/notifications'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _signingOut ? null : _signOut,
                icon: const Icon(Icons.logout_rounded),
                label: Text(_signingOut ? 'Signing out…' : 'Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.danger,
                  side: BorderSide(color: p.danger.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(AppPaletteData p, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.textTertiary),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: p.textTertiary, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
