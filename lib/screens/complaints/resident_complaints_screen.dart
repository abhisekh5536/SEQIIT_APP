import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/complaint_models.dart';
import '../../services/app_session.dart';
import '../../services/complaints_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import 'raise_complaint_screen.dart';
import 'resident_complaint_detail_screen.dart';

class ResidentComplaintsScreen extends StatefulWidget {
  final bool showBack;

  const ResidentComplaintsScreen({super.key, this.showBack = true});

  @override
  State<ResidentComplaintsScreen> createState() => _ResidentComplaintsScreenState();
}

class _ResidentComplaintsScreenState extends State<ResidentComplaintsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  List<ComplaintRecord> _complaints = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    NotificationsService.instance.markModuleAsRead('complaint');
    _loadComplaints();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await ComplaintsService.instance.fetchResidentComplaints();
      if (mounted) {
        setState(() {
          _complaints = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load complaints: $e';
          _loading = false;
        });
      }
    }
  }

  List<ComplaintRecord> get _activeComplaints =>
      _complaints.where((c) => c.status != ComplaintStatus.closed).toList();

  List<ComplaintRecord> get _closedComplaints =>
      _complaints.where((c) => c.status == ComplaintStatus.closed).toList();

  List<ComplaintRecord> get _resolvedAwaitingConfirmation =>
      _complaints.where((c) => c.status == ComplaintStatus.resolved).toList();

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top App Bar row
                    Row(
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
                        if (widget.showBack) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'My Complaints',
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                AppSession.instance.flatSubtitle ?? AppSession.instance.societyName,
                                style: textTheme.bodySmall?.copyWith(
                                  color: p.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _loadComplaints,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh',
                          style: IconButton.styleFrom(
                            backgroundColor: p.card,
                            side: BorderSide(color: p.hairline),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Attention Banner for Resolved complaints awaiting resident review
                    if (_resolvedAwaitingConfirmation.isNotEmpty) ...[
                      _buildResolvedActionBanner(context, p, textTheme),
                      const SizedBox(height: 16),
                    ],

                    // Segmented Tabs
                    Container(
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.hairline),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: Colors.white,
                        unselectedLabelColor: p.textSecondary,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: p.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Active'),
                                if (_activeComplaints.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${_activeComplaints.length}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Past / Closed'),
                                if (_closedComplaints.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: p.cardMuted,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${_closedComplaints.length}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: p.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
          body: _loading
              ? Center(child: CircularProgressIndicator(color: p.primary))
              : _error != null
                  ? _buildErrorView(context, p, textTheme)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildComplaintsList(_activeComplaints, isActiveTab: true, p: p, textTheme: textTheme),
                        _buildComplaintsList(_closedComplaints, isActiveTab: false, p: p, textTheme: textTheme),
                      ],
                    ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          HapticFeedback.lightImpact();
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (context) => const RaiseComplaintScreen()),
          );
          if (created == true) {
            _loadComplaints();
          }
        },
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Raise Complaint',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
    );
  }

  Widget _buildResolvedActionBanner(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    final count = _resolvedAwaitingConfirmation.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF2563EB),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1 ? '1 Complaint Resolved' : '$count Complaints Resolved',
                  style: textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Please confirm if the work was done or mark as not fixed.',
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF1E40AF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF1E40AF)),
        ],
      ),
    );
  }

  Widget _buildComplaintsList(
    List<ComplaintRecord> list, {
    required bool isActiveTab,
    required AppPaletteData p,
    required TextTheme textTheme,
  }) {
    if (list.isEmpty) {
      return _buildEmptyView(isActiveTab: isActiveTab, p: p, textTheme: textTheme);
    }

    return RefreshIndicator(
      onRefresh: _loadComplaints,
      color: p.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final complaint = list[index];
          return _buildComplaintCard(complaint, p: p, textTheme: textTheme);
        },
      ),
    );
  }

  Widget _buildComplaintCard(
    ComplaintRecord item, {
    required AppPaletteData p,
    required TextTheme textTheme,
  }) {
    final status = item.status;
    final cat = item.category;

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          HapticFeedback.lightImpact();
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => ResidentComplaintDetailScreen(complaintId: item.id),
            ),
          );
          if (changed == true) {
            _loadComplaints();
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isResolved ? const Color(0xFF93C5FD) : p.hairline,
              width: item.isResolved ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Category tag & Status Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 13, color: cat.color),
                        const SizedBox(width: 4),
                        Text(
                          cat.label,
                          style: TextStyle(
                            color: cat.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item.flatNumber != null)
                    Text(
                      item.flatDisplay,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  const Spacer(),
                  _buildStatusBadge(status),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                item.title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (item.description != null && item.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.description!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: p.textSecondary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Admin notes highlight if present
              if (item.adminNotes != null && item.adminNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_rounded, size: 14, color: Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Admin: ${item.adminNotes!}',
                          style: const TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Bottom row: Time Ago & Arrow
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: p.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    item.timeAgo,
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  if (item.photoUrl != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.photo_camera_rounded, size: 14, color: p.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Photo',
                      style: textTheme.bodySmall?.copyWith(
                        color: p.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        'View detail',
                        style: TextStyle(
                          color: p.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios_rounded, size: 11, color: p.primary),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ComplaintStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: status.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView({
    required bool isActiveTab,
    required AppPaletteData p,
    required TextTheme textTheme,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActiveTab ? Icons.check_circle_outline_rounded : Icons.folder_open_rounded,
                size: 40,
                color: p.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isActiveTab ? 'No active complaints' : 'No past complaints',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isActiveTab
                  ? 'Need help with plumbing, electrical, or society maintenance? Raise a complaint anytime.'
                  : 'Resolved and closed complaints will be archived here.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
            ),
            if (isActiveTab) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final created = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => const RaiseComplaintScreen()),
                  );
                  if (created == true) {
                    _loadComplaints();
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: p.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Raise Complaint', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: p.danger),
            const SizedBox(height: 16),
            Text(
              'Unable to load complaints',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loadComplaints,
              style: FilledButton.styleFrom(backgroundColor: p.primary),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
