import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/guard_models.dart';
import '../../models/visitor_models.dart';
import '../../services/app_session.dart';
import '../../services/guard_service.dart';
import '../../services/notifications_service.dart';
import '../../services/security_service.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';
import '../visitors/admin_log_visitor_screen.dart';
import '../visitors/admin_verify_preapproval_screen.dart';
import '../visitors/widgets/live_status_chip.dart';
import 'guard_waiting_screen.dart';
import 'widgets/guard_widgets.dart';

/// The gate's working screen: everything that needs action now, top to
/// bottom — open SOS, the code box, one-tap entry types, visitors waiting
/// on a flat, and who is expected today.
class GuardHomeScreen extends StatefulWidget {
  /// Switches the shell's tab (1 = Inside, 2 = Alerts).
  final ValueChanged<int> onOpenTab;

  const GuardHomeScreen({super.key, required this.onOpenTab});

  @override
  State<GuardHomeScreen> createState() => _GuardHomeScreenState();
}

class _GuardHomeScreenState extends State<GuardHomeScreen> {
  final _codeCtrl = TextEditingController();

  List<VisitorRecord> _waiting = const [];
  List<ExpectedVisitor> _expected = const [];
  List<VisitorRecord> _inside = const [];
  String? _expectedError;
  bool _loading = true;

