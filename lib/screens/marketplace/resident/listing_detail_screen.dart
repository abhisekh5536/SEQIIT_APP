import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/marketplace_models.dart';
import '../../../services/marketplace_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/marketplace_widgets.dart';
import 'post_listing_screen.dart';
import 'report_listing_sheet.dart';

class ListingDetailScreen extends StatefulWidget {
  final String listingId;

  const ListingDetailScreen({super.key, required this.listingId});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _pageController = PageController();

  MarketplaceListing? _listing;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _page = 0;

  String? _phone;
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await MarketplaceService.instance.fetchListing(widget.listingId);
      if (!mounted) return;
      setState(() {
        _listing = l;
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

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reveal() async {
    HapticFeedback.selectionClick();
    setState(() => _revealing = true);
    try {
      final phone =
          await MarketplaceService.instance.revealSellerPhone(widget.listingId);
      if (mounted) setState(() => _phone = phone);
    } on MarketplaceException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _toast('No app found to open this');
    } catch (_) {
      if (mounted) _toast('No app found to open this');
    }
  }

  /// wa.me needs the full international number without "+" or spaces.
  String _waNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length == 10 ? '91$digits' : digits;
  }

  Future<void> _runAction(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(done);
      await _load();
    } on MarketplaceException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markSold() => _runAction(
        () => MarketplaceService.instance
            .setListingStatus(widget.listingId, ListingStatus.sold),
        'Marked as sold — it is off the feed now',
      );

  Future<void> _relist() => _runAction(
        () => MarketplaceService.instance
            .setListingStatus(widget.listingId, ListingStatus.active),
        'Listing is live again',
      );

