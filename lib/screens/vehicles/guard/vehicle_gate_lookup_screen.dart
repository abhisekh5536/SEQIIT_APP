import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class VehicleGateLookupScreen extends StatefulWidget {
  final String societyId;
  final bool showAppBar;

  const VehicleGateLookupScreen({
    super.key,
    required this.societyId,
    this.showAppBar = true,
  });

  @override
  State<VehicleGateLookupScreen> createState() =>
      _VehicleGateLookupScreenState();
}

class _VehicleGateLookupScreenState extends State<VehicleGateLookupScreen> {
  final _plateController = TextEditingController();
  final _notesController = TextEditingController();

  PlateLookupResult? _result;
  bool _isSearching = false;
  bool _isLogging = false;

  @override
  void initState() {
    super.initState();
    VehiclesParkingService.instance.fetchGateLogs(societyId: widget.societyId);
  }

  @override
  void dispose() {
    _plateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final query = _plateController.text.trim();
    if (query.isEmpty || _isSearching) return;
    HapticFeedback.lightImpact();
    setState(() => _isSearching = true);
    try {
      final res = await VehiclesParkingService.instance.lookupPlate(
        societyId: widget.societyId,
        plateNumber: query,
      );
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lookup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _logEntry() async {
    final r = _result;
    if (r == null || _isLogging) return;
    setState(() => _isLogging = true);
    try {
      await VehiclesParkingService.instance.logGateEntry(
        societyId: widget.societyId,
        plateNumber: r.vehicleNumber ?? _plateController.text.trim(),
        vehicleId: r.vehicleId,
        matchStatus: r.matchStatus,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      if (mounted) {
        setState(() {
          _notesController.clear();
          _plateController.clear();
          _result = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry noted in the gate register')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log entry: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLogging = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'\s+'), '')}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: VehiclesParkingService.instance,
      builder: (context, _) {
        final logs = VehiclesParkingService.instance.recentLogs;
        return RefreshIndicator(
          onRefresh: () => VehiclesParkingService.instance
              .fetchGateLogs(societyId: widget.societyId),
          child: ListView(
            padding: widget.showAppBar
                ? const EdgeInsets.fromLTRB(16, 12, 16, 32)
                : const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (widget.showAppBar) ...[
                ModuleHeader(
                  title: 'Gate check',
                  subtitle: 'Verify a plate, then log the movement',
                  showBack: true,
                ),
                const SizedBox(height: 12),
              ],
              _PlateEntryCard(
                controller: _plateController,
                isSearching: _isSearching,
                onChanged: (_) => setState(() {}),
                onClear: () => setState(() {
                  _plateController.clear();
                  _result = null;
                }),
                onLookup: _lookup,
              ),
              if (_result != null) ...[
                const SizedBox(height: 10),
                _VerdictCard(
                  result: _result!,
                  notesController: _notesController,
                  isLogging: _isLogging,
                  onLog: _logEntry,
                  onCall: _call,
                  onDismiss: () => setState(() => _result = null),
                ),
              ],
              const SizedBox(height: 16),
              ModuleSectionHeader(
                title: 'Today at the gate (${logs.length})',
                trailing: 'Refresh',
                onTrailing: () => VehiclesParkingService.instance
                    .fetchGateLogs(societyId: widget.societyId),
              ),
              const SizedBox(height: 8),
              if (logs.isEmpty)
                const ModuleEmptyState(
                  icon: Icons.history_rounded,
                  title: 'No movements noted yet',
                  message:
                      'Look up a plate above — resident and visitor entries will list here.',
                )
              else
                ...logs.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _GateLogRow(
                        log: l,
                        onExit: l.isExited
                            ? null
                            : () => VehiclesParkingService.instance
                                .logGateExit(
                                    logId: l.id, societyId: widget.societyId),
                      ),
                    )),
            ],
          ),
        );
      },
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      body: SafeArea(child: body),
    );
  }
}

class _PlateEntryCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onLookup;

  const _PlateEntryCard({
    required this.controller,
    required this.isSearching,
    required this.onChanged,
    required this.onClear,
    required this.onLookup,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vehicle number',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: onChanged,
                  onSubmitted: (_) => onLookup(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'MH 12 AB 1234',
                    hintStyle: TextStyle(
                      fontFamily: null,
                      fontSize: 14,
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w400,
                      color: p.textTertiary,
                    ),
                    prefixIcon: const Icon(Icons.directions_car_outlined,
                        size: 20),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: onClear,
                          )
                        : null,
                    filled: true,
                    fillColor: p.cardMuted,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: isSearching ? null : onLookup,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: isSearching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Check'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Type as printed on the plate — spaces optional.',
            style: TextStyle(color: p.textTertiary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final PlateLookupResult result;
  final TextEditingController notesController;
  final bool isLogging;
  final VoidCallback onLog;
  final ValueChanged<String> onCall;
  final VoidCallback onDismiss;

  const _VerdictCard({
    required this.result,
    required this.notesController,
    required this.isLogging,
    required this.onLog,
    required this.onCall,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final ok = result.isRegistered;
    final edge = ok ? p.success : p.warning;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: edge,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: VehiclePlate(
                        (result.vehicleNumber ?? result.normalizedQuery)
                            .toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusDot(
                      color: edge,
                      label: ok ? 'Resident' : 'Not registered',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (ok) ...[
                  _kv(context, 'Flat',
                      result.flatDisplay == '—' ? '—' : result.flatDisplay),
                  _kv(context, 'Resident', result.residentName ?? '—',
                      secondary: result.makeModel),
                  _kv(
                      context,
                      'Bay',
                      result.slotNumber != null
                          ? 'Bay ${result.slotNumber}'
                          : 'No bay allotted'),
                  if (result.residentPhone != null &&
                      result.residentPhone!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => onCall(result.residentPhone!),
                        icon: const Icon(Icons.call_outlined, size: 16),
                        label: Text(result.residentPhone!,
                            style: const TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                ] else ...[
                  Text(
                    'No match in the society register. Note the purpose below — delivery, cab, guest — before logging.',
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onLog(),
                  decoration: InputDecoration(
                    hintText: ok
                        ? 'Note (optional) — e.g. family member driving'
                        : 'Purpose — e.g. Swiggy delivery to B-202',
                    hintStyle:
                        TextStyle(fontSize: 12.5, color: p.textTertiary),
                    filled: true,
                    fillColor: p.cardMuted,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: isLogging ? null : onLog,
                          style: FilledButton.styleFrom(
                            backgroundColor: edge,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isLogging
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(ok ? 'Log entry' : 'Log visitor entry'),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {String? secondary}) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              k,
              style: TextStyle(color: p.textTertiary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              secondary != null && secondary.isNotEmpty ? '$v · $secondary' : v,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GateLogRow extends StatelessWidget {
  final VehicleEntryLogItem log;
  final VoidCallback? onExit;

  const _GateLogRow({required this.log, this.onExit});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final ok = log.matchStatus == MatchStatus.registered;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 44,
            decoration: BoxDecoration(
              color: (ok ? p.success : p.warning).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.vehicleNumberEntered.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.8,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? '${log.flatDisplay} · ${[
                          if ((log.residentName ?? '').isNotEmpty)
                            log.residentName!,
                          if ((log.makeModel ?? '').isNotEmpty) log.makeModel!,
                        ].join(' · ')}'
                      : ((log.notes?.isNotEmpty == true)
                          ? log.notes!
                          : 'Visitor / cab'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                DateFormat('h:mm a').format(log.entryAt),
                style: TextStyle(
                  fontSize: 11.5,
                  color: p.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              if (log.isExited)
                Text('Out ${DateFormat('h:mm a').format(log.exitAt!)}',
                    style:
                        TextStyle(fontSize: 11, color: p.textTertiary))
              else if (onExit != null)
                InkWell(
                  onTap: onExit,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(
                      'Mark out',
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
        ],
      ),
    );
  }
}
