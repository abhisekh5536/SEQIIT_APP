import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/security_models.dart';
import '../../services/app_session.dart';
import '../../services/notifications_service.dart';
import '../../services/security_service.dart';
import '../../theme/app_theme.dart';
import 'widgets/guard_widgets.dart';

/// SOS alerts and the numbers the gate rings in an emergency.
class GuardAlertsScreen extends StatefulWidget {
  final bool showBack;

  const GuardAlertsScreen({super.key, this.showBack = false});

  @override
  State<GuardAlertsScreen> createState() => _GuardAlertsScreenState();
}

class _GuardAlertsScreenState extends State<GuardAlertsScreen> {
  List<SosAlert> _recent = const [];
  List<EmergencyContact> _contacts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    NotificationsService.instance.markModuleAsRead('sos_alert');
    SecurityService.instance.addListener(_onSecurityChanged);
    _load();
  }

  @override
  void dispose() {
    SecurityService.instance.removeListener(_onSecurityChanged);
    super.dispose();
  }

  /// An alert opened or closed somewhere: the "recent" list moves too.
  void _onSecurityChanged() {
    if (mounted) _loadRecent();
  }

  Future<void> _load() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        SecurityService.instance.fetchGateSosAlerts(
          societyId,
          includeClosed: true,
        ),
        SecurityService.instance.fetchContacts(societyId, activeOnly: true),
        SecurityService.instance
            .refreshActiveAlerts(societyId)
            .then((_) => true),
      ]);
      if (!mounted) return;
      setState(() {
        _recent = (results[0] as List<SosAlert>)
            .where((a) => !a.isOpen)
            .toList();
        _contacts = results[1] as List<EmergencyContact>;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = gateErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadRecent() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return;
    try {
      final all = await SecurityService.instance.fetchGateSosAlerts(
        societyId,
        includeClosed: true,
      );
      if (mounted) {
        setState(() => _recent = all.where((a) => !a.isOpen).toList());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final society = _contacts.where((c) => !c.isGlobal).toList();
    final national = _contacts.where((c) => c.isGlobal).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              GateHeader(
                title: 'Alerts',
                subtitle: 'SOS from residents and emergency numbers',
                showBack: widget.showBack,
              ),
              const SizedBox(height: 14),
              const GateSectionTitle('Active SOS'),
              AnimatedBuilder(
                animation: SecurityService.instance,
                builder: (context, _) {
                  final open = SecurityService.instance.activeSosAlerts
                      .where((a) => a.isOpen)
                      .toList();
                  if (open.isEmpty) {
                    return GateEmptyNote(
                      icon: Icons.verified_user_outlined,
                      text: _loading
                          ? 'Checking…'
                          : 'No active emergencies. A new SOS rings this phone.',
                    );
                  }
                  return Column(
                    children: open.map((a) => GateSosCard(alert: a)).toList(),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                GateEmptyNote(icon: Icons.cloud_off_rounded, text: _error!),
              ],
              const SizedBox(height: 22),
              const GateSectionTitle('Emergency numbers'),
              if (_loading && _contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (society.isEmpty)
                  const GateEmptyNote(
                    icon: Icons.contact_phone_outlined,
                    text: 'The society has not listed its own contacts yet.',
                  )
                else
                  ...society.map((c) => _contactRow(p, c)),
                if (national.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...national.map((c) => _contactRow(p, c, national: true)),
                ],
              ],
              const SizedBox(height: 22),
              const GateSectionTitle('Last 7 days'),
              if (_recent.isEmpty)
                const GateEmptyNote(
                  icon: Icons.history_rounded,
                  text: 'No closed alerts in the last week.',
                )
              else
                ..._recent.map((a) => _recentRow(p, a)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactRow(
    AppPaletteData p,
    EmergencyContact c, {
    bool national = false,
  }) {
    final accent = national ? p.danger : const Color(0xFF00897B);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                SecurityIconHelper.getIconData(c.categoryIconKey),
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    [
                      if ((c.designation ?? '').isNotEmpty) c.designation!,
                      c.availability,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                final ok = await SecurityService.instance.launchCall(
                  phoneNumber: c.phoneNumber,
                );
                if (!ok && mounted) {
                  showGateSnack(
                    context,
                    'Could not open the dialer for ${c.phoneNumber}',
                    danger: true,
                  );
                }
              },
              icon: const Icon(Icons.call_rounded, size: 18),
              label: Text(c.phoneNumber),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentRow(AppPaletteData p, SosAlert a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openSosAlert(context, a),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(a.alertType.icon, color: a.alertType.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a.formattedFlat} · ${a.alertType.shortLabel}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        DateFormat('d MMM, h:mm a').format(a.createdAt),
                        style: TextStyle(color: p.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  a.status.label,
                  style: TextStyle(
                    color: a.status.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
