import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/marketplace_models.dart';
import '../../../services/app_session.dart';
import '../../../services/marketplace_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/marketplace_widgets.dart';
import 'listing_detail_screen.dart';
import 'my_listings_screen.dart';
import 'post_listing_screen.dart';

/// Society-scoped feed. The server decides which society from the session;
/// this screen never passes a society id.
class MarketplaceFeedScreen extends StatefulWidget {
  final bool showBack;

  const MarketplaceFeedScreen({super.key, this.showBack = true});

  @override
  State<MarketplaceFeedScreen> createState() => _MarketplaceFeedScreenState();
}

class _MarketplaceFeedScreenState extends State<MarketplaceFeedScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  MarketplaceContext _ctx = const MarketplaceContext();
  List<MarketplaceCategory> _categories = const [];
  List<MarketplaceListing> _listings = const [];
  String? _categoryId;
  FeedSort _sort = FeedSort.newest;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      MarketplaceService.instance.fetchContext(),
      MarketplaceService.instance.fetchCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _ctx = results[0] as MarketplaceContext;
      _categories = results[1] as List<MarketplaceCategory>;
    });
    await _loadFeed();
  }

  Future<void> _loadFeed() async {
    if (!_ctx.enabled) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await MarketplaceService.instance.fetchFeed(
        categoryId: _categoryId,
        search: _searchController.text,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _listings = items;
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

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadFeed);
  }

  Future<void> _openListing(MarketplaceListing l) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listingId: l.id)),
    );
    if (mounted) _loadFeed();
  }

  Future<void> _openPost() async {
    HapticFeedback.lightImpact();
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PostListingScreen(
          marketplaceContext: _ctx,
          categories: _categories,
        ),
      ),
    );
    if (created == true && mounted) _loadFeed();
  }

  Future<void> _openMyListings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyListingsScreen(
          marketplaceContext: _ctx,
          categories: _categories,
        ),
      ),
    );
    if (mounted) _loadFeed();
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<FeedSort>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in FeedSort.values)
              ListTile(
                title: Text(s.label),
                trailing: s == _sort
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != _sort) {
      setState(() => _sort = picked);
      _loadFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final session = AppSession.instance;
    final countLabel = _loading
        ? session.societyName
        : '${session.societyName} · ${_listings.length} item${_listings.length == 1 ? '' : 's'}';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Marketplace',
              subtitle: countLabel,
              showBack: widget.showBack,
              actions: [
                if (_ctx.residentId != null)
                  TextButton.icon(
                    onPressed: _openMyListings,
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('My listings'),
                  ),
              ],
            ),
            if (_ctx.enabled) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search sofas, cycles, books…',
                          prefixIcon: const Icon(Icons.search_rounded),
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
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _pickSort,
                      tooltip: _sort.label,
                      icon: Icon(
                        Icons.swap_vert_rounded,
                        color: _sort == FeedSort.newest
                            ? p.textSecondary
                            : p.primary,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: p.card,
                        side: BorderSide(color: p.hairline),
                      ),
                    ),
                  ],
                ),
              ),
              CategoryChips(
                categories: _categories,
                selectedId: _categoryId,
                onSelected: (id) {
                  setState(() => _categoryId = id);
                  _loadFeed();
                },
              ),
              if (_ctx.isBlocked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: FormError(
                    'The society office has paused your posting. You can still browse.',
                  ),
                ),
              const SizedBox(height: 10),
            ],
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: _ctx.canPost
          ? FloatingActionButton.extended(
              onPressed: _openPost,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Sell an item'),
              backgroundColor: p.primary,
              foregroundColor: p.onPrimary,
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_ctx.enabled) {
      return RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          children: [
            const SizedBox(height: 60),
            ModuleEmptyState(
              icon: Icons.storefront_outlined,
              title: _ctx.error == null
                  ? 'Marketplace is turned off'
                  : 'Marketplace unavailable',
              message: _ctx.error ??
                  'Your society office has not enabled the marketplace yet.',
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return ModuleEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load listings',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _loadFeed,
      );
    }
    if (_listings.isEmpty) {
      final filtered =
          _categoryId != null || _searchController.text.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: _loadFeed,
        child: ListView(
          children: [
            const SizedBox(height: 40),
            ModuleEmptyState(
              icon: Icons.storefront_outlined,
              title: filtered ? 'Nothing matches' : 'No listings yet',
              message: filtered
                  ? 'Try another category or search term.'
                  : 'Be the first to list something — neighbours only, no strangers.',
              actionLabel: !filtered && _ctx.canPost ? 'Sell an item' : null,
              onAction: !filtered && _ctx.canPost ? _openPost : null,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.66,
        ),
        itemCount: _listings.length,
        itemBuilder: (_, i) => ListingGridCard(
          listing: _listings[i],
          onTap: () => _openListing(_listings[i]),
        ),
      ),
    );
  }
}