  Future<void> _edit() async {
    final l = _listing!;
    final results = await Future.wait([
      MarketplaceService.instance.fetchContext(),
      MarketplaceService.instance.fetchCategories(),
    ]);
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PostListingScreen(
          marketplaceContext: results[0] as MarketplaceContext,
          categories: results[1] as List<MarketplaceCategory>,
          existing: l,
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: const Text(
          'It will be removed from the marketplace along with its photos. This cannot be undone.',
        ),
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
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await MarketplaceService.instance.deleteListing(_listing!);
      if (!mounted) return;
      _toast('Listing deleted');
      Navigator.pop(context, true);
    } on MarketplaceException catch (e) {
      if (mounted) {
        _toast(e.message);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _report() async {
    final reported = await ReportListingSheet.show(
      context,
      listingId: widget.listingId,
      listingTitle: _listing!.title,
    );
    if (reported == true && mounted) _load();
  }

  Future<void> _adminRemove() async {
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove listing?'),
        content: TextField(
          controller: reasonController,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Reason shown to the seller (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    final reason = reasonController.text;
    reasonController.dispose();
    if (ok != true) return;
    await _runAction(
      () => MarketplaceService.instance.setListingStatus(
        widget.listingId,
        ListingStatus.removed,
        reason: reason,
      ),
      'Listing removed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    if (_loading && _listing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_listing == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const ModuleHeader(title: 'Listing'),
              Expanded(
                child: ModuleEmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'Listing unavailable',
                  message: _error ?? 'It may have been sold or removed.',
                  actionLabel: 'Go back',
                  onAction: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final l = _listing!;
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildGallery(l, p)),
              SliverToBoxAdapter(child: _buildBody(l, p)),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  _overlayButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  _buildMenu(l),
                ],
              ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(l, p),
    );
  }

  Widget _overlayButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildMenu(MarketplaceListing l) {
    final items = <PopupMenuEntry<String>>[
      if (l.isMine && l.status != ListingStatus.removed)
        const PopupMenuItem(value: 'edit', child: Text('Edit listing')),
      if (l.isMine)
        const PopupMenuItem(value: 'delete', child: Text('Delete listing')),
      if (!l.isMine && l.viewerIsAdmin && l.status != ListingStatus.removed)
        const PopupMenuItem(value: 'remove', child: Text('Remove listing')),
      if (!l.isMine && !l.viewerIsAdmin)
        PopupMenuItem(
          value: 'report',
          enabled: !l.myReportPending,
          child: Text(l.myReportPending ? 'Reported' : 'Report listing'),
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        onSelected: (v) => switch (v) {
          'edit' => _edit(),
          'delete' => _delete(),
          'remove' => _adminRemove(),
          'report' => _report(),
          _ => null,
        },
        itemBuilder: (_) => items,
      ),
    );
  }

  Widget _buildGallery(MarketplaceListing l, AppPaletteData p) {
    final height = MediaQuery.sizeOf(context).width.clamp(260.0, 420.0);
    if (l.images.isEmpty) {
      return SizedBox(
        height: height * 0.75,
        child: ListingImage(
          url: null,
          categoryIconKey: l.categoryIcon,
          iconSize: 56,
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: l.images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openFullscreen(l, i),
              child: ListingImage(
                url: l.images[i].imageUrl,
                categoryIconKey: l.categoryIcon,
              ),
            ),
          ),
          if (l.images.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < l.images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: i == _page ? 0.95 : 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openFullscreen(MarketplaceListing l, int initial) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenGallery(images: l.images, initial: initial),
      ),
    );
  }

  Widget _buildBody(MarketplaceListing l, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    final status = l.effectiveStatus;
    final metaParts = <String>[
      if (l.categoryName != null) l.categoryName!,
      'Posted ${l.postedAgo}',
      if (l.daysLeft != null)
        l.daysLeft! <= 0
            ? 'expires today'
            : 'expires in ${l.daysLeft} day${l.daysLeft == 1 ? '' : 's'}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status != ListingStatus.active) ...[
            _StatusBanner(listing: l),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  l.priceLabel,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: l.priceType == PriceType.free
                        ? p.success
                        : p.textPrimary,
                  ),
                ),
              ),
              if (l.isNegotiable) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Negotiable',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.title,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            metaParts.join(' · '),
            style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
          ),
          if (l.description != null) ...[
            const SizedBox(height: 18),
            const ModuleSectionHeader(title: 'Details'),
            const SizedBox(height: 6),
            Text(
              l.description!,
              style: textTheme.bodyMedium?.copyWith(
                color: p.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 22),
          const ModuleSectionHeader(title: 'Seller'),
          const SizedBox(height: 8),
          _buildSellerCard(l, p),
          if (!l.isMine) ...[
            const SizedBox(height: 14),
            Text(
              'Meet at the society gate or clubhouse and check the item before paying. Never pay in advance.',
              style: textTheme.bodySmall?.copyWith(
                color: p.textTertiary,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSellerCard(MarketplaceListing l, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    final name = l.sellerName ?? 'Resident';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: p.primary.withValues(alpha: 0.14),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: TextStyle(
                    color: p.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isMine ? '$name (you)' : name,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.sellerFlatLabel ?? 'Your society',
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_phone != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 18, color: p.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _phone!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _launch(Uri(scheme: 'tel', path: _phone)),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launch(Uri.parse(
                      'https://wa.me/${_waNumber(_phone!)}?text=${Uri.encodeComponent('Hi, is "${l.title}" still available? (from the society marketplace)')}',
                    )),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildBottomBar(MarketplaceListing l, AppPaletteData p) {
    Widget bar(List<Widget> children) => SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: p.card,
              border: Border(top: BorderSide(color: p.hairline)),
            ),
            child: Row(children: children),
          ),
        );

    final status = l.effectiveStatus;
    if (l.isMine) {
      if (status == ListingStatus.active) {
        return bar([
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _edit,
              child: const Text('Edit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _busy ? null : _markSold,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Mark as sold'),
            ),
          ),
        ]);
      }
      if (status == ListingStatus.sold || status == ListingStatus.expired) {
        return bar([
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _relist,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Relist item'),
            ),
          ),
        ]);
      }
      return null;
    }

    if (status != ListingStatus.active || _phone != null) return null;
    if (!l.hasSellerPhone) {
      return bar([
        Expanded(
          child: Text(
            'The seller has not added a phone number. Ask the society office to update it.',
            style: TextStyle(color: p.textTertiary, fontSize: 12),
          ),
        ),
      ]);
    }
    return bar([
      Expanded(
        child: FilledButton.icon(
          onPressed: _revealing ? null : _reveal,
          icon: _revealing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.phone_in_talk_outlined, size: 18),
          label: const Text('Show seller\'s number'),
        ),
      ),
    ]);
  }
}

class _StatusBanner extends StatelessWidget {
  final MarketplaceListing listing;

  const _StatusBanner({required this.listing});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final status = listing.effectiveStatus;
    final color = listingStatusColor(status, p);
    final message = switch (status) {
      ListingStatus.sold => listing.soldAt != null
          ? 'Sold on ${DateFormat('d MMM').format(listing.soldAt!)}. Hidden from the feed.'
          : 'Sold. Hidden from the feed.',
      ListingStatus.expired =>
        'Expired and hidden from the feed. Relist it to show it again.',
      ListingStatus.flagged =>
        'Hidden while the society office reviews reports on it.',
      ListingStatus.removed => listing.removedReason != null
          ? 'Removed by the society office: ${listing.removedReason}'
          : 'Removed by the society office.',
      ListingStatus.active => '',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusDot(color: color, label: status.label),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _FullscreenGallery extends StatelessWidget {
  final List<MarketplaceImage> images;
  final int initial;

  const _FullscreenGallery({required this.images, required this.initial});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: images.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: ListingImage(
              url: images[i].imageUrl,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
