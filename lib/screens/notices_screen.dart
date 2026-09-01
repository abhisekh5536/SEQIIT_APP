import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/notice_models.dart';
import '../services/app_session.dart';
import '../services/notices_service.dart';
import '../theme/app_theme.dart';
import '../widgets/skeleton_loader.dart';
import 'notices/admin_notice_detail_screen.dart';
import 'notices/create_edit_notice_screen.dart';
import 'notices/notice_detail_screen.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  NoticeCategory? _selectedCategory;
  List<NoticeRecord> _residentNotices = [];
  List<NoticeRecord> _upcomingEvents = [];
  List<NoticeRecord> _adminNotices = [];
  NoticeStats _noticeStats = const NoticeStats();
  bool _isLoading = true;
  final String _searchQuery = '';

  // Admin view toggle (0: Resident Feed, 1: Admin Management)
  int _adminViewMode = 0;
  NoticeStatus? _adminStatusFilter;

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_onSessionChanged);
    _loadNotices();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted && AppSession.instance.isLoaded) {
      _loadNotices(skipSessionLoad: true);
    }
  }

  Future<void> _loadNotices({bool skipSessionLoad = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    if (!skipSessionLoad && !AppSession.instance.isLoaded && !AppSession.instance.isLoading) {
      await AppSession.instance.load();
    }
    final isAdmin = AppSession.instance.isAdmin;

    try {
      if (isAdmin && _adminViewMode == 1) {
        final list = await NoticesService.instance.fetchSocietyNotices(
          statusFilter: _adminStatusFilter,
          categoryFilter: _selectedCategory,
          searchQuery: _searchQuery,
        );
        final stats = await NoticesService.instance.fetchNoticeStats();
        if (mounted) {
          setState(() {
            _adminNotices = list;
            _noticeStats = stats;
            _isLoading = false;
          });
        }
      } else {
        final list = await NoticesService.instance.fetchResidentNotices(
          categoryFilter: _selectedCategory,
        );
        final events = await NoticesService.instance.fetchUpcomingEvents();
        if (mounted) {
          setState(() {
            _residentNotices = list;
            _upcomingEvents = events;
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final isAdmin = AppSession.instance.isAdmin;

    if (_isLoading && _residentNotices.isEmpty && _adminNotices.isEmpty) {
      return const Scaffold(
        body: NoticesScreenSkeleton(),
      );
    }

    return Scaffold(
      floatingActionButton: (isAdmin && _adminViewMode == 1)
          ? FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateEditNoticeScreen()),
                ).then((_) => _loadNotices());
              },
              backgroundColor: p.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                'Post Notice',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadNotices,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, p, isAdmin),
                      const SizedBox(height: 12),
                      if (isAdmin) _buildAdminModeSelector(context, p),
                    ],
                  ),
                ),
              ),

              if (_adminViewMode == 1 && isAdmin) ...[
                SliverToBoxAdapter(child: _buildAdminStatusChips(context, p)),
                SliverToBoxAdapter(child: _buildCategoryChips(context, p)),
                _buildAdminNoticesList(context, p),
              ] else ...[
                // Resident Feed
                if (_upcomingEvents.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildUpcomingEventsSection(context, p),
                  ),
                SliverToBoxAdapter(child: _buildCategoryChips(context, p)),
                _buildResidentNoticesList(context, p),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppPaletteData p, bool isAdmin) {
    final textTheme = Theme.of(context).textTheme;
    final unreadCount = _residentNotices.where((n) => !n.isReadByMe).length;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notices',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isAdmin
                    ? 'Society circulars and broadcast management'
                    : 'Board updates and community alerts',
                style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        if (!isAdmin && unreadCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE68A00).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE68A00).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 14, color: Color(0xFFE68A00)),
                const SizedBox(width: 5),
                Text(
                  '$unreadCount Unread',
                  style: const TextStyle(
                    color: Color(0xFFE68A00),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (isAdmin && _adminViewMode == 0)
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: p.primary,
            tooltip: 'Create Notice',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateEditNoticeScreen()),
              ).then((_) => _loadNotices());
            },
          ),
      ],
    );
  }

  Widget _buildAdminModeSelector(BuildContext context, AppPaletteData p) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _adminViewMode = 0);
                _loadNotices();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _adminViewMode == 0 ? p.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Resident Feed',
                  style: TextStyle(
                    color: _adminViewMode == 0 ? Colors.white : p.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _adminViewMode = 1);
                _loadNotices();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _adminViewMode == 1 ? p.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Manage Notices (${_noticeStats.total})',
                  style: TextStyle(
                    color: _adminViewMode == 1 ? Colors.white : p.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEventsSection(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(Icons.event_available_rounded, size: 18, color: p.secondary),
              const SizedBox(width: 8),
              Text(
                'Upcoming Events',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 124,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _upcomingEvents.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (ctx, index) {
              final event = _upcomingEvents[index];
              return _buildEventCardItem(ctx, p, event);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEventCardItem(BuildContext context, AppPaletteData p, NoticeRecord event) {
    final textTheme = Theme.of(context).textTheme;
    final start = event.eventStartsAt?.toLocal() ?? DateTime.now();
    final monthStr = DateFormat('MMM').format(start).toUpperCase();
    final dayStr = DateFormat('d').format(start);
    final timeStr = DateFormat('h:mm a').format(start);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NoticeDetailScreen(notice: event)),
        ).then((_) => _loadNotices());
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              p.secondary.withValues(alpha: 0.12),
              p.card,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.secondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 52,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.secondary.withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    monthStr,
                    style: TextStyle(
                      color: p.secondary,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    dayStr,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: p.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  if (event.eventVenue != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.eventVenue!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textTertiary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(BuildContext context, AppPaletteData p) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: _selectedCategory == null,
            onSelected: (_) {
              setState(() => _selectedCategory = null);
              _loadNotices();
            },
            selectedColor: p.primary.withValues(alpha: 0.18),
            labelStyle: TextStyle(
              color: _selectedCategory == null ? p.primary : p.textSecondary,
              fontWeight: _selectedCategory == null ? FontWeight.w700 : FontWeight.w500,
            ),
            backgroundColor: p.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _selectedCategory == null ? p.primary : p.hairline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ...NoticeCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            final catColor = cat.color(p);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cat.icon,
                      size: 14,
                      color: isSelected ? catColor : p.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(cat.label),
                  ],
                ),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedCategory = isSelected ? null : cat);
                  _loadNotices();
                },
                selectedColor: catColor.withValues(alpha: 0.16),
                labelStyle: TextStyle(
                  color: isSelected ? catColor : p.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                backgroundColor: p.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? catColor : p.hairline,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAdminStatusChips(BuildContext context, AppPaletteData p) {
    final statusList = [
      (null, 'All (${_noticeStats.total})'),
      (NoticeStatus.published, 'Published (${_noticeStats.published})'),
      (NoticeStatus.scheduled, 'Scheduled (${_noticeStats.scheduled})'),
      (NoticeStatus.draft, 'Draft (${_noticeStats.draft})'),
      (NoticeStatus.expired, 'Expired (${_noticeStats.expired})'),
      (NoticeStatus.archived, 'Archived (${_noticeStats.archived})'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: statusList.map((item) {
          final isSelected = _adminStatusFilter == item.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(item.$2),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _adminStatusFilter = item.$1);
                _loadNotices();
              },
              selectedColor: p.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              backgroundColor: p.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? p.primary : p.hairline,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResidentNoticesList(BuildContext context, AppPaletteData p) {
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_residentNotices.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.campaign_outlined, size: 56, color: p.textTertiary),
              const SizedBox(height: 12),
              Text(
                'No notices posted yet',
                style: TextStyle(color: p.textSecondary, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final notice = _residentNotices[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildResidentNoticeCard(context, p, notice),
            );
          },
          childCount: _residentNotices.length,
        ),
      ),
    );
  }

  Widget _buildResidentNoticeCard(BuildContext context, AppPaletteData p, NoticeRecord notice) {
    final textTheme = Theme.of(context).textTheme;
    final catColor = notice.category.color(p);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NoticeDetailScreen(notice: notice)),
        ).then((_) => _loadNotices());
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: notice.isPinned
                ? p.warning.withValues(alpha: 0.5)
                : p.hairline,
            width: notice.isPinned ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Category badge, Pinned tag, Unread indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(notice.category.icon, size: 12, color: catColor),
                      const SizedBox(width: 4),
                      Text(
                        notice.category.label,
                        style: TextStyle(
                          color: catColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (notice.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin_rounded, size: 13, color: p.warning),
                ],
                if (notice.targetType == NoticeTargetType.block) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.cardMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      notice.targetBlockName ?? 'Block Specific',
                      style: TextStyle(color: p.textTertiary, fontSize: 10),
                    ),
                  ),
                ],
                const Spacer(),
                if (!notice.isReadByMe)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE68A00),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              notice.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: notice.isReadByMe ? FontWeight.w600 : FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),

            // Body snippet
            Text(
              notice.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: p.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),

            // Bottom row: Event badge or Relative time, Ack status
            Row(
              children: [
                if (notice.isEvent && notice.formattedEventBadge != null) ...[
                  Icon(Icons.schedule_rounded, size: 13, color: p.secondary),
                  const SizedBox(width: 4),
                  Text(
                    notice.formattedEventBadge!,
                    style: TextStyle(
                      color: p.secondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ] else ...[
                  Text(
                    notice.relativeTime,
                    style: TextStyle(color: p.textTertiary, fontSize: 12),
                  ),
                ],
                if (notice.attachmentUrl != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.attach_file_rounded, size: 13, color: p.textTertiary),
                ],
                const Spacer(),
                if (notice.requiresAcknowledgment) ...[
                  if (notice.isAcknowledgedByMe)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: p.success),
                        const SizedBox(width: 4),
                        Text(
                          'Acknowledged',
                          style: TextStyle(
                            color: p.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Ack Required',
                        style: TextStyle(
                          color: p.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminNoticesList(BuildContext context, AppPaletteData p) {
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_adminNotices.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_outlined, size: 56, color: p.textTertiary),
              const SizedBox(height: 12),
              Text(
                'No notices matching filter',
                style: TextStyle(color: p.textSecondary, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final notice = _adminNotices[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildAdminNoticeCard(context, p, notice),
            );
          },
          childCount: _adminNotices.length,
        ),
      ),
    );
  }

  Widget _buildAdminNoticeCard(BuildContext context, AppPaletteData p, NoticeRecord notice) {
    final textTheme = Theme.of(context).textTheme;
    final catColor = notice.category.color(p);
    final statusColor = notice.status.color(p);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminNoticeDetailScreen(notice: notice)),
        ).then((_) => _loadNotices());
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    notice.status.label.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    notice.category.label,
                    style: TextStyle(
                      color: catColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (notice.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin_rounded, size: 13, color: p.warning),
                ],
                const Spacer(),
                Text(
                  notice.relativeTime,
                  style: TextStyle(color: p.textTertiary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text(
              notice.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),

            Text(
              notice.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 10),

            // Read stats & Ack stats bar
            Row(
              children: [
                Icon(Icons.visibility_outlined, size: 14, color: p.primary),
                const SizedBox(width: 4),
                Text(
                  '${notice.readCount}/${notice.totalEligibleResidents} read',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (notice.requiresAcknowledgment) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check_circle_outline, size: 14, color: p.success),
                  const SizedBox(width: 4),
                  Text(
                    '${notice.ackCount} ack',
                    style: TextStyle(
                      color: p.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}