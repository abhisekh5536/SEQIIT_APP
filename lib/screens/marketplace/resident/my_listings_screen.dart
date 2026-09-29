import 'package:flutter/material.dart';

import '../../../models/marketplace_models.dart';
import '../../../services/marketplace_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/marketplace_widgets.dart';
import 'listing_detail_screen.dart';
import 'post_listing_screen.dart';

class MyListingsScreen extends StatefulWidget {
  final MarketplaceContext marketplaceContext;
  final List<MarketplaceCategory> categories;

  const MyListingsScreen({
    super.key,
    required this.marketplaceContext,
    required this.categories,
  });

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<MarketplaceListing> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await MarketplaceService.instance.fetchMyListings();
      if (!mounted) return;
      setState(() {
        _all = items;
        _loading = false;
      });
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<MarketplaceListing> _bucket(int tab) => _all.where((l) {
        final s = l.effectiveStatus;
        return switch (tab) {
          0 => s == ListingStatus.active,
          1 => s == ListingStatus.sold,
          _ => s != ListingStatus.active && s != ListingStatus.sold,
        };
      }).toList();

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _open(MarketplaceListing l) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listingId: l.id)),
    );
    if (mounted) _load();
  }

  Future<void> _edit(MarketplaceListing l) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PostListingScreen(
          marketplaceContext: widget.marketplaceContext,
          categories: widget.categories,
          existing: l,
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _setStatus(MarketplaceListing l, ListingStatus s) async {
    try {
      await MarketplaceService.instance.setListingStatus(l.id, s);
      if (!mounted) return;
      _toast(s == ListingStatus.sold ? 'Marked as sold' : 'Listing is live again');
      _load();
    } on MarketplaceException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _delete(MarketplaceListing l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: Text('"${l.title}" and its photos will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MarketplaceService.instance.deleteListing(l);
      if (!mounted) return;
      _toast('Listing deleted');
      _load();
    } on MarketplaceException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _bucket(0).length;
    final sold = _bucket(1).length;
    final other = _bucket(2).length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'My listings',
              subtitle: widget.marketplaceContext.sellerFlatLabel ??
                  'Items you have posted',
            ),
            SegmentedTabs(
              controller: _tabController,
              labels: ['Live ($live)', 'Sold ($sold)', 'Inactive ($other)'],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ModuleEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load your listings',
                          message: _error!,
                          actionLabel: 'Retry',
                          onAction: _load,
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildList(0),
                            _buildList(1),
                            _buildList(2),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(int tab) {
    final items = _bucket(tab);
    if (items.isEmpty) {
      final (title, message) = switch (tab) {
        0 => (
            'Nothing live right now',
            'Post something from the marketplace feed — it shows up for your neighbours instantly.'
          ),
        1 => ('No sales yet', 'Items you mark as sold move here.'),
        _ => (
            'No inactive listings',
            'Expired, hidden or removed listings show up here.'
          ),
      };
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 40),
            ModuleEmptyState(
              icon: Icons.inventory_2_outlined,
              title: title,
              message: message,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final l = items[i];
          return ListingRow(
            listing: l,
            meta: _meta(l),
            onTap: () => _open(l),
            trailing: _actions(l),
          );
        },
      ),
    );
  }

  String _meta(MarketplaceListing l) {
    return switch (l.effectiveStatus) {
      ListingStatus.active => l.daysLeft == null
          ? l.postedAgo
          : '${l.daysLeft}d left',
      ListingStatus.flagged => 'Reported · hidden',
      ListingStatus.removed => l.removedReason ?? 'By society office',
      _ => l.postedAgo,
    };
  }

  Widget _actions(MarketplaceListing l) {
    final s = l.effectiveStatus;
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: p.textSecondary),
      onSelected: (v) => switch (v) {
        'edit' => _edit(l),
        'sold' => _setStatus(l, ListingStatus.sold),
        'relist' => _setStatus(l, ListingStatus.active),
        'delete' => _delete(l),
        _ => null,
      },
      itemBuilder: (_) => [
        if (s != ListingStatus.removed)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (s == ListingStatus.active)
          const PopupMenuItem(value: 'sold', child: Text('Mark as sold')),
        if (s == ListingStatus.sold || s == ListingStatus.expired)
          const PopupMenuItem(value: 'relist', child: Text('Relist')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
