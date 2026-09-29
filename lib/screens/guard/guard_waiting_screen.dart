import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/guard_models.dart';
import '../../models/visitor_models.dart';
import '../../services/guard_service.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/text_input_dialog.dart';
import '../visitors/widgets/live_status_chip.dart';
import 'widgets/guard_widgets.dart';

/// The screen a guard holds while a walk-in waits for the flat to answer.
///
/// Pending   → live timer; after [_callAfter] the guard may call the flat,
///             and only after a logged call record what the resident said.
/// Approved  → ALLOW ENTRY, one tap to check in.
/// Denied    → DO NOT ALLOW, with the resident's reason.
class GuardWaitingScreen extends StatefulWidget {
  final String visitorId;

  const GuardWaitingScreen({super.key, required this.visitorId});

  @override
  State<GuardWaitingScreen> createState() => _GuardWaitingScreenState();
}

class _GuardWaitingScreenState extends State<GuardWaitingScreen> {
  /// How long the push gets before the gate may pick up the phone. ADDA
  /// escalates at 55 s; a minute is the same idea without an IVR bridge.
  static const _callAfter = Duration(seconds: 60);

  VisitorRecord? _visitor;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _callPlaced = false;

  StreamSubscription<VisitorLiveEvent>? _liveSub;
  Timer? _tick;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _liveSub = VisitorsService.instance.onVisitorEvent.listen((event) {
      if (event.visitor.id != widget.visitorId || !mounted) return;
      final before = _visitor?.status;
      setState(() => _visitor = event.visitor);
      if (before == VisitorStatus.pendingApproval &&
          event.visitor.status != VisitorStatus.pendingApproval) {
        HapticFeedback.heavyImpact();
      }
    });
    // Drives the "call the flat" unlock; the timer text ticks on its own.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && (_visitor?.isPending ?? false)) setState(() {});
    });
    // Belt and braces for when the socket is down.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!VisitorsService.instance.isLive && (_visitor?.isPending ?? false)) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final v = await VisitorsService.instance.fetchVisitorDetail(
        widget.visitorId,
      );
      // A call placed before the guard stepped away still counts on the
      // server for 15 minutes; don't make them ring again to record it.
      if (v != null && v.isPending && !_callPlaced) {
        _callPlaced = await GuardService.instance.hasRecentCall(v.id);
      }
      if (!mounted) return;
      setState(() {
        _visitor = v;
        _error = v == null ? 'This visitor entry could not be found.' : null;
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

  bool get _canCall {
    final v = _visitor;
    if (v == null || !v.isPending) return false;
    return DateTime.now().difference(v.createdAt.toLocal()) >= _callAfter;
  }

  Future<void> _call() async {
    final v = _visitor;
    if (v == null) return;
    final placed = await callFlatFromGate(
      context,
      flatId: v.flatId,
      reason: 'visitor_no_response',
      visitorId: v.id,
    );
    if (placed && mounted) setState(() => _callPlaced = true);
  }

  Future<void> _decide(GateDecision decision) async {
    final v = _visitor;
    if (v == null || _busy) return;

    String? note;
    if (decision == GateDecision.denied) {
      note = await _askReason();
      if (note == null) return;
    } else {
      final ok = await _confirm(decision, v);
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await GuardService.instance.resolveGateRequest(
        visitorId: v.id,
        decision: decision,
        note: note,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) showGateSnack(context, gateErrorText(e), danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(GateDecision decision, VisitorRecord v) {
    final approved = decision == GateDecision.approved;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approved ? 'Resident said yes?' : 'Turn the visitor away?'),
        content: Text(
          approved
              ? 'This records that ${v.flatDisplay} approved ${v.visitorName} on the phone. The flat is told it was recorded by you.'
              : 'Nobody answered for ${v.visitorName}. The flat is told the visitor was turned away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approved ? 'Yes, allow' : 'Turn away'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askReason() => showTextInputDialog(
    context,
    title: 'Resident refused',
    hint: 'What did they say? e.g. "Not expecting anyone"',
    confirmLabel: 'Record',
    requiredMessage: 'Note what the resident said',
  );

  Future<void> _checkIn() async {
    final v = _visitor;
    if (v == null || _busy) return;
    setState(() => _busy = true);
    try {
      await VisitorsService.instance.checkInVisitor(
        v.id,
        entryGate: GuardService.instance.currentGate?.name,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showGateSnack(context, '${v.visitorName} checked in', success: true);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showGateSnack(context, gateErrorText(e), danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final v = _visitor;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: p.card,
                      side: BorderSide(color: p.hairline),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gate request',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : v == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error ?? 'Not found',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          _statusBanner(p, v),
                          const SizedBox(height: 14),
                          GateVisitorSummary(visitor: v),
                          const SizedBox(height: 18),
                          ..._actions(p, v),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(AppPaletteData p, VisitorRecord v) {
    final (
      Color color,
      IconData icon,
      String title,
      String sub,
    ) = switch (v.status) {
      VisitorStatus.pendingApproval => (
        p.warning,
        Icons.hourglass_top_rounded,
        'Waiting for ${v.flatDisplay}',
        'Keep the visitor at the gate until the flat answers.',
      ),
      VisitorStatus.approved => (
        p.success,
        Icons.check_circle_rounded,
        'ALLOW ENTRY',
        v.approvedAt != null
            ? 'Approved by the flat${v.isApprovedOnCall ? ' on the phone' : ''} · ${gateTime(v.approvedAt)}'
            : 'Approved by the flat',
      ),
      VisitorStatus.denied => (
        p.danger,
        Icons.block_rounded,
        'DO NOT ALLOW',
        (v.deniedReason ?? '').isNotEmpty
            ? 'Reason: ${v.deniedReason}'
            : 'The flat refused this visitor.',
      ),
      VisitorStatus.checkedIn => (
        const Color(0xFF16A34A),
        Icons.login_rounded,
        'Checked in',
        'Entered at ${gateTime(v.checkedInAt)}${(v.entryGate ?? '').isNotEmpty ? ' · ${v.entryGate}' : ''}',
      ),
      _ => (
        p.textTertiary,
        Icons.info_outline_rounded,
        v.status.label,
        'This request is closed.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: v.isPending ? 18 : 24,
                    letterSpacing: v.isPending ? 0 : 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (v.isPending)
            ElapsedText(
              since: v.createdAt,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actions(AppPaletteData p, VisitorRecord v) {
    if (v.isApproved) {
      return [
        _bigButton(
          label: 'Check in now',
          icon: Icons.login_rounded,
          color: p.success,
          onTap: _busy ? null : _checkIn,
        ),
      ];
    }

    if (!v.isPending) {
      return [
        _bigButton(
          label: 'Done',
          icon: Icons.check_rounded,
          color: p.primary,
          onTap: () => Navigator.pop(context),
        ),
      ];
    }

    final canCall = _canCall;
    return [
      if (!canCall)
        GateEmptyNote(
          icon: Icons.notifications_active_outlined,
          text:
              'The flat has been notified. You can call them if there is no answer in a minute.',
        ),
      if (canCall) ...[
        _bigButton(
          label: _callPlaced ? 'Call again' : 'No answer? Call the flat',
          icon: Icons.phone_in_talk_rounded,
          color: const Color(0xFF00897B),
          onTap: _busy ? null : _call,
        ),
        if (_callPlaced) ...[
          const SizedBox(height: 18),
          const GateSectionTitle('What did the resident say?'),
          Row(
            children: [
              Expanded(
                child: _bigButton(
                  label: 'Allow',
                  icon: Icons.check_rounded,
                  color: p.success,
                  onTap: _busy ? null : () => _decide(GateDecision.approved),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigButton(
                  label: 'Refused',
                  icon: Icons.close_rounded,
                  color: p.danger,
                  onTap: _busy ? null : () => _decide(GateDecision.denied),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _decide(GateDecision.expired),
          icon: const Icon(Icons.do_not_disturb_on_outlined),
          label: const Text('Nobody answered — turn away'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: p.textSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _bigButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 58,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Visitor summary for the waiting screen: photo large enough to compare
/// against the face at the barrier.
class GateVisitorSummary extends StatelessWidget {
  final VisitorRecord visitor;

  const GateVisitorSummary({super.key, required this.visitor});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final v = visitor;
    final photo = v.visitorPhotoUrl;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 88,
              height: 88,
              child: (photo != null && photo.startsWith('http'))
                  ? Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(v),
                    )
                  : _placeholder(v),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.visitorName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    v.category.label,
                    if ((v.companyOrContext ?? '').isNotEmpty)
                      v.companyOrContext!,
                  ].join(' · '),
                  style: TextStyle(
                    color: v.category.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _line(p, Icons.apartment_rounded, v.flatDisplay),
                if ((v.vehicleNumber ?? '').isNotEmpty)
                  _line(p, Icons.directions_car_outlined, v.vehicleNumber!),
                if ((v.visitorPhone ?? '').isNotEmpty)
                  _line(p, Icons.phone_outlined, v.visitorPhone!),
                _line(
                  p,
                  Icons.schedule_rounded,
                  'Logged ${gateTime(v.createdAt)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(VisitorRecord v) => Container(
    color: v.category.color.withValues(alpha: 0.12),
    child: Icon(v.category.icon, color: v.category.color, size: 36),
  );

  Widget _line(AppPaletteData p, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 15, color: p.textTertiary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
