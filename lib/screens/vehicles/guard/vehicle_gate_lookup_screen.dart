import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/app_session.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class VehicleGateLookupScreen extends StatefulWidget {
  final String? societyId;

  /// False when embedded under a host that already supplies a header and a
  /// SafeArea — the admin dashboard's "Gate" tab.
  final bool showAppBar;

  /// False when the screen is a navigation destination rather than a pushed
  /// route, so the header carries no back arrow.
  final bool showBack;

  const VehicleGateLookupScreen({
    super.key,
    this.societyId,
    this.showAppBar = true,
    this.showBack = true,
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
  /// Ids of log rows whose exit is being written, so a second tap on
  /// "Mark out" cannot fire a duplicate update.
  final Set<String> _exiting = {};

  String get _effectiveSocietyId =>
      widget.societyId ?? AppSession.instance.societyId ?? '';

  @override
  void initState() {
    super.initState();
    // The session may still be loading when the gate screen opens; fetching
    // with an empty society id would fail once and never retry, leaving the
    // guard staring at an empty register.
    AppSession.instance.addListener(_onSessionChanged);
    _refreshLogs();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    _plateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_effectiveSocietyId.isNotEmpty &&
        VehiclesParkingService.instance.recentLogs.isEmpty) {
      _refreshLogs();
    }
  }

  Future<void> _refreshLogs() {
    return VehiclesParkingService.instance
        .fetchGateLogs(societyId: _effectiveSocietyId);
  }

  void _snack(String message, {bool danger = false}) {
    if (!mounted) return;
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? p.danger : null,
      ),
    );
  }

  Future<void> _lookup() async {
    final query = _plateController.text.trim();
    if (_isSearching) return;
    if (normalizePlate(query).length < 4) {
      _snack('Enter at least 4 characters of the number plate');
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() => _isSearching = true);
    try {
      final res = await VehiclesParkingService.instance.lookupPlate(
        societyId: _effectiveSocietyId,
        plateNumber: query,
      );
      if (mounted) {
        setState(() => _result = res);
        HapticFeedback.selectionClick();
      }
    } catch (e) {
      // Never silently render "not registered" off a failed lookup — the
      // guard has to know the check did not actually run.
      _snack(
        'Could not check this plate: ${e.toString().replaceFirst('Exception: ', '')}',
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _markExit(VehicleEntryLogItem log) async {
    if (_exiting.contains(log.id)) return;
    setState(() => _exiting.add(log.id));
    try {
      await VehiclesParkingService.instance
          .logGateExit(logId: log.id, societyId: _effectiveSocietyId);
      HapticFeedback.lightImpact();
      _snack('${log.vehicleNumberEntered} marked out');
    } catch (e) {
      _snack(
        'Could not mark exit: ${e.toString().replaceFirst('Exception: ', '')}',
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _exiting.remove(log.id));
    }
  }

  Future<void> _logEntry() async {
    final r = _result;
    if (r == null || _isLogging) return;
    setState(() => _isLogging = true);
    try {
      await VehiclesParkingService.instance.logGateEntry(
        societyId: _effectiveSocietyId,
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
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));
    try {
      // canLaunchUrl can report false even when a dialer exists (package
      // visibility on Android, scheme declarations on iOS), so treat it as a
      // hint and still attempt the launch. A guard pressing "call" and
      // getting silence is worse than a launch that fails loudly.
      if (await canLaunchUrl(uri)) {
        if (await launchUrl(uri)) return;
      }
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      _snack('Could not open the dialer for $phone', danger: true);
    } catch (e) {
      _snack('Could not place the call: $e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: VehiclesParkingService.instance,
      builder: (context, _) {
        final service = VehiclesParkingService.instance;
        final logs = service.recentLogs;
        final logError = service.errorFor('gateLogs');
        return RefreshIndicator(
          onRefresh: _refreshLogs,
          child: ListView(
            padding: widget.showAppBar
                ? const EdgeInsets.fromLTRB(16, 12, 16, 32)
                : const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (widget.showAppBar) ...[
                ModuleHeader(
                  title: 'Gate check',
                  subtitle: 'Verify a plate, then log the movement',
                  showBack: widget.showBack,
                ),
                const SizedBox(height: 12),
              ],
              _PlateEntryCard(
                controller: _plateController,
                isSearching: _isSearching,
                // Keyboard up immediately on the pushed gate screen. Not in
                // the admin dashboard's tab, and not in MainShell either —
                // IndexedStack builds every page eagerly, so autofocus there
                // would grab the keyboard on app launch from whatever tab the
                // user is actually on.
                autofocus: widget.showAppBar && widget.showBack,
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
                onTrailing: _refreshLogs,
              ),
              const SizedBox(height: 8),
              if (logError != null)
                ModuleEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Gate register unavailable',
                  message: logError,
                  actionLabel: 'Retry',
                  onAction: _refreshLogs,
                )
              else if (logs.isEmpty)
                const ModuleEmptyState(
                  icon: Icons.history_rounded,
                  title: 'Nothing logged today yet',
                  message:
                      'Look up a plate above — resident and visitor movements for today will list here.',
                )
              else
                ...logs.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _GateLogRow(
                        log: l,
                        isExiting: _exiting.contains(l.id),
                        onExit: l.isExited ? null : () => _markExit(l),
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
  final bool autofocus;

  const _PlateEntryCard({
    required this.controller,
    required this.isSearching,
    required this.onChanged,
    required this.onClear,
    required this.onLookup,
    this.autofocus = false,
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
                  autofocus: autofocus,
                  textInputAction: TextInputAction.search,
                  // The guard types this one-handed at a barrier; force the
                  // register's own casing so "mh12ab1234" and "MH 12 AB 1234"
                  // cannot become two different entries.
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(16),
                    TextInputFormatter.withFunction((oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase())),
                  ],
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
  final bool isExiting;

  const _GateLogRow({
    required this.log,
    this.onExit,
    this.isExiting = false,
  });

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
              else if (isExiting)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.primary,
                    ),
                  ),
                )
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
