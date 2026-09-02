import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/visitor_models.dart';
import '../../services/notifications_service.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';
import 'pre_approve_bottom_sheet.dart';
import 'visitor_detail_screen.dart';
import 'widgets/visitor_card.dart';

class ResidentVisitorsScreen extends StatefulWidget {
  final bool showBack;

  const ResidentVisitorsScreen({super.key, this.showBack = true});

  @override
  State<ResidentVisitorsScreen> createState() => _ResidentVisitorsScreenState();
}

class _ResidentVisitorsScreenState extends State<ResidentVisitorsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  List<VisitorRecord> _visitors = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    NotificationsService.instance.markModuleAsRead('visitor');
    _loadVisitors();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVisitors() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await VisitorsService.instance.fetchResidentVisitors();
      if (mounted) {
        setState(() {
          _visitors = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load visitors: $e';
          _loading = false;
        });
      }
    }
  }

  List<VisitorRecord> get _pending =>
      _visitors.where((v) => v.isPending).toList();

  List<VisitorRecord> get _upcoming => _visitors
      .where((v) =>
          (v.isApproved || v.isCheckedIn) && v.isWithinValidity)
      .toList();

  List<VisitorRecord> get _past => _visitors
      .where((v) =>
          v.isDenied ||
          v.isCancelled ||
          v.isExpired ||
          v.isCheckedOut ||
          !v.isWithinValidity)
      .toList();

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  if (widget.showBack)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: p.card,
                        side: BorderSide(color: p.hairline),
                      ),
                    ),
                  if (widget.showBack) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'My Visitors',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_pending.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_top_rounded,
                              size: 14, color: p.warning),
                          const SizedBox(width: 4),
                          Text(
                            '${_pending.length} pending',
                            style: TextStyle(
                              color: p.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Tabs
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: p.cardMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: p.shadow.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: p.textPrimary,
                  unselectedLabelColor: p.textTertiary,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    Tab(text: 'Pending (${_pending.length})'),
                    Tab(text: 'Upcoming (${_upcoming.length})'),
                    const Tab(text: 'Past'),
                    Tab(text: 'All (${_visitors.length})'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError(p, textTheme)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildList(_pending, 'No pending approvals',
                                'Gate requests from visitors will appear here',
                                Icons.hourglass_empty_rounded),
                            _buildList(_upcoming, 'No upcoming visitors',
                                'Pre-approved visitors will appear here',
                                Icons.event_available_rounded),
                            _buildList(_past, 'No past visitors',
                                'Visitor history will appear here',
                                Icons.history_rounded),
                            _buildList(_visitors, 'No visitors yet',
                                'Create a pre-approval to get started',
                                Icons.people_outline_rounded),
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPreApproveSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Pre-Approve'),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
    );
  }

  Widget _buildList(
    List<VisitorRecord> visitors,
    String emptyTitle,
    String emptySubtitle,
    IconData emptyIcon,
  ) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    if (visitors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(emptyIcon, size: 32, color: p.textTertiary),
              ),
              const SizedBox(height: 16),
              Text(
                emptyTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadVisitors,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: visitors.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final visitor = visitors[index];
          return VisitorCard(
            visitor: visitor,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VisitorDetailScreen(visitorId: visitor.id),
                ),
              ).then((_) => _loadVisitors());
            },
          );
        },
      ),
    );
  }

  Widget _buildError(AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: p.danger),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loadVisitors,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showPreApproveSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PreApproveBottomSheet(
        onCreated: () => _loadVisitors(),
      ),
    );
  }
}
