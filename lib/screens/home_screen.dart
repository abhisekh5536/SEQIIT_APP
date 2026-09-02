import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/complaint_models.dart';
import '../models/notice_models.dart';
import '../models/society_models.dart';
import '../services/app_session.dart';
import '../services/complaints_service.dart';
import '../services/notifications_service.dart';
import '../services/notices_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/home_widgets.dart';
import '../widgets/skeleton_loader.dart';
import 'join_society_screen.dart';
import 'notices/notice_detail_screen.dart';
import 'request_status_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _quickActions = [
    QuickAction(
      label: 'Dues',
      icon: Icons.payments_rounded,
      route: '/maintenance',
    ),
    QuickAction(
      label: 'Amenity',
      icon: Icons.event_seat_rounded,
      route: '/facilities',
    ),
    QuickAction(
      label: 'Guests',
      icon: Icons.qr_code_rounded,
      route: '/visitors',
    ),
    QuickAction(
      label: 'Helpdesk',
      icon: Icons.support_agent_rounded,
      route: '/complaints',
    ),
  ];

  static List<SocietyService> _servicesFor(bool isAdmin) => isAdmin
      ? [
          const SocietyService(
            title: 'Approvals',
            subtitle: 'Resident requests',
            icon: Icons.how_to_reg_outlined,
            route: '/admin-approvals',
            colorIndex: 0,
          ),
          const SocietyService(
            title: 'Directory',
            subtitle: 'Residents list',
            icon: Icons.contacts_outlined,
            route: '/directory',
            colorIndex: 7,
          ),
          const SocietyService(
            title: 'Flats & Blocks',
            subtitle: 'Units register',
            icon: Icons.domain_outlined,
            route: '/flats-management',
            colorIndex: 3,
          ),
          const SocietyService(
            title: 'Maintenance',
            subtitle: 'Dues & billing',
            icon: Icons.payments_outlined,
            route: '/maintenance',
            colorIndex: 0,
          ),
          const SocietyService(
            title: 'Visitors',
            subtitle: 'Gate & security logs',
            icon: Icons.qr_code_2_outlined,
            route: '/visitors',
            colorIndex: 1,
          ),
          const SocietyService(
            title: 'Complaints',
            subtitle: 'Track & resolve',
            icon: Icons.support_agent_outlined,
            route: '/complaints',
            colorIndex: 2,
          ),
          const SocietyService(
            title: 'Staff',
            subtitle: 'Roster & guards',
            icon: Icons.engineering_outlined,
            route: '/staff',
            colorIndex: 1,
          ),
          const SocietyService(
            title: 'Facilities',
            subtitle: 'Hall, gym & bookings',
            icon: Icons.event_seat_outlined,
            route: '/facilities',
            colorIndex: 4,
          ),
          const SocietyService(
            title: 'Vehicles',
            subtitle: 'Parking & allotment',
            icon: Icons.directions_car_outlined,
            route: '/admin-vehicles',
            colorIndex: 5,
          ),
          const SocietyService(
            title: 'Meetings',
            subtitle: 'AGM & minutes',
            icon: Icons.groups_outlined,
            route: '/meetings',
            colorIndex: 3,
          ),
          const SocietyService(
            title: 'Notices',
            subtitle: 'Board circulars',
            icon: Icons.campaign_outlined,
            route: '/notices',
            colorIndex: 6,
          ),
        ]
      : [
          const SocietyService(
            title: 'Maintenance',
            subtitle: 'Pay dues & ledger',
            icon: Icons.payments_outlined,
            route: '/maintenance',
            colorIndex: 0,
          ),
          const SocietyService(
            title: 'Visitors',
            subtitle: 'Gate pass & guests',
            icon: Icons.qr_code_2_outlined,
            route: '/visitors',
            colorIndex: 1,
          ),
          const SocietyService(
            title: 'Helpdesk',
            subtitle: 'Raise complaints',
            icon: Icons.support_agent_outlined,
            route: '/complaints',
            colorIndex: 2,
          ),
          const SocietyService(
            title: 'My Flat',
            subtitle: 'Family & household',
            icon: Icons.home_outlined,
            route: '/my-flat',
            colorIndex: 3,
          ),
          const SocietyService(
            title: 'Facilities',
            subtitle: 'Club, pool & gym',
            icon: Icons.event_seat_outlined,
            route: '/facilities',
            colorIndex: 4,
          ),
          const SocietyService(
            title: 'Vehicles',
            subtitle: 'Parking & tags',
            icon: Icons.directions_car_outlined,
            route: '/profile',
            colorIndex: 5,
          ),
          const SocietyService(
            title: 'Notices',
            subtitle: 'Board circulars',
            icon: Icons.campaign_outlined,
            route: '/notices',
            colorIndex: 6,
          ),
          const SocietyService(
            title: 'Security',
            subtitle: 'Emergency contacts',
            icon: Icons.shield_outlined,
            route: '/settings',
            colorIndex: 7,
          ),
        ];

  List<NoticeRecord> _liveNotices = [];
  int _allNoticesCount = 0;
  int _unreadNoticesCount = 0;
  int _openRequestsCount = 0;
  final int _visitorsToday = 12;
  bool _isLoadingHome = true;

  String? _badgeFor(String title) {
    return switch (title.toLowerCase()) {
      'notices' => _unreadNoticesCount > 0 ? '$_unreadNoticesCount new' : null,
      'approvals' => AppSession.instance.pendingApprovalsCount > 0
          ? '${AppSession.instance.pendingApprovalsCount}'
          : null,
      'complaints' || 'helpdesk' =>
        _openRequestsCount > 0 ? '$_openRequestsCount open' : null,
      'visitors' => '$_visitorsToday today',
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_onSessionChanged);
    _loadHomeData();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted && AppSession.instance.isLoaded) {
      _loadHomeData(skipSessionLoad: true);
    }
  }

  Future<void> _loadHomeData({bool skipSessionLoad = false}) async {
    try {
      if (!skipSessionLoad &&
          !AppSession.instance.isLoaded &&
          !AppSession.instance.isLoading) {
        await AppSession.instance.load();
      }

      final notices = await NoticesService.instance.fetchResidentNotices();
      int openReqs = 0;
      try {
        final session = AppSession.instance;
        if (session.isAdmin) {
          final complaints = await ComplaintsService.instance
              .fetchSocietyComplaints();
          openReqs = complaints
              .where(
                (c) =>
                    c.status == ComplaintStatus.open ||
                    c.status == ComplaintStatus.inProgress ||
                    c.status == ComplaintStatus.reopened,
              )
              .length;
        } else {
          final complaints = await ComplaintsService.instance
              .fetchResidentComplaints();
          openReqs = complaints
              .where(
                (c) =>
                    c.status == ComplaintStatus.open ||
                    c.status == ComplaintStatus.inProgress ||
                    c.status == ComplaintStatus.reopened,
              )
              .length;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _liveNotices = notices.take(3).toList();
          _allNoticesCount = notices.length;
          _unreadNoticesCount = notices.where((n) => !n.isReadByMe).length;
          _openRequestsCount = openReqs;
          _isLoadingHome = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHome = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;

        if (!session.isLoaded || _isLoadingHome) {
          return const Scaffold(
            body: HomeScreenSkeleton(),
          );
        }

        // If user is unlisted (neither admin nor linked resident), show claim flow
        if (session.isUnlinkedUser) {
          if (session.pendingJoinRequest != null) {
            return RequestStatusScreen(request: session.pendingJoinRequest!);
          }
          return const JoinSocietyScreen();
        }

        final services = _servicesFor(session.isAdmin);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, p)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: HeroCarousel(
                      slides: _buildHeroSlides(context, session),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: QuickActionRail(
                      actions: _quickActions,
                      onSelected: (action) =>
                          Navigator.pushNamed(context, action.route),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverToBoxAdapter(child: _buildStats(context, p)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: const SectionHeader(title: 'Services'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final service = services[index];
                        return ServiceTile(
                          service: service,
                          accent: service.colorIndex != null
                              ? p.featureColor(service.colorIndex!)
                              : p.featureColor(index),
                          badge: _badgeFor(service.title),
                        );
                      },
                      childCount: services.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 118,
                        ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'Latest updates',
                      actionLabel: 'View all',
                      onAction: () => Navigator.pushNamed(
                        context,
                        '/notices',
                      ).then((_) => _loadHomeData()),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  sliver: _buildLatestUpdatesList(context, p),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Slides for the hero carousel. The first is always the balance card;
  /// the rest reflect things a resident (or committee member) would
  /// realistically need at a glance today. Each slide is a distinct
  /// archetype (wallet, ticket, booking, status, notice) so the deck never
  /// reads as the same template repeated.
  List<Widget> _buildHeroSlides(BuildContext context, AppSession session) {
    final slides = <Widget>[
      HeroBalanceCard(
        societyName: session.societyName,
        period: 'August 2026',
        amount: '₹4,850',
        dueCaption: session.flatSubtitle != null
            ? 'Due by 15 August · ${session.flatSubtitle}'
            : 'Due by 15 August · Flat Details Pending',
        onPay: () => Navigator.pushNamed(context, '/maintenance'),
        onLedger: () => Navigator.pushNamed(context, '/maintenance'),
        onReceipts: () => Navigator.pushNamed(context, '/maintenance'),
      ),
      HeroTicketCard(
        guestName: 'Mr. & Mrs. Sharma',
        time: '6:30',
        period: 'PM',
        dayLabel: 'Today',
        location: 'Tower B · Main gate',
        passNumber: 'GP-4471',
        onShow: () => Navigator.pushNamed(context, '/visitors'),
        onDetails: () => Navigator.pushNamed(context, '/visitors'),
      ),
      HeroBookingCard(
        dateDay: '6',
        dateMonth: 'SEP',
        eyebrow: 'Booking confirmed',
        title: 'Community Hall',
        timeRange: 'Sat 6 Sep · 6:00–9:00 PM',
        detail: "Aarav's birthday",
        onManage: () => Navigator.pushNamed(context, '/facilities'),
        onRules: () => Navigator.pushNamed(context, '/facilities'),
      ),
      if (session.isAdmin)
        HeroStatusCard(
          pill: 'Approvals',
          eyebrow: 'Awaiting your review',
          title:
              '$_openRequestsCount open ${_openRequestsCount == 1 ? 'request' : 'requests'}',
          detail: 'Gate passes, maintenance exceptions and vendor notes',
          steps: const ['Raised', 'In review', 'Resolved'],
          current: 1,
          actionLabel: 'Review now',
          onAction: () => Navigator.pushNamed(context, '/admin-approvals'),
        )
      else
        HeroStatusCard(
          pill: 'Request #C-118',
          eyebrow: 'Plumbing · Tower B, Flat 204',
          title: 'In progress',
          detail: 'Rahul from the site team assigned · ETA today, 4–6 PM',
          steps: const ['Received', 'In progress', 'Resolved'],
          current: 1,
          actionLabel: 'Track request',
          onAction: () => Navigator.pushNamed(context, '/complaints'),
          secondaryActionLabel: 'History',
          onSecondaryAction: () => Navigator.pushNamed(context, '/complaints'),
        ),
      if (_liveNotices.isNotEmpty)
        HeroNoticeCard(
          category: _liveNotices.first.category.label,
          eyebrow: 'Society notice',
          title: _liveNotices.first.title,
          snippet: _liveNotices.first.body,
          meta: _liveNotices.first.relativeTime,
          pinned: _liveNotices.first.isPinned,
          onRead: () {
            final notice = _liveNotices.first;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoticeDetailScreen(notice: notice),
              ),
            ).then((_) => _loadHomeData());
          },
        ),
    ];
    return slides;
  }

  Widget _buildLatestUpdatesList(BuildContext context, AppPaletteData p) {
    if (_liveNotices.isNotEmpty) {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final notice = _liveNotices[index];
          final catColor = notice.category.color(p);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoticeDetailScreen(notice: notice),
                  ),
                ).then((_) => _loadHomeData());
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
                      color: p.shadow.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: catColor.withValues(alpha: 0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (notice.isPinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 13,
                                  color: p.warning,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  notice.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: notice.isReadByMe
                                            ? FontWeight.w600
                                            : FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            notice.category.label,
                            style: TextStyle(
                              color: catColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notice.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (notice.isEvent &&
                            notice.formattedEventBadge != null) ...[
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: p.secondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            notice.formattedEventBadge!,
                            style: TextStyle(
                              color: p.secondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ] else ...[
                          Text(
                            notice.relativeTime,
                            style: TextStyle(
                              color: p.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (!notice.isReadByMe)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: p.warning,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: p.warning.withValues(alpha: 0.45),
                                  blurRadius: 5,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }, childCount: _liveNotices.length),
      );
    }

    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 36, color: p.textTertiary),
            const SizedBox(height: 8),
            Text(
              'No active notices right now',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'All community updates and circulars will appear here',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: p.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    final session = AppSession.instance;
    final displayName = session.displayName ?? (session.isAdmin ? 'Admin' : 'Resident');
    final flatLine = session.flatSubtitle ??
        (session.isAdmin
            ? 'Society Administration'
            : (session.societyCity != null && session.societyCity!.isNotEmpty
                ? session.societyCity!
                : ''));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppSession.instance.societyName.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: p.primary,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_greeting()}, $displayName',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(flatLine, style: textTheme.bodySmall),
              ],
            ),
          ),
          _notificationBell(context, p),
          const SizedBox(width: 10),
          _avatar(context, p),
        ],
      ),
    );
  }

  Widget _notificationBell(BuildContext context, AppPaletteData p) {
    return AnimatedBuilder(
      animation: NotificationsService.instance,
      builder: (context, _) {
        final unreadCount = NotificationsService.instance.unreadCount;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pushNamed(context, '/notifications');
              },
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              style: IconButton.styleFrom(
                backgroundColor: p.card,
                side: BorderSide(color: p.hairline),
                padding: const EdgeInsets.all(10),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: p.warning,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.card, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _avatar(BuildContext context, AppPaletteData p) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/profile'),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.primary, p.secondary],
          ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: p.card, width: 2),
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildStats(BuildContext context, AppPaletteData p) {
    final hour = DateTime.now().hour;
    final hasOpen = _openRequestsCount > 0;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.people_alt_outlined,
            value: '$_visitorsToday',
            label: 'Visitors today',
            hint: hour < 18 ? 'since 6:00 AM' : 'gate log, full day',
            accent: p.secondary,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(context, '/visitors');
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.campaign_outlined,
            value: '$_allNoticesCount',
            label: 'Notices',
            hint: _unreadNoticesCount > 0
                ? '$_unreadNoticesCount unread'
                : 'all caught up',
            accent: p.success,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(
                context,
                '/notices',
              ).then((_) => _loadHomeData());
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: hasOpen ? Icons.timelapse_rounded : Icons.task_alt_rounded,
            value: '$_openRequestsCount',
            label: hasOpen ? 'Open requests' : 'All resolved',
            hint: hasOpen ? 'avg reply under a day' : 'helpdesk history kept',
            accent: hasOpen ? p.warning : p.success,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(
                context,
                '/complaints',
              ).then((_) => _loadHomeData());
            },
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
