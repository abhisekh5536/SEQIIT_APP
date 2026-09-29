import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/facility_models.dart';
import '../../services/facilities_service.dart';
import '../../theme/app_theme.dart';
import 'facilities_settings_screen.dart';
import 'facility_categories_screen.dart';
import 'facility_detail_screen.dart';
import 'facility_form_screen.dart';
import 'widgets/facility_widgets.dart';

/// Admin: every facility of the society, with status at a glance and a
/// one-tap status change (the common case — "pool closed for cleaning").
class AdminFacilitiesScreen extends StatefulWidget {
  final bool showBack;

  const AdminFacilitiesScreen({super.key, this.showBack = true});

  @override
  State<AdminFacilitiesScreen> createState() => _AdminFacilitiesScreenState();
}

class _AdminFacilitiesScreenState extends State<AdminFacilitiesScreen> {
  List<FacilityRecord> _facilities = [];
  bool _loading = true;
  bool _moduleEnabled = true;
  FacilityStatus? _statusFilter;
  String? _error;

  @override
  void initState() {
    super.initState();
    FacilitiesService.instance.startLive();
    FacilitiesService.instance.addListener(_onLive);
    _load();
  }

  @override
  void dispose() {
    FacilitiesService.instance.removeListener(_onLive);
    FacilitiesService.instance.stopLive();
    super.dispose();
  }

  void _onLive() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent && _facilities.isEmpty) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        FacilitiesService.instance.fetchFacilities(),
        FacilitiesService.instance.isModuleEnabled(),
      ]);
      if (!mounted) return;
      setState(() {
        _facilities = results[0] as List<FacilityRecord>;
        _moduleEnabled = results[1] as bool;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'Could not load facilities: $e';
      });
    }
  }

  int _count(FacilityStatus s) =>
      _facilities.where((f) => f.status == s).length;

  List<FacilityRecord> get _visible => _statusFilter == null
      ? _facilities
      : _facilities.where((f) => f.status == _statusFilter).toList();

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openForm([FacilityRecord? f]) async {
    HapticFeedback.lightImpact();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FacilityFormScreen(facility: f)),
    );
    _load(silent: true);
  }

  Future<void> _changeStatus(FacilityRecord f, FacilityStatus status) async {
    if (status == f.status) return;
    String? note;
    if (!status.isAvailable) {
      note = await _askNote(f, status);
      if (note == null) return; // cancelled
    }
    try {
      await FacilitiesService.instance.setStatus(f.id, status, note: note);
      HapticFeedback.mediumImpact();
      _snack('${f.name}: ${status.label}. Residents notified.');
      _load(silent: true);
    } catch (e) {
      _snack('Could not update status: $e');
    }
  }

  /// Returns the note ('' for none), or null if cancelled.
  Future<String?> _askNote(FacilityRecord f, FacilityStatus status) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark ${f.name} as ${status.label.toLowerCase()}?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Note for residents (optional)',
            hintText: 'e.g. Cleaning until Friday',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Update'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add facility'),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Row(
                children: [
                  if (widget.showBack)
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Facilities',
                            style: textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text('Manage what residents see',
                            style: textTheme.bodySmall
                                ?.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Categories',
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FacilityCategoriesScreen()),
                      );
                      _load(silent: true);
                    },
                    icon: const Icon(Icons.category_outlined),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FacilitiesSettingsScreen()),
                      );
                      _load(silent: true);
                    },
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!_loading && !_moduleEnabled) ...[
                _moduleOffBanner(p),
                const SizedBox(height: 14),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.danger)),
                )
              else if (_facilities.isEmpty)
                _emptyState(p)
              else ...[
                _summary(p),
                const SizedBox(height: 14),
                if (_visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      'Nothing ${_statusFilter!.label.toLowerCase()} right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textTertiary),
                    ),
                  ),
                for (final f in _visible) ...[
                  _facilityTile(p, f),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _moduleOffBanner(AppPaletteData p) {
    return Surface(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FacilitiesSettingsScreen()),
        );
        _load(silent: true);
      },
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, color: p.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hidden from residents. Turn the module on in Settings when '
              'the catalog is ready.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        ],
      ),
    );
  }

  /// Status counts that double as filters.
  Widget _summary(AppPaletteData p) {
    Widget cell(FacilityStatus? s, String label, int count, Color color) {
      final selected = _statusFilter == s;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _statusFilter = selected ? null : s);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? color.withValues(alpha: 0.5) : p.hairline),
            ),
            child: Column(
              children: [
                Text('$count',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        cell(null, 'All', _facilities.length, p.primary),
        const SizedBox(width: 8),
        for (final s in FacilityStatus.values) ...[
          cell(s, s.shortLabel, _count(s), s.color(p)),
          if (s != FacilityStatus.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _facilityTile(AppPaletteData p, FacilityRecord f) {
    final textTheme = Theme.of(context).textTheme;
    return Surface(
      padding: const EdgeInsets.all(10),
      onTap: () async {
        HapticFeedback.lightImpact();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FacilityDetailScreen(facilityId: f.id, initial: f),
          ),
        );
        _load(silent: true);
      },
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Hero(
                tag: 'facility-cover-${f.id}',
                child: FacilityImageView(
                  url: f.coverUrl,
                  fallbackIcon: f.fallbackIcon,
                  dimmed: !f.status.isAvailable,
                  iconSize: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  [
                    f.categoryName ?? 'Uncategorised',
                    '${f.images.length} photo${f.images.length == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: textTheme.bodySmall
                      ?.copyWith(color: p.textTertiary, fontSize: 11.5),
                ),
                const SizedBox(height: 6),
                FacilityStatusBadge(status: f.status, compact: true),
              ],
            ),
          ),
          PopupMenuButton<Object>(
            tooltip: 'Actions',
            onSelected: (v) {
              if (v == 'edit') {
                _openForm(f);
              } else if (v is FacilityStatus) {
                _changeStatus(f, v);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              for (final s in FacilityStatus.values)
                PopupMenuItem(
                  value: s,
                  enabled: s != f.status,
                  child: ListTile(
                    leading: Icon(s.icon, color: s.color(p)),
                    title: Text(s == FacilityStatus.active
                        ? 'Mark open'
                        : 'Mark ${s.shortLabel.toLowerCase()}'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState(AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.pool_rounded, size: 36, color: p.primary),
          ),
          const SizedBox(height: 16),
          Text('Add your first facility',
              style: textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Clubhouse, gym, pool, courts — add photos, hours and rules so '
            'residents know what is available.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
