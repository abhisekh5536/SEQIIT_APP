import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

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
            _groupTitle(context, 'About'),
            const SizedBox(height: 10),
            _card(
              context,
              p,
              children: [
                _infoRow(context, p, 'Version', '1.0.0'),
                _divider(p),
                _infoRow(context, p, 'Society', 'Sunrise Heights'),
                _divider(p),
                _infoRow(context, p, 'Built with', 'Flutter'),
              ],
            ),
          ],
        ),
      ),
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