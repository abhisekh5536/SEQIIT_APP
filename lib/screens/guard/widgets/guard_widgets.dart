import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../models/security_models.dart';
import '../../../services/guard_service.dart';
import '../../../services/security_service.dart';
import '../../../theme/app_theme.dart';
import '../../security/widgets/admin_sos_alert_dialog.dart';

/// Strips Dart's "Exception: " prefix so the server's own words reach the
/// guard.
String gateErrorText(Object e) => e.toString().replaceFirst(
  RegExp(r'^(Exception|PostgrestException):\s*'),
  '',
);

void showGateSnack(
  BuildContext context,
  String message, {
  bool danger = false,
  bool success = false,
}) {
  final p = AppTheme.paletteFor(Theme.of(context).brightness);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger
            ? p.danger
            : success
            ? p.success
            : null,
      ),
    );
}

/// Dials a flat through `guard_call_flat`: the number comes from the server
/// one call at a time, is logged, and is never shown on screen.
///
/// Returns true when a call was placed, so callers can unlock the
/// "resident said yes / no" step that depends on a logged call.
Future<bool> callFlatFromGate(
  BuildContext context, {
  required String flatId,
  String reason = 'other',
  String? visitorId,
}) async {
  HapticFeedback.lightImpact();
  try {
    final res = await GuardService.instance.callFlat(
      flatId: flatId,
      reason: reason,
      visitorId: visitorId,
    );
    if (!context.mounted) return true;
    if (!res.dialerOpened) {
      showGateSnack(
        context,
        'Call logged, but this phone could not open the dialer.',
        danger: true,
      );
    } else if (res.residentFirstName != null) {
      showGateSnack(context, 'Calling ${res.residentFirstName}…');
    }
    return true;
  } catch (e) {
    if (context.mounted) showGateSnack(context, gateErrorText(e), danger: true);
    return false;
  }
}

/// Opens the SOS dialog for [alert]. Shared by the home card, the alerts
/// tab and the realtime listener in the shell.
Future<void> openSosAlert(BuildContext context, SosAlert alert) =>
    AdminSosAlertDialog.show(context, alert);

/// A mm:ss / h:mm counter that ticks on its own, so a list of waiting
/// visitors does not rebuild the whole screen every second.
class ElapsedText extends StatefulWidget {
  final DateTime since;
  final TextStyle? style;
  final String prefix;

  const ElapsedText({
    super.key,
    required this.since,
    this.style,
    this.prefix = '',
  });

  static String format(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.since.toLocal());
    return Text(
      '${widget.prefix}${ElapsedText.format(elapsed)}',
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A big one-tap button for the gate — at least 56 dp tall, icon plus
/// label, because it is pressed standing up with one hand.
class GateActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const GateActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section title used across the guard tabs.
class GateSectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;

  const GateSectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: p.textSecondary,
              ),
            ),
          ),
          if (trailing != null)
            InkWell(
              onTap: onTrailing,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Quiet placeholder for an empty gate list.
class GateEmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const GateEmptyNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Red card for an open SOS. Cannot be dismissed from the home screen —
/// it stays until the alert is resolved or cancelled.
class GateSosCard extends StatelessWidget {
  final SosAlert alert;

  const GateSosCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final type = alert.alertType;
    final active = alert.isActive;
    final base = active ? const Color(0xFFD32F2F) : const Color(0xFF0277BD);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? const [Color(0xFFD32F2F), Color(0xFFB71C1C)]
              : const [Color(0xFF0277BD), Color(0xFF01579B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openSosAlert(context, alert),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(type.icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            active
                                ? '🚨 SOS · ${type.shortLabel.toUpperCase()}'
                                : 'SOS · ACKNOWLEDGED',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            alert.formattedFlat,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElapsedText(
                      since: alert.createdAt,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if ((alert.residentName ?? '').isNotEmpty ||
                    (alert.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if ((alert.residentName ?? '').isNotEmpty)
                        alert.residentName!,
                      if ((alert.note ?? '').isNotEmpty) '"${alert.note}"',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SosQuickButton(
                        label: active ? 'Acknowledge' : 'Open',
                        icon: active
                            ? Icons.pan_tool_alt_rounded
                            : Icons.open_in_new_rounded,
                        // One tap from the home screen: the resident is told
                        // someone is coming the moment the guard presses it.
                        onTap: active
                            ? () => _acknowledge(context)
                            : () => openSosAlert(context, alert),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SosQuickButton(
                        label: 'Call flat',
                        icon: Icons.phone_in_talk_rounded,
                        onTap: () => callFlatFromGate(
                          context,
                          flatId: alert.flatId,
                          reason: 'sos',
                        ),
                      ),
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
}

extension on GateSosCard {
  Future<void> _acknowledge(BuildContext context) async {
    HapticFeedback.mediumImpact();
    try {
      await SecurityService.instance.acknowledgeSosAlert(alert.id);
      if (context.mounted) {
        showGateSnack(
          context,
          'Acknowledged — the flat has been told you are coming',
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showGateSnack(context, gateErrorText(e), danger: true);
      }
    }
  }
}

class _SosQuickButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SosQuickButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFFB71C1C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Lets the guard say which gate this phone is at.
Future<void> showGateSwitcher(BuildContext context) async {
  final service = GuardService.instance;
  if (service.gates.isEmpty) {
    await service.loadGates();
  }
  if (!context.mounted) return;
  final p = AppTheme.paletteFor(Theme.of(context).brightness);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final gates = service.gates;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Which gate are you at?',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Entries you log are recorded against this gate.',
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (gates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No gates are set up yet. Ask the society office to add them.',
                    style: TextStyle(color: p.textSecondary),
                  ),
                )
              else
                ...gates.map((g) {
                  final selected = g.id == service.currentGate?.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.sensor_door_rounded,
                      color: selected ? p.primary : p.textTertiary,
                    ),
                    title: Text(
                      g.name,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle_rounded, color: p.primary)
                        : null,
                    onTap: () {
                      service.selectGate(g.id);
                      Navigator.pop(ctx);
                    },
                  );
                }),
            ],
          ),
        ),
      );
    },
  );
}

/// "6:42 PM" for a check-in time, local.
String gateTime(DateTime? t) =>
    t == null ? '—' : DateFormat('h:mm a').format(t.toLocal());

/// Label for how long a visitor has stayed past their limit.
String overstayLabel(Duration over) {
  if (over.inHours >= 1) {
    return 'over by ${over.inHours}h ${over.inMinutes.remainder(60)}m';
  }
  return 'over by ${over.inMinutes}m';
}

/// Colour-coded "Gate" chip for a header.
class GateChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const GateChip({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: p.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensor_door_rounded, size: 14, color: p.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 16, color: p.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Title row for the guard tabs. Unlike the module headers elsewhere it
/// carries no padding of its own, so it lines up with the list below it.
class GateHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final List<Widget> actions;

  const GateHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        if (showBack) ...[
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              backgroundColor: p.card,
              side: BorderSide(color: p.hairline),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}
