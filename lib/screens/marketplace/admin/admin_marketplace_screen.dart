import 'package:flutter/material.dart';

import '../../../models/marketplace_models.dart';
import '../../../services/app_session.dart';
import '../../../services/marketplace_service.dart';
import '../../../theme/app_theme.dart';
import '../resident/listing_detail_screen.dart';
import '../widgets/marketplace_widgets.dart';

/// Society Admin: moderation queue, all listings, and module settings.
class AdminMarketplaceScreen extends StatefulWidget {
  final bool showBack;

  const AdminMarketplaceScreen({super.key, this.showBack = true});

  @override
  State<AdminMarketplaceScreen> createState() => _AdminMarketplaceScreenState();
}

class _AdminMarketplaceScreenState extends State<AdminMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  MarketplaceContext _ctx = const MarketplaceContext();
  List<MarketplaceReport> _reports = const [];
  List<MarketplaceListing> _listings = const [];
  List<MarketplaceCategory> _categories = const [];
  List<BlockedSeller> _blocked = const [];

  bool _showReviewed = false;
  ListingStatus? _listingFilter;
  bool _loading = true;
  String? _error;

  String? get _societyId => AppSession.instance.societyId ?? _ctx.societyId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _ctx = await MarketplaceService.instance.fetchContext();
    final societyId = _societyId;
    if (societyId == null) {
      if (mounted) {
        setState(() {
          _error = _ctx.error ?? 'No society linked to this admin account';
          _loading = false;
        });
      }
      return;
    }
    try {
      final service = MarketplaceService.instance;
      final results = await Future.wait([
        service.fetchReports(societyId: societyId, pendingOnly: !_showReviewed),
        service.fetchSocietyListings(
            societyId: societyId, status: _listingFilter),
        service.fetchCategories(includeInactive: true),
        service.fetchBlockedSellers(societyId),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = results[0] as List<MarketplaceReport>;
        _listings = results[1] as List<MarketplaceListing>;
        _categories = results[2] as List<MarketplaceCategory>;
        _blocked = results[3] as List<BlockedSeller>;
        _loading = false;
      });
      if (_showReviewed) service.refreshPendingReportsCount(societyId);
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      _toast(done);
      await _loadAll();
    } on MarketplaceException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _openListing(String listingId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ListingDetailScreen(listingId: listingId)),
    );
    if (mounted) _loadAll();
  }

  /// Confirm a moderation action with an optional note to the seller.
  Future<String?> _confirmWithNote({
    required String title,
    required String message,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note to the seller (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final note = controller.text;
    controller.dispose();
    return ok == true ? note : null;
  }

  Future<void> _resolve(MarketplaceReport r, ReportAction action) async {
    final title = r.listing?.title ?? 'this listing';
    final String? note;
    if (action == ReportAction.dismiss) {
      note = '';
    } else {
      note = await _confirmWithNote(
        title: action.label,
        message: switch (action) {
          ReportAction.warnSeller =>
            'The listing stays up. The seller gets a notification with your note.',
          ReportAction.removeListing =>
            '"$title" will be taken off the marketplace. All open reports on it are closed.',
          ReportAction.blockSeller =>
            '"$title" will be removed and the seller cannot post again until you unblock them.',
          ReportAction.dismiss => '',
        },
        confirmLabel: action.label,
        destructive: action == ReportAction.removeListing ||
            action == ReportAction.blockSeller,
      );
    }
    if (note == null) return;
    await _run(
      () => MarketplaceService.instance.resolveReport(
        reportId: r.id,
        action: action,
        note: note,
      ),
      switch (action) {
        ReportAction.dismiss => 'Report dismissed',
        ReportAction.warnSeller => 'Seller warned',
        ReportAction.removeListing => 'Listing removed',
        ReportAction.blockSeller => 'Listing removed and seller blocked',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _showReviewed
        ? MarketplaceService.instance.pendingReportsCount
        : _reports.length;
    final live =
        _listings.where((l) => l.effectiveStatus == ListingStatus.active).length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Marketplace',
              subtitle: _ctx.enabled
                  ? '${AppSession.instance.societyName} · moderation & settings'
                  : 'Turned off for residents',
              showBack: widget.showBack,
              actions: [
                IconButton(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            SegmentedTabs(
              controller: _tabController,
              labels: [
                'Reports ($pending)',
                _listingFilter == null ? 'Listings ($live live)' : 'Listings',
                'Settings',
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ModuleEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load marketplace',
                          message: _error!,
                          actionLabel: 'Retry',
                          onAction: _loadAll,
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildReportsTab(),
                            _buildListingsTab(),
                            _buildSettingsTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reports ─────────────────────────────────────────────────

  Widget _buildReportsTab() {
    final filter = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Pending'),
            selected: !_showReviewed,
            onSelected: (_) {
              setState(() => _showReviewed = false);
              _loadAll();
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Reviewed'),
            selected: _showReviewed,
            onSelected: (_) {
              setState(() => _showReviewed = true);
              _loadAll();
            },
          ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          filter,
          if (_reports.isEmpty)
            ModuleEmptyState(
              icon: Icons.verified_user_outlined,
              title: _showReviewed ? 'No reviewed reports' : 'Queue is clear',
              message: _showReviewed
                  ? 'Reports you act on will be listed here.'
                  : 'Listings reported by residents will appear here for review.',
            )
          else
            for (final r in _reports)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _ReportCard(
                  report: r,
                  onOpenListing: () => _openListing(r.listingId),
                  onAction: r.isPending ? (a) => _resolve(r, a) : null,
                ),
              ),
        ],
      ),
    );
  }

  // ── Listings ────────────────────────────────────────────────

  Widget _buildListingsTab() {
    final filters = <(ListingStatus?, String)>[
      (null, 'All'),
      (ListingStatus.active, 'Live'),
      (ListingStatus.flagged, 'Under review'),
      (ListingStatus.removed, 'Removed'),
      (ListingStatus.sold, 'Sold'),
      (ListingStatus.expired, 'Expired'),
    ];
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (status, label) in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _listingFilter == status,
                      onSelected: (_) {
                        setState(() => _listingFilter = status);
                        _loadAll();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_listings.isEmpty)
            const ModuleEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No listings',
              message: 'Nothing posted with this status yet.',
            )
          else
            for (final l in _listings)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: ListingRow(
                  listing: l,
                  meta: [
                    l.sellerName ?? 'Resident',
                    if (l.flatNumber != null) 'Flat ${l.flatNumber}',
                    if (l.reportCount > 0)
                      '${l.reportCount} report${l.reportCount == 1 ? '' : 's'}',
                  ].join(' · '),
                  onTap: () => _openListing(l.id),
                  trailing: _listingMenu(l),
                ),
              ),
        ],
      ),
    );
  }

  Widget _listingMenu(MarketplaceListing l) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: p.textSecondary),
      onSelected: (v) async {
        if (v == 'remove') {
          final note = await _confirmWithNote(
            title: 'Remove listing',
            message: '"${l.title}" will be taken off the marketplace.',
            confirmLabel: 'Remove',
            destructive: true,
          );
          if (note == null) return;
          await _run(
            () => MarketplaceService.instance.setListingStatus(
                l.id, ListingStatus.removed,
                reason: note),
            'Listing removed',
          );
        } else if (v == 'restore') {
          await _run(
            () => MarketplaceService.instance
                .setListingStatus(l.id, ListingStatus.active),
            'Listing restored',
          );
        }
      },
      itemBuilder: (_) => [
        if (l.status != ListingStatus.removed)
          const PopupMenuItem(value: 'remove', child: Text('Remove')),
        if (l.status == ListingStatus.removed ||
            l.status == ListingStatus.flagged)
          const PopupMenuItem(value: 'restore', child: Text('Restore to feed')),
      ],
    );
  }

  // ── Settings ────────────────────────────────────────────────

  Widget _buildSettingsTab() {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final societyCats = _categories.where((c) => !c.isGlobal).toList();
    final globalCats = _categories.where((c) => c.isGlobal).toList();

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _SettingsCard(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ctx.enabled,
                title: const Text(
                  'Marketplace for residents',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _ctx.enabled
                      ? 'Residents can buy and sell within the society'
                      : 'Hidden from residents. Existing listings are kept.',
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                ),
                onChanged: (v) => _run(
                  () => MarketplaceService.instance.setEnabled(v),
                  v ? 'Marketplace turned on' : 'Marketplace turned off',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              const ModuleSectionHeader(title: 'Listing policy'),
              const SizedBox(height: 10),
              _policyRow(
                label: 'Listings expire after',
                value: _ctx.listingExpiryDays,
                options: const [7, 14, 30, 45, 60, 90],
                format: (d) => '$d days',
                onChanged: (d) => _run(
                  () => MarketplaceService.instance.updateSettings(
                    listingExpiryDays: d,
                    autoFlagThreshold: _ctx.autoFlagThreshold,
                  ),
                  'New listings will expire after $d days',
                ),
              ),
              const SizedBox(height: 8),
              _policyRow(
                label: 'Auto-hide after',
                value: _ctx.autoFlagThreshold,
                options: const [1, 2, 3, 5, 10],
                format: (n) => '$n report${n == 1 ? '' : 's'}',
                onChanged: (n) => _run(
                  () => MarketplaceService.instance.updateSettings(
                    listingExpiryDays: _ctx.listingExpiryDays,
                    autoFlagThreshold: n,
                  ),
                  'Listings auto-hide after $n report${n == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ModuleSectionHeader(
                title: 'Categories',
                trailing: '+ Add',
                onTrailing: _addCategory,
              ),
              const SizedBox(height: 4),
              Text(
                'Default categories are shared by all societies. Add your own for anything specific to your community.',
                style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: 8),
              for (final c in societyCats)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: Icon(categoryIcon(c.iconKey), size: 20),
                  title: Text(c.name),
                  subtitle: const Text('Your society'),
                  value: c.isActive,
                  onChanged: (v) => _run(
                    () => MarketplaceService.instance.setCategoryActive(c.id, v),
                    v ? '${c.name} enabled' : '${c.name} hidden',
                  ),
                ),
              for (final c in globalCats)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(categoryIcon(c.iconKey), size: 20),
                  title: Text(c.name),
                  trailing: Icon(Icons.lock_outline_rounded,
                      size: 16, color: p.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ModuleSectionHeader(
                title: 'Blocked sellers',
                trailing: '${_blocked.length}',
              ),
              const SizedBox(height: 4),
              if (_blocked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nobody is blocked. Use "Remove & block seller" on a report to pause someone\'s posting.',
                    style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                )
              else
                for (final b in _blocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(b.name),
                    subtitle: Text(
                      [?b.flat, ?b.reason].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () => _run(
                        () => MarketplaceService.instance.unblockSeller(
                          societyId: _societyId!,
                          residentId: b.residentId,
                        ),
                        '${b.name} can post again',
                      ),
                      child: const Text('Unblock'),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _policyRow({
    required String label,
    required int value,
    required List<int> options,
    required String Function(int) format,
    required ValueChanged<int> onChanged,
  }) {
    final opts = options.contains(value) ? options : ([...options, value]..sort());
    return Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [
            for (final o in opts)
              DropdownMenuItem(value: o, child: Text(format(o))),
          ],
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
        ),
      ],
    );
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Plants & Garden'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 2 || _societyId == null) return;
    await _run(
      () => MarketplaceService.instance
          .addCategory(societyId: _societyId!, name: name),
      '$name added',
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final MarketplaceReport report;
  final VoidCallback onOpenListing;
  final ValueChanged<ReportAction>? onAction;

  const _ReportCard({
    required this.report,
    required this.onOpenListing,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final l = report.listing;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (l != null)
            ListingRow(
              listing: l,
              meta: [
                l.sellerName ?? 'Resident',
                ?l.sellerFlatLabel,
              ].join(' · '),
              onTap: onOpenListing,
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: p.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  report.reason.label,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                timeAgo(report.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: p.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          if (report.details != null) ...[
            const SizedBox(height: 4),
            Text(
              '"${report.details}"',
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Reported by ${report.reporterName ?? 'a resident'}'
            '${report.reporterFlat != null ? ' · ${report.reporterFlat}' : ''}'
            '${l != null && l.reportCount > 1 ? ' · ${l.reportCount} reports in total' : ''}',
            style: textTheme.bodySmall?.copyWith(
              color: p.textTertiary,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          if (onAction == null)
            StatusDot(
              color: report.actionTaken == 'dismissed' ? p.textTertiary : p.success,
              label: [
                report.actionLabel,
                ?report.adminNote,
              ].join(' · '),
            )
          else
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => onAction!(ReportAction.dismiss),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PopupMenuButton<ReportAction>(
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      for (final a in [
                        ReportAction.warnSeller,
                        ReportAction.removeListing,
                        ReportAction.blockSeller,
                      ])
                        PopupMenuItem(value: a, child: Text(a.label)),
                    ],
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.danger,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Take action',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down_rounded,
                              color: Colors.white),
                        ],
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