  StreamSubscription<VisitorLiveEvent>? _liveSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _liveSub = VisitorsService.instance.onVisitorEvent.listen((_) {
      // A busy gate produces bursts; one reload per burst is enough.
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 600),
        () => _load(silent: true),
      );
    });
    VisitorsService.instance.addListener(_onVisitorsTick);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _debounce?.cancel();
    VisitorsService.instance.removeListener(_onVisitorsTick);
    _codeCtrl.dispose();
    super.dispose();
  }

  /// While the socket is down the service ticks on a timer; follow it.
  void _onVisitorsTick() {
    if (mounted && !VisitorsService.instance.isLive) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final service = GuardService.instance;

    final results = await Future.wait<Object?>([
      service.fetchWaitingRequests().catchError((_) => <VisitorRecord>[]),
      service.fetchInside().catchError((_) => <VisitorRecord>[]),
      service
          .fetchExpectedVisitors()
          .then<Object?>((v) => v)
          .catchError((Object e) => e),
    ]);

    if (!mounted) return;
    setState(() {
      _waiting = results[0] as List<VisitorRecord>;
      _inside = results[1] as List<VisitorRecord>;
      final exp = results[2];
      if (exp is List<ExpectedVisitor>) {
        _expected = exp;
        _expectedError = null;
      } else {
        _expected = const [];
        _expectedError = exp == null ? null : gateErrorText(exp);
      }
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final societyId = AppSession.instance.societyId;
    await Future.wait([
      _load(silent: true),
      if (societyId != null)
        SecurityService.instance.refreshActiveAlerts(societyId),
      GuardService.instance.loadGates(),
    ]);
  }

  void _verify([String? code]) {
    final typed = (code ?? _codeCtrl.text).trim();
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminVerifyPreapprovalScreen(
          initialCode: typed.isEmpty ? null : typed,
        ),
      ),
    ).then((_) {
      _codeCtrl.clear();
      _load(silent: true);
    });
  }

  void _newEntry(VisitorCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => AdminLogVisitorScreen(
          initialCategory: category,
          // Straight on to the waiting screen: the guard's next job is to
          // hold the visitor until the flat answers.
          onLogged: (visitorId) => Navigator.pushReplacement(
            routeContext,
            MaterialPageRoute(
              builder: (_) => GuardWaitingScreen(visitorId: visitorId),
            ),
          ),
        ),
      ),
    ).then((_) => _load(silent: true));
  }

  void _openWaiting(VisitorRecord v) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GuardWaitingScreen(visitorId: v.id)),
    ).then((_) => _load(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final now = DateTime.now();
    final overstaying = _inside.where((v) => isOverstaying(v, now)).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _header(p),
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: SecurityService.instance,
                builder: (context, _) {
                  final open = SecurityService.instance.activeSosAlerts
                      .where((a) => a.isOpen)
                      .toList();
                  if (open.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: open.map((a) => GateSosCard(alert: a)).toList(),
                  );
                },
              ),
              _codeBox(p),
              const SizedBox(height: 18),
              const GateSectionTitle('New entry'),
              _entryGrid(p),
              const SizedBox(height: 22),
              GateSectionTitle(
                'Waiting for resident (${_waiting.length})',
                trailing: _loading ? null : 'Refresh',
                onTrailing: () => _load(),
              ),
              if (_loading && _waiting.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_waiting.isEmpty)
                const GateEmptyNote(
                  icon: Icons.hourglass_empty_rounded,
                  text: 'Nobody is waiting on a flat right now.',
                )
              else
                ..._waiting.map((v) => _waitingRow(p, v)),
              const SizedBox(height: 22),
              _insideSummary(p, overstaying),
              const SizedBox(height: 22),
              GateSectionTitle('Expected today (${_expected.length})'),
              if (_expectedError != null)
                GateEmptyNote(
                  icon: Icons.cloud_off_rounded,
                  text: 'Could not load expected visitors: $_expectedError',
                )
              else if (_expected.isEmpty)
                const GateEmptyNote(
                  icon: Icons.event_available_outlined,
                  text: 'No pre-approved visitors for the next few hours.',
                )
              else
                ..._expected.map((e) => _expectedRow(p, e, now)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppPaletteData p) {
    final session = AppSession.instance;
    final guard = session.guardProfile;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.societyName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.primary,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                guard != null ? 'On duty · ${guard.firstName}' : 'On duty',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: GuardService.instance,
                builder: (context, _) => GateChip(
                  label:
                      GuardService.instance.currentGate?.name ?? 'Choose gate',
                  onTap: () => showGateSwitcher(context),
                ),
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: VisitorsService.instance,
          builder: (context, _) => LiveStatusChip(
            status: VisitorsService.instance.liveStatus,
            onRefresh: _refresh,
          ),
        ),
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: NotificationsService.instance,
          builder: (context, _) {
            final unread = NotificationsService.instance.unreadCount;
            return Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: IconButton(
                onPressed: () => Navigator.pushNamed(context, '/notifications'),
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                style: IconButton.styleFrom(
                  backgroundColor: p.card,
                  side: BorderSide(color: p.hairline),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// The code box comes first: checking a pass is what a gate does most.
  Widget _codeBox(AppPaletteData p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visitor has a pass?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: p.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 8,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _verify(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
                    TextInputFormatter.withFunction(
                      (_, v) => v.copyWith(text: v.text.toUpperCase()),
                    ),
                  ],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Enter code',
                    hintStyle: TextStyle(
                      fontFamily: null,
                      fontSize: 16,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w500,
                      color: p.textTertiary,
                    ),
                    prefixIcon: const Icon(Icons.pin_rounded),
                    filled: true,
                    fillColor: p.cardMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 58,
                child: FilledButton(
                  onPressed: () => _verify(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text(
                    'Verify',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryGrid(AppPaletteData p) {
    final tiles = <Widget>[
      GateActionTile(
        icon: VisitorCategory.guest.icon,
        label: 'Guest',
        color: VisitorCategory.guest.color,
        onTap: () => _newEntry(VisitorCategory.guest),
      ),
      GateActionTile(
        icon: VisitorCategory.delivery.icon,
        label: 'Delivery',
        color: VisitorCategory.delivery.color,
        onTap: () => _newEntry(VisitorCategory.delivery),
      ),
      GateActionTile(
        icon: VisitorCategory.cab.icon,
        label: 'Cab',
        color: VisitorCategory.cab.color,
        onTap: () => _newEntry(VisitorCategory.cab),
      ),
      GateActionTile(
        icon: Icons.handyman_rounded,
        label: 'Service',
        color: VisitorCategory.others.color,
        onTap: () => _newEntry(VisitorCategory.others),
      ),
      GateActionTile(
        icon: Icons.directions_car_filled_rounded,
        label: 'Vehicle',
        color: p.featureColor(1),
        onTap: () => Navigator.pushNamed(context, '/gate-vehicles'),
      ),
      GateActionTile(
        icon: Icons.emergency_rounded,
        label: 'Emergency',
        color: p.danger,
        onTap: () => widget.onOpenTab(2),
      ),
    ];

    // A fixed tile height rather than an aspect ratio: on a 320 px phone
    // a square tile is too short for the icon plus its label.
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 96,
      ),
      children: tiles,
    );
  }

  Widget _waitingRow(AppPaletteData p, VisitorRecord v) {
    final waited = DateTime.now().difference(v.createdAt.toLocal());
    final late = waited > const Duration(minutes: 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openWaiting(v),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: p.warning.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: v.category.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(v.category.icon, color: v.category.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.visitorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${v.flatDisplay} · ${v.category.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ElapsedText(
                      since: v.createdAt,
                      style: TextStyle(
                        color: p.warning,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      late ? 'Tap to call' : 'Waiting',
                      style: TextStyle(color: p.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _insideSummary(AppPaletteData p, int overstaying) {
    final color = overstaying > 0 ? p.warning : p.success;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onOpenTab(1),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.groups_2_rounded, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_inside.length} visitor${_inside.length == 1 ? '' : 's'} inside',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      overstaying > 0
                          ? '$overstaying past their time · check them out on exit'
                          : 'Check visitors out as they leave',
                      style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expectedRow(AppPaletteData p, ExpectedVisitor e, DateTime now) {
    final activeNow = e.isActiveAt(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // No code in the list on purpose — ask the visitor for it.
          onTap: () => _verify(),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(e.category.icon, color: e.category.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.groupSize > 0
                            ? '${e.visitorName} +${e.groupSize}'
                            : e.visitorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          e.flatDisplay,
                          if ((e.companyOrContext ?? '').isNotEmpty)
                            e.companyOrContext!,
                          if ((e.vehicleNumber ?? '').isNotEmpty)
                            e.vehicleNumber!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  e.windowLabel(now),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: activeNow ? p.success : p.textTertiary,
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
