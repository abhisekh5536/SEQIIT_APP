import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/guard_models.dart';
import '../../models/visitor_models.dart';
import '../../services/guard_service.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';
import '../vehicles/guard/vehicle_gate_lookup_screen.dart';
import '../vehicles/widgets/vehicle_parking_widgets.dart';
import '../visitors/visitor_detail_screen.dart';
import '../visitors/widgets/live_status_chip.dart';
import '../visitors/widgets/visitor_card.dart';
import 'guard_waiting_screen.dart';
import 'widgets/guard_widgets.dart';

/// The gate register: who is inside right now, today's log, and the
/// vehicle register.
class GuardRegisterScreen extends StatefulWidget {
  final bool showBack;

  const GuardRegisterScreen({super.key, this.showBack = false});

  @override
  State<GuardRegisterScreen> createState() => _GuardRegisterScreenState();
}

class _GuardRegisterScreenState extends State<GuardRegisterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _searchCtrl = TextEditingController();

  List<VisitorRecord> _inside = const [];
  List<VisitorRecord> _today = const [];
  String? _error;
  bool _loading = true;
  final Set<String> _checkingOut = {};

  StreamSubscription<VisitorLiveEvent>? _liveSub;
  Timer? _debounce;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _liveSub = VisitorsService.instance.onVisitorEvent.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 600),
        () => _load(silent: true),
      );
    });
    // Overstay flags depend on the clock, not only on data changes.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _debounce?.cancel();
    _clock?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        GuardService.instance.fetchInside(),
        GuardService.instance.fetchTodayLog(),
      ]);
      if (!mounted) return;
      setState(() {
        _inside = results[0];
        _today = results[1];
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

  List<VisitorRecord> _filter(List<VisitorRecord> list) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((v) {
      return v.visitorName.toLowerCase().contains(q) ||
          (v.flatNumber?.toLowerCase().contains(q) ?? false) ||
          (v.blockName?.toLowerCase().contains(q) ?? false) ||
          (v.vehicleNumber?.toLowerCase().contains(q) ?? false) ||
          (v.companyOrContext?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _checkOut(VisitorRecord v) async {
    if (_checkingOut.contains(v.id)) return;
    setState(() => _checkingOut.add(v.id));
    try {
      await VisitorsService.instance.checkOutVisitor(v.id);
      HapticFeedback.lightImpact();
      if (mounted) showGateSnack(context, '${v.visitorName} checked out');
      await _load(silent: true);
    } catch (e) {
      if (mounted) showGateSnack(context, gateErrorText(e), danger: true);
    } finally {
      if (mounted) setState(() => _checkingOut.remove(v.id));
    }
  }

  void _open(VisitorRecord v) {
    final route = v.isPending && v.isGateRequest
        ? MaterialPageRoute(builder: (_) => GuardWaitingScreen(visitorId: v.id))
        : MaterialPageRoute(
            builder: (_) => VisitorDetailScreen(visitorId: v.id),
          );
    Navigator.push(context, route).then((_) => _load(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: GateHeader(
                title: 'Gate register',
                subtitle:
                    GuardService.instance.currentGate?.name ??
                    'Today at the gate',
                showBack: widget.showBack,
                actions: [
                  AnimatedBuilder(
                    animation: VisitorsService.instance,
                    builder: (context, _) => LiveStatusChip(
                      status: VisitorsService.instance.liveStatus,
                      onRefresh: _load,
                    ),
                  ),
                ],
              ),
            ),
            SegmentedTabs(
              controller: _tabs,
              labels: ['Inside (${_inside.length})', 'Today', 'Vehicles'],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _visitorList(p, inside: true),
                  _visitorList(p, inside: false),
                  const VehicleGateLookupScreen(showAppBar: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visitorList(AppPaletteData p, {required bool inside}) {
    final now = DateTime.now();
    final list = _filter(inside ? _inside : _today);

    Widget body;
    if (_loading && list.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = GateEmptyNote(
        icon: Icons.cloud_off_rounded,
        text: 'Could not load the register: $_error',
      );
    } else if (list.isEmpty) {
      body = GateEmptyNote(
        icon: inside ? Icons.door_front_door_outlined : Icons.history_rounded,
        text: _searchCtrl.text.isNotEmpty
            ? 'No match for "${_searchCtrl.text.trim()}".'
            : inside
            ? 'Nobody is checked in right now.'
            : 'No visitors logged today yet.',
      );
    } else {
      body = Column(
        children: list.map((v) {
          final over = isOverstaying(v, now);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VisitorCard(
                  visitor: v,
                  showCode: false,
                  borderColor: over ? p.warning : null,
                  onTap: () => _open(v),
                  trailing: inside ? _outButton(p, v) : null,
                ),
                if (inside)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text(
                      over
                          ? 'In since ${gateTime(v.checkedInAt)} · ${_overBy(v, now)}'
                          : 'In since ${gateTime(v.checkedInAt)}${(v.entryGate ?? '').isNotEmpty ? ' · ${v.entryGate}' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: over ? FontWeight.w800 : FontWeight.w500,
                        color: over ? p.warning : p.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search name, flat or vehicle',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(_searchCtrl.clear),
                    ),
              isDense: true,
              filled: true,
              fillColor: p.card,
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
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  String _overBy(VisitorRecord v, DateTime now) {
    final limitEnd =
        v.validUntil ?? v.checkedInAt!.add(overstayLimitFor(v.category));
    return overstayLabel(now.difference(limitEnd));
  }

  Widget _outButton(AppPaletteData p, VisitorRecord v) {
    final busy = _checkingOut.contains(v.id);
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: busy ? null : () => _checkOut(v),
        style: FilledButton.styleFrom(
          backgroundColor: p.danger,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('OUT', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}
