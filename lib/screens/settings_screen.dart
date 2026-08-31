import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController themeController;

  const SettingsScreen({super.key, required this.themeController});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _billAlerts = true;
  bool _announcementAlerts = true;
  bool _gateAlerts = false;
  bool _directoryVisibility = true;
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not sign out. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _showEmergencyContactsModal(BuildContext context, AppPaletteData p) {
    final societyName = AppSession.instance.societyName;
    showModalBottomSheet(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.danger.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shield_rounded, color: p.danger, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency & Gate Contacts',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          societyName,
                          style: TextStyle(fontSize: 13, color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _emergencyTile(
                p,
                icon: Icons.meeting_room_outlined,
                title: 'Main Gate Security Cabin',
                subtitle: 'Intercom 100 · 24/7 Gate Guard',
                phone: '+91 98765 00100',
              ),
              const SizedBox(height: 10),
              _emergencyTile(
                p,
                icon: Icons.business_outlined,
                title: 'Society Facility Manager',
                subtitle: 'Office hours 9 AM - 6 PM',
                phone: '+91 98765 00200',
              ),
              const SizedBox(height: 10),
              _emergencyTile(
                p,
                icon: Icons.elevator_outlined,
                title: 'Lift Emergency & Breakdown',
                subtitle: 'Otis 24/7 Technical Response',
                phone: '1800 123 4567',
              ),
              const SizedBox(height: 10),
              _emergencyTile(
                p,
                icon: Icons.local_police_outlined,
                title: 'Local Police & Ambulance',
                subtitle: 'National Emergency Response (112)',
                phone: '112',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emergencyTile(
    AppPaletteData p, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String phone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: p.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: p.textPrimary),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: p.textTertiary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_rounded, size: 20),
            color: p.primary,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied $phone to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;
        final isAdmin = session.isAdmin;
        final pendingCount = session.pendingApprovalsCount;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'Settings',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Appearance and preferences',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                _groupTitle(context, 'Account'),
                const SizedBox(height: 10),
                _accountCard(context, p),
                const SizedBox(height: 24),
                _groupTitle(context, 'Appearance'),
                const SizedBox(height: 10),
                _themeCard(context, p),
                const SizedBox(height: 24),
                _groupTitle(context, 'Notifications'),
                const SizedBox(height: 10),
                _card(
                  context,
                  p,
                  children: [
                    _switchRow(
                      context,
                      p,
                      icon: Icons.receipt_long_outlined,
                      title: 'Bills & receipts',
                      subtitle: 'Maintenance invoices and payment confirmations',
                      value: _billAlerts,
                      onChanged: (v) => setState(() => _billAlerts = v),
                    ),
                    _divider(p),
                    _switchRow(
                      context,
                      p,
                      icon: Icons.campaign_outlined,
                      title: 'Announcements',
                      subtitle: 'New board notices and community alerts',
                      value: _announcementAlerts,
                      onChanged: (v) => setState(() => _announcementAlerts = v),
                    ),
                    _divider(p),
                    _switchRow(
                      context,
                      p,
                      icon: Icons.sensor_door_outlined,
                      title: 'Gate activity',
                      subtitle: 'Visitor and delivery entries',
                      value: _gateAlerts,
                      onChanged: (v) => setState(() => _gateAlerts = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Role-Specific Section
                if (isAdmin) ...[
                  _groupTitle(context, 'Society Management (Admin)'),
                  const SizedBox(height: 10),
                  _card(
                    context,
                    p,
                    children: [
                      _navRow(
                        context,
                        p,
                        icon: Icons.how_to_reg_outlined,
                        title: 'Resident Approvals',
                        subtitle: pendingCount > 0
                            ? '$pendingCount pending join request(s)'
                            : 'Review and approve flat applicants',
                        trailingBadge: pendingCount > 0 ? '$pendingCount' : null,
                        onTap: () => Navigator.pushNamed(context, '/admin-approvals'),
                      ),
                      _divider(p),
                      _navRow(
                        context,
                        p,
                        icon: Icons.domain_outlined,
                        title: 'Blocks & Flats Register',
                        subtitle: 'Configure towers, floors, and unit parameters',
                        onTap: () => Navigator.pushNamed(context, '/flats-management'),
                      ),
                      _divider(p),
                      _navRow(
                        context,
                        p,
                        icon: Icons.people_outline_rounded,
                        title: 'Resident Directory',
                        subtitle: 'View and manage society occupants',
                        onTap: () => Navigator.pushNamed(context, '/directory'),
                      ),
                    ],
                  ),
                ] else ...[
                  _groupTitle(context, 'My Residence & Community'),
                  const SizedBox(height: 10),
                  _card(
                    context,
                    p,
                    children: [
                      _navRow(
                        context,
                        p,
                        icon: Icons.home_outlined,
                        title: 'My Flat & Household',
                        subtitle: 'Unit details, family members & tenants',
                        onTap: () => Navigator.pushNamed(context, '/my-flat'),
                      ),
                      _divider(p),
                      _navRow(
                        context,
                        p,
                        icon: Icons.directions_car_outlined,
                        title: 'Registered Vehicles',
                        subtitle: 'Parking slots & vehicle tags',
                        onTap: () => Navigator.pushNamed(context, '/profile'),
                      ),
                      _divider(p),
                      _navRow(
                        context,
                        p,
                        icon: Icons.shield_outlined,
                        title: 'Emergency & Gate Contacts',
                        subtitle: 'Gate security, facility manager & SOS',
                        onTap: () => _showEmergencyContactsModal(context, p),
                      ),
                      _divider(p),
                      _switchRow(
                        context,
                        p,
                        icon: Icons.visibility_outlined,
                        title: 'Directory Visibility',
                        subtitle: 'Show phone number to verified neighbors',
                        value: _directoryVisibility,
                        onChanged: (v) => setState(() => _directoryVisibility = v),
                      ),
                      _divider(p),
                      _navRow(
                        context,
                        p,
                        icon: Icons.support_agent_outlined,
                        title: 'Helpdesk & Complaints',
                        subtitle: 'Raise a ticket or report an issue',
                        onTap: () => Navigator.pushNamed(context, '/complaints'),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                _groupTitle(context, 'About Society'),
                const SizedBox(height: 10),
                _card(
                  context,
                  p,
                  children: [
                    _infoRow(context, p, 'Society', session.societyName),
                    if (session.societyCity != null && session.societyCity!.isNotEmpty) ...[
                      _divider(p),
                      _infoRow(context, p, 'City / Region', session.societyCity!),
                    ],
                    _divider(p),
                    _infoRow(context, p, 'App Version', '1.0.0'),
                    _divider(p),
                    _infoRow(context, p, 'Platform', 'Flutter · Supabase'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _groupTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  Widget _accountCard(BuildContext context, AppPaletteData p) {
    String title = 'Signed in as';
    String subtitle = 'Signed in';
    try {
      final session = AppSession.instance;
      final displayName = session.displayName;
      String? email;
      try {
        email = Supabase.instance.client.auth.currentUser?.email;
      } catch (_) {
        email = null;
      }
      if (displayName != null && displayName.trim().isNotEmpty) {
        title = displayName;
        subtitle = email ?? displayName;
        // If subtitle is same as title (e.g., derived from email local part), keep single line
        if (email != null && email.isNotEmpty && displayName.toLowerCase() == email.split('@').first.toLowerCase()) {
          subtitle = email;
        }
      } else if (email != null && email.isNotEmpty) {
        // No displayName, keep generic title and show email as subtitle
        title = 'Signed in as';
        subtitle = email;
      } else {
        // Test / no auth
        title = 'Test user';
        subtitle = 'test@example.com';
      }
    } catch (_) {
      title = 'Test user';
      subtitle = 'test@example.com';
    }

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHead(context, p,
              icon: Icons.person_outline_rounded, title: title, subtitle: subtitle),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _signingOut ? null : _signOut,
              icon: _signingOut
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.danger,
                side: BorderSide(color: p.danger.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeCard(BuildContext context, AppPaletteData p) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeController,
      builder: (context, mode, _) {
        return Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHead(context, p,
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  subtitle: 'Follow your device or choose a look'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) =>
                      widget.themeController.setMode(selection.first),
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, AppPaletteData p,
      {required List<Widget> children}) {
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }

  Widget _sectionHead(
    BuildContext context,
    AppPaletteData p, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: p.primary.withValues(alpha: 0.12),
            child: Icon(icon, size: 19, color: p.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(
    BuildContext context,
    AppPaletteData p, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: p.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: p.primary,
          ),
        ],
      ),
    );
  }

  Widget _navRow(
    BuildContext context,
    AppPaletteData p, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? trailingBadge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: p.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                        ),
                  ),
                ],
              ),
            ),
            if (trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE68A00),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  trailingBadge,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, AppPaletteData p, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: p.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _divider(AppPaletteData p) =>
      Divider(height: 1, color: p.hairline, indent: 16, endIndent: 16);
}