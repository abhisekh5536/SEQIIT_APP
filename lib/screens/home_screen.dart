import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/complaint_models.dart';
import '../models/notice_models.dart';
import '../models/society_models.dart';
import '../models/visitor_models.dart';
import '../services/app_session.dart';
import '../services/complaints_service.dart';
import '../services/home_summary_service.dart';
import '../services/marketplace_service.dart';
import '../services/notifications_service.dart';
import '../services/notices_service.dart';
import '../services/resident_documents_service.dart';
import '../services/security_service.dart';
import '../services/visitors_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/home_widgets.dart';
import '../widgets/skeleton_loader.dart';
import 'complaints/resident_complaint_detail_screen.dart';
import 'join_society_screen.dart';
import 'marketplace/resident/listing_detail_screen.dart';
import 'notices/notice_detail_screen.dart';
import 'request_status_screen.dart';
import 'security/widgets/admin_sos_alert_dialog.dart';
import 'security/widgets/sos_dialog.dart';
import 'visitors/visitor_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Sentinel route: the SOS quick action opens the emergency sheet in place
  /// instead of navigating, so help is one tap away.
  static const _sosAction = 'sos';

  static const _quickActions = [
    QuickAction(
      label: 'Dues',
      icon: Icons.payments_rounded,
      route: '/maintenance',
    ),
    QuickAction(
      label: 'SOS',
      icon: Icons.crisis_alert_rounded,
      route: _sosAction,
      isEmergency: true,
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

  // Guards have their own shell (GuardShell) and never see this screen.
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
            title: 'Guards',
            subtitle: 'Gate staff & gates',
            icon: Icons.local_police_outlined,
            route: '/security-staff',
            colorIndex: 1,
          ),
          const SocietyService(
            title: 'Facilities',
            subtitle: 'Hall, gym & amenities',
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
          const SocietyService(
            title: 'Security',
            subtitle: 'Emergency & SOS',
            icon: Icons.shield_outlined,
            route: '/security',
            colorIndex: 7,
          ),
          const SocietyService(
            title: 'Documents',
            subtitle: 'Tenant & owner KYC',
            icon: Icons.folder_shared_outlined,
            route: '/documents',
            colorIndex: 4,
          ),
          const SocietyService(
            title: 'Marketplace',
            subtitle: 'Moderate listings',
            icon: Icons.storefront_outlined,
            route: '/marketplace',
            colorIndex: 2,
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
            subtitle: 'Parking & slots',
            icon: Icons.directions_car_outlined,
            route: '/vehicles',
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
            route: '/security',
            colorIndex: 7,
          ),
          const SocietyService(
            title: 'Documents',
            subtitle: 'Agreement & ID proofs',
            icon: Icons.folder_shared_outlined,
            route: '/documents',
            colorIndex: 4,
          ),
          const SocietyService(
            title: 'Marketplace',
            subtitle: 'Buy & sell locally',
            icon: Icons.storefront_outlined,
            route: '/marketplace',
            colorIndex: 2,
          ),
        ];

  List<NoticeRecord> _liveNotices = [];
  int _allNoticesCount = 0;
  int _unreadNoticesCount = 0;
  int _openRequestsCount = 0;
  int _visitorsToday = 0;
  int _pendingVisitorsCount = 0;
  bool _isLoadingHome = true;

  // Hero carousel data — every card is backed by these, nothing static.
  HomeSummary _summary = const HomeSummary();
  MarketplaceTeaser _market = MarketplaceTeaser.disabled;
  VisitorRecord? _guestPass;
  ComplaintRecord? _activeRequest; // resident: their most recent open one
  List<ComplaintRecord> _openComplaints = const []; // admin: all open ones
  String? _latestNotificationId;
  StreamSubscription? _sosSub;

  String? _badgeFor(String title) {
    return switch (title.toLowerCase()) {
      'notices' => _unreadNoticesCount > 0 ? '$_unreadNoticesCount new' : null,
      'approvals' => AppSession.instance.pendingApprovalsCount > 0
          ? '${AppSession.instance.pendingApprovalsCount}'
          : null,
      'complaints' || 'helpdesk' =>
        _openRequestsCount > 0 ? '$_openRequestsCount open' : null,
      'visitors' => _pendingVisitorsCount > 0
          ? '$_pendingVisitorsCount pending'
          : '$_visitorsToday today',
      'marketplace' => AppSession.instance.isAdmin &&
              MarketplaceService.instance.pendingReportsCount > 0
          ? '${MarketplaceService.instance.pendingReportsCount} reported'
          : null,
      'documents' => AppSession.instance.isAdmin
          ? (ResidentDocumentsService.instance.adminPendingCount > 0
              ? '${ResidentDocumentsService.instance.adminPendingCount} to verify'
              : null)
          : (ResidentDocumentsService.instance.attentionCount > 0
              ? 'Action needed'
              : null),
      'security' => SecurityService.instance.activeSosAlerts.isNotEmpty
          ? '🚨 ${SecurityService.instance.activeSosAlerts.length} SOS'
          : null,
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    AppSession.instance.addListener(_onSessionChanged);
    VisitorsService.instance.addListener(_onVisitorsChanged);
    NotificationsService.instance.addListener(_onNotificationsChanged);
    SecurityService.instance.addListener(_onSecurityChanged);
    MarketplaceService.instance.addListener(_onSecurityChanged);
    ResidentDocumentsService.instance.addListener(_onSecurityChanged);
    _sosSub = SecurityService.instance.onSosAlertReceived.listen((alert) {
      if (!mounted) return;
      if (AppSession.instance.isAdmin && alert.isActive) {
        AdminSosAlertDialog.show(context, alert);
      }
      setState(() {});
    });
    _loadHomeData();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    VisitorsService.instance.removeListener(_onVisitorsChanged);
    NotificationsService.instance.removeListener(_onNotificationsChanged);
    SecurityService.instance.removeListener(_onSecurityChanged);
    MarketplaceService.instance.removeListener(_onSecurityChanged);
    ResidentDocumentsService.instance.removeListener(_onSecurityChanged);
    _sosSub?.cancel();
    super.dispose();
  }

  void _onSecurityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSessionChanged() {
    if (mounted && AppSession.instance.isLoaded) {
      _loadHomeData(skipSessionLoad: true);
    }
  }

  void _onVisitorsChanged() {
    if (mounted) {
      _loadHomeData(skipSessionLoad: true);
    }
  }

  void _onNotificationsChanged() {
    if (!mounted) return;
    // Every module's alert lands in the (live) bell first. When a new one
    // arrives — a notice, a complaint update, a join request — reload the
    // carousel so its cards follow. Compare the newest id rather than
    // reloading on every notify: _loadHomeData itself refreshes the bell,
    // which would otherwise loop.
    final list = NotificationsService.instance.notifications;
    final newest = list.isEmpty ? null : list.first.id;
    final previous = _latestNotificationId;
    _latestNotificationId = newest;
    if (previous != null && newest != null && newest != previous) {
      _loadHomeData(skipSessionLoad: true);
    } else {
      setState(() {});
    }
  }

  Future<void> _loadHomeData({bool skipSessionLoad = false}) async {
    try {
      if (!skipSessionLoad &&
          !AppSession.instance.isLoaded &&
          !AppSession.instance.isLoading) {
        await AppSession.instance.load();
      }

      ResidentDocumentsService.instance.refreshCounts();
      final session = AppSession.instance;
      // Carousel data that does not depend on anything below; started now
      // so it loads in parallel with the notices/complaints queries.
      final summaryFuture =
          HomeSummaryService.instance.fetchSummary(session.societyId);
      final marketFuture = HomeSummaryService.instance.fetchMarketplaceTeaser();
      final guestPassFuture = VisitorsService.instance
          .fetchNextGuestPass()
          .catchError((Object _) => null);

      final notices = await NoticesService.instance.fetchResidentNotices();
      int openReqs = 0;
      ComplaintRecord? activeRequest;
      List<ComplaintRecord> openComplaints = const [];
      bool needsAction(ComplaintRecord c) =>
          c.status == ComplaintStatus.open ||
          c.status == ComplaintStatus.inProgress ||
          c.status == ComplaintStatus.reopened;
      try {
        if (session.isAdmin) {
          if (session.societyId != null) {
            MarketplaceService.instance
                .refreshPendingReportsCount(session.societyId!);
          }
          final complaints = await ComplaintsService.instance
              .fetchSocietyComplaints();
          openComplaints = complaints.where(needsAction).toList();
          openReqs = openComplaints.length;
        } else {
          final complaints = await ComplaintsService.instance
              .fetchResidentComplaints();
          openReqs = complaints.where(needsAction).length;
          // The Request card follows the resident's latest live complaint,
          // including one marked resolved that still awaits their confirm.
          final live = complaints.where((c) => c.isActive).toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          activeRequest = live.isEmpty ? null : live.first;
        }
      } catch (_) {}

      // Load today's visitor count & pending approval count
      int visitorsToday = 0;
      int pendingVisitors = 0;
      try {
        final results = await Future.wait([
          VisitorsService.instance.getTodaysVisitorCount(),
          VisitorsService.instance.getPendingApprovalCount(),
        ]);
        visitorsToday = results[0];
        pendingVisitors = results[1];
      } catch (_) {}

      // Refresh and reconcile notifications to keep unread bell dot in sync
      NotificationsService.instance.fetchNotifications();

      final summary = await summaryFuture;
      final market = await marketFuture;
      final guestPass = await guestPassFuture;

      if (mounted) {
        setState(() {
          _liveNotices = notices.take(3).toList();
          _allNoticesCount = notices.length;
          _unreadNoticesCount = notices.where((n) => !n.isReadByMe).length;
          _openRequestsCount = openReqs;
          _visitorsToday = visitorsToday;
          _pendingVisitorsCount = pendingVisitors;
          _summary = summary;
          _market = market;
          _guestPass = guestPass;
          _activeRequest = activeRequest;
          _openComplaints = openComplaints;
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
                if (_pendingVisitorsCount > 0)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: InkWell(
                        onTap: () => Navigator.pushNamed(context, '/visitors')
                            .then((_) => _loadHomeData()),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: p.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: p.warning.withValues(alpha: 0.4),
                                width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: p.warning.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.door_front_door_rounded,
                                    color: p.warning, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_pendingVisitorsCount Visitor${_pendingVisitorsCount > 1 ? 's' : ''} at Gate',
                                      style: TextStyle(
                                        color: p.warning,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Waiting for your entry approval',
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: p.warning,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Review',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: QuickActionRail(
                      actions: _quickActions,
                      onSelected: _onQuickAction,
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

  void _onQuickAction(QuickAction action) {
    if (action.route != _sosAction) {
      Navigator.pushNamed(context, action.route);
      return;
    }
    HapticFeedback.heavyImpact();
    // SOS is raised against a flat; accounts without one (e.g. admins not
    // living in the society) go to the Security hub instead.
    if (AppSession.instance.myResidences.isEmpty) {
      Navigator.pushNamed(context, '/security');
      return;
    }
    SosDialog.show(context);
  }

  /// Slides for the hero carousel — all backed by live data.
  ///
  /// The always-on cards come first in a fixed order: my flat / society,
  /// security desk, the society's newest marketplace post (when the
  /// marketplace is switched on) and the latest notice. After them, the
  /// cards that only exist while something is running for this user
  /// (approvals waiting, an open request, a guest pass).
  List<Widget> _buildHeroSlides(BuildContext context, AppSession session) {
    final hasFlat = session.myResidences.isNotEmpty;
    return [
      // ── Always on ────────────────────────────────────────────────
      session.isAdmin && !hasFlat
          ? _societySlide(context, session)
          : _myFlatSlide(context, session),
      _securitySlide(context, hasFlat),
      if (_market.enabled) _marketSlide(context),
      _noticeSlide(context),

      // ── Only while something is active ───────────────────────────
      if (session.isAdmin && session.pendingApprovalsCount > 0)
        _approvalsSlide(context, session.pendingApprovalsCount),
      if (session.isAdmin && _openComplaints.isNotEmpty)
        _adminRequestsSlide(context)
      else if (!session.isAdmin && _activeRequest != null)
        _residentRequestSlide(context, _activeRequest!),
      if (_guestPass != null) _guestPassSlide(context, _guestPass!),
    ];
  }

  Future<void> _go(String route) =>
      Navigator.pushNamed(context, route).then((_) => _loadHomeData());

  Future<void> _push(Widget screen) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => screen),
      ).then((_) => _loadHomeData());

  Widget _approvalsSlide(BuildContext context, int count) {
    return HeroStatusCard(
      pill: 'Approvals',
      eyebrow: 'Resident join requests',
      title: '$count waiting for review',
      detail: count == 1
          ? 'A new resident cannot use the app until approved'
          : 'New residents cannot use the app until approved',
      steps: const ['Requested', 'In review', 'Approved'],
      current: 1,
      actionLabel: 'Review now',
      onAction: () => _go('/admin-approvals'),
    );
  }

  Widget _adminRequestsSlide(BuildContext context) {
    final open = _openComplaints
        .where((c) => c.status == ComplaintStatus.open)
        .length;
    final inProgress = _openComplaints
        .where((c) => c.status == ComplaintStatus.inProgress)
        .length;
    final reopened = _openComplaints
        .where((c) => c.status == ComplaintStatus.reopened)
        .length;
    final n = _openComplaints.length;
    final parts = [
      if (open > 0) '$open new',
      if (inProgress > 0) '$inProgress in progress',
      if (reopened > 0) '$reopened reopened',
    ];
    return HeroStatusCard(
      pill: 'Helpdesk',
      eyebrow: 'Requests needing action',
      title: '$n open ${n == 1 ? 'request' : 'requests'}',
      detail: parts.join(' · '),
      steps: const ['Raised', 'In progress', 'Resolved'],
      // Anything untouched keeps the stepper on "Raised".
      current: open + reopened > 0 ? 0 : 1,
      accent: reopened > 0 ? ComplaintStatus.reopened.foreground : null,
      actionLabel: 'Open helpdesk',
      onAction: () => _go('/complaints'),
    );
  }

  Widget _residentRequestSlide(BuildContext context, ComplaintRecord c) {
    final step = switch (c.status) {
      ComplaintStatus.inProgress => 1,
      ComplaintStatus.resolved => 2,
      _ => 0,
    };
    final detail = c.isResolved
        ? 'Marked resolved · confirm or reopen'
        : (c.adminNotes?.trim().isNotEmpty ?? false)
            ? 'Office: ${c.adminNotes!.trim()}'
            : 'Raised ${c.timeAgo}';
    return HeroStatusCard(
      pill: 'Request · ${c.category.label}',
      eyebrow: c.flatDisplay,
      title: c.title,
      detail: detail,
      steps: const ['Received', 'In progress', 'Resolved'],
      current: step,
      accent: c.status.foreground,
      actionLabel: c.isResolved ? 'Confirm or reopen' : 'Track request',
      onAction: () =>
          _push(ResidentComplaintDetailScreen(complaintId: c.id)),
      secondaryActionLabel: 'All',
      onSecondaryAction: () => _go('/complaints'),
    );
  }

  Widget _guestPassSlide(BuildContext context, VisitorRecord v) {
    final from = v.validFrom?.toLocal();
    final until = v.validUntil?.toLocal();
    final now = DateTime.now();

    String time;
    String period;
    String day;
    if (from == null || !from.isAfter(now)) {
      // Already usable: say until when.
      time = 'Now';
      period = '';
      day = until == null
          ? 'Valid any time'
          : 'Valid till ${_dayWord(until)}, ${DateFormat('h:mm a').format(until)}';
    } else {
      time = DateFormat('h:mm').format(from);
      period = DateFormat('a').format(from);
      day = _dayWord(from);
    }

    return HeroTicketCard(
      guestName: v.visitorName,
      time: time,
      period: period,
      dayLabel: day,
      location: '${v.flatDisplay} · ${v.category.label}',
      passNumber: v.approvalCode ?? '—',
      onShow: () => _push(VisitorDetailScreen(visitorId: v.id)),
      onDetails: () => _go('/visitors'),
    );
  }

  /// "Today", "Tomorrow" or "Sat 4 Oct".
  String _dayWord(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    final diff = DateUtils.dateOnly(d).difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEE d MMM').format(d);
  }

  Widget _noticeSlide(BuildContext context) {
    if (_liveNotices.isEmpty) {
      return HeroNoticeCard(
        category: 'Notice',
        eyebrow: 'Society notices',
        title: "You're all caught up",
        snippet: 'Circulars from the society office will appear here.',
        meta: 'Nothing new',
        actionLabel: 'View all',
        onRead: () => _go('/notices'),
      );
    }
    final notice = _liveNotices.first;
    // The pill names the card ("Notice"), not the notice's category: a
    // "Maintenance" category pill read as a leftover maintenance card.
    return HeroNoticeCard(
      category: 'Notice',
      eyebrow: notice.isReadByMe ? 'Latest notice' : 'New notice',
      title: notice.title,
      snippet: notice.body,
      meta: notice.relativeTime,
      pinned: notice.isPinned,
      onRead: () => _push(NoticeDetailScreen(notice: notice)),
    );
  }

  Widget _myFlatSlide(BuildContext context, AppSession session) {
    final primary = session.primaryResidence;
    final flat = primary == null ? null : session.flatOf(primary);
    final block = _summary.myBlock;
    final title = flat == null
        ? 'My Flat'
        : block == null
            ? 'Flat ${flat.flatNumber}'
            : '$block · Flat ${flat.flatNumber}';
    final subtitle = flat == null
        ? session.societyName
        : 'Floor ${flat.floorNumber} · ${flat.type} · ${session.societyName}';
    final slots = _summary.myParkingSlots;
    // Household = everyone registered in the flat, including this user.
    final household = session.householdMembers.length + 1;

    return HeroSummaryCard(
      pill: primary?.roleLabel ?? 'Resident',
      title: title,
      subtitle: subtitle,
      stats: [
        HeroStat('$household', household == 1 ? 'Member' : 'Members'),
        HeroStat('${session.myVehicles.length}',
            session.myVehicles.length == 1 ? 'Vehicle' : 'Vehicles'),
        HeroStat(
          slots.isEmpty ? '—' : slots.join(', '),
          slots.length > 1 ? 'Parking bays' : 'Parking bay',
        ),
      ],
      actionLabel: 'My Flat',
      actionIcon: Icons.home_rounded,
      onAction: () => _go('/my-flat'),
      secondaryActionLabel: 'Vehicles',
      onSecondaryAction: () => _go('/vehicles'),
    );
  }

  Widget _societySlide(BuildContext context, AppSession session) {
    final s = _summary;
    final total = s.totalFlats ?? 0;
    final occupied = s.occupiedFlats ?? 0;
    return HeroSummaryCard(
      pill: 'Society',
      title: session.societyName,
      subtitle: [
        if (s.blocks != null) '${s.blocks} ${s.blocks == 1 ? 'block' : 'blocks'}',
        if (session.societyCity != null) session.societyCity!,
      ].join(' · '),
      stats: [
        HeroStat('$occupied/$total', 'Flats occupied'),
        HeroStat('${s.activeResidents ?? 0}', 'Residents'),
        HeroStat('${s.guardsActive}', 'Guards'),
      ],
      actionLabel: 'Flats',
      actionIcon: Icons.domain_rounded,
      onAction: () => _go('/flats-management'),
      secondaryActionLabel: 'Directory',
      onSecondaryAction: () => _go('/directory'),
    );
  }

  Widget _securitySlide(BuildContext context, bool hasFlat) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final s = _summary;
    final sos = s.openSos;
    return HeroSummaryCard(
      pill: 'Security desk',
      alert: sos > 0 ? '$sos open SOS' : null,
      title: s.guardsActive > 0
          ? '${s.guardsActive} ${s.guardsActive == 1 ? 'guard' : 'guards'} on duty'
          : 'Security desk',
      subtitle: sos > 0
          ? 'An SOS is open — the security team has been alerted'
          : 'Help is one tap away, day or night',
      stats: [
        HeroStat('${s.gatesActive}', s.gatesActive == 1 ? 'Gate' : 'Gates'),
        HeroStat('${s.guardsActive}', 'On duty'),
        HeroStat('${s.emergencyContacts}', 'Emergency contacts'),
      ],
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: sos > 0
            ? [p.danger, p.danger.withValues(alpha: 0.75)]
            : [const Color(0xFF1F6F6B), const Color(0xFF2E9A8E)],
      ),
      accent: sos > 0 ? p.danger : p.accent,
      actionLabel: sos > 0 ? 'View SOS' : 'Emergency contacts',
      actionIcon: sos > 0 ? Icons.crisis_alert_rounded : Icons.call_rounded,
      onAction: () => _go('/security'),
      // SOS is raised against a flat; accounts without one use the hub.
      secondaryActionLabel: hasFlat && sos == 0 ? 'SOS' : null,
      onSecondaryAction: hasFlat && sos == 0
          ? () {
              HapticFeedback.heavyImpact();
              SosDialog.show(context);
            }
          : null,
    );
  }

  Widget _marketSlide(BuildContext context) {
    final l = _market.latest;
    if (l == null) {
      return HeroMarketCard.empty(
        onOpen: () => _go('/marketplace'),
        onBrowse: () => _go('/marketplace'),
      );
    }
    return HeroMarketCard(
      title: l.title,
      price: l.priceLabel,
      sellerLine: [
        if (l.sellerName != null) l.sellerName!,
        if (l.sellerFlatLabel != null) l.sellerFlatLabel!,
      ].join(' · '),
      postedAgo: l.postedAgo,
      imageUrl: l.coverImageUrl,
      onOpen: () => _push(ListingDetailScreen(listingId: l.id)),
      onBrowse: () => _go('/marketplace'),
    );
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
