import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/sample_data.dart';
import '../models/society_models.dart';
import '../services/app_session.dart';
import '../services/notifications_service.dart';
import '../theme/app_theme.dart';
import '../widgets/home_widgets.dart';
import 'join_society_screen.dart';
import 'request_status_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _quickActions = [
    QuickAction(label: 'Pay dues', icon: Icons.payments_rounded, route: '/maintenance'),
    QuickAction(label: 'Facility', icon: Icons.event_seat_rounded, route: '/facilities'),
    QuickAction(label: 'Gate pass', icon: Icons.qr_code_rounded, route: '/visitors'),
    QuickAction(label: 'Request', icon: Icons.edit_note_rounded, route: '/complaints'),
  ];

  static List<SocietyService> _servicesFor(bool isAdmin) => isAdmin
      ? [
          const SocietyService(
            title: 'Approvals',
            subtitle: 'Resident requests',
            icon: Icons.how_to_reg_outlined,
            route: '/admin-approvals',
          ),
          const SocietyService(
            title: 'Directory',
            subtitle: 'Residents list',
            icon: Icons.contacts_outlined,
            route: '/directory',
          ),
          const SocietyService(
            title: 'Flats & Blocks',
            subtitle: 'Units register',
            icon: Icons.domain_outlined,
            route: '/flats-management',
          ),
          const SocietyService(
            title: 'Maintenance',
            subtitle: 'Dues & billing',
            icon: Icons.payments_outlined,
            route: '/maintenance',
          ),
          const SocietyService(
            title: 'Visitors',
            subtitle: 'Gate & security logs',
            icon: Icons.person_pin_outlined,
            route: '/visitors',
          ),
          const SocietyService(
            title: 'Complaints',
            subtitle: 'Track & resolve',
            icon: Icons.report_problem_outlined,
            route: '/complaints',
          ),
          const SocietyService(
            title: 'Staff',
            subtitle: 'Roster & guards',
            icon: Icons.engineering_outlined,
            route: '/staff',
          ),
          const SocietyService(
            title: 'Facilities',
            subtitle: 'Hall, gym & bookings',
            icon: Icons.event_seat_outlined,
            route: '/facilities',
          ),
          const SocietyService(
            title: 'Meetings',
            subtitle: 'AGM & minutes',
            icon: Icons.groups_outlined,
            route: '/meetings',
          ),
          const SocietyService(
            title: 'Notices',
            subtitle: 'Board circulars',
            icon: Icons.campaign_outlined,
            route: '/notices',
          ),
        ]
      : [
          const SocietyService(
            title: 'Maintenance',
            subtitle: 'Pay dues & ledger',
            icon: Icons.payments_outlined,
            route: '/maintenance',
          ),
          const SocietyService(
            title: 'Visitors',
            subtitle: 'Gate pass & guests',
            icon: Icons.qr_code_2_outlined,
            route: '/visitors',
          ),
          const SocietyService(
            title: 'Helpdesk',
            subtitle: 'Raise complaints',
            icon: Icons.support_agent_outlined,
            route: '/complaints',
          ),
          const SocietyService(
            title: 'My Flat',
            subtitle: 'Family & household',
            icon: Icons.home_outlined,
            route: '/my-flat',
          ),
          const SocietyService(
            title: 'Facilities',
            subtitle: 'Club, pool & gym',
            icon: Icons.event_seat_outlined,
            route: '/facilities',
          ),
          const SocietyService(
            title: 'Vehicles',
            subtitle: 'Parking & tags',
            icon: Icons.directions_car_outlined,
            route: '/profile',
          ),
          const SocietyService(
            title: 'Notices',
            subtitle: 'Board updates',
            icon: Icons.campaign_outlined,
            route: '/notices',
          ),
          const SocietyService(
            title: 'Emergency',
            subtitle: 'Gate & SOS contacts',
            icon: Icons.shield_outlined,
            route: '/settings',
          ),
        ];

  static final _announcements = sampleAnnouncements;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;

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
                    child: HeroBalanceCard(
                      societyName: session.societyName,
                      period: 'August 2026',
                      amount: '₹4,850.00',
                      dueCaption: session.flatSubtitle != null
                          ? 'Due by 15 August · ${session.flatSubtitle}'
                          : 'Due by 15 August · Flat Details Pending',
                      onPay: () =>
                          Navigator.pushNamed(context, '/maintenance'),
                      onLedger: () =>
                          Navigator.pushNamed(context, '/maintenance'),
                      onReceipts: () =>
                          Navigator.pushNamed(context, '/maintenance'),
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
                  sliver: SliverToBoxAdapter(
                    child: _buildStats(context, p),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'Services',
                      actionLabel: 'See all',
                      onAction: () => _showAllServices(context),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ServiceTile(
                        service: services[index],
                        accent: p.featureColor(index),
                      ),
                      childCount: services.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 138,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'Latest updates',
                      actionLabel: 'View all',
                      onAction: () =>
                          Navigator.pushNamed(context, '/notices'),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: NoticeCard(announcement: _announcements[index]),
                      ),
                      childCount: _announcements.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    // Resolve display name from session, fallback to Saurabh for demo/tests where no auth
    String displayName;
    String flatLine;
    try {
      final session = AppSession.instance;
      displayName = session.displayName ?? 'Saurabh';
      flatLine = session.flatSubtitle ?? 'Tower B · Flat 204 · Sector 21';
    } catch (_) {
      displayName = 'Saurabh';
      flatLine = 'Tower B · Flat 204 · Sector 21';
    }

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
                Text(
                  flatLine,
                  style: textTheme.bodySmall,
                ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE68A00),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.card, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.people_alt_outlined,
            value: '12',
            label: 'Visitors today',
            accent: p.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.campaign_outlined,
            value: '3',
            label: 'New notices',
            accent: p.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.assignment_outlined,
            value: '2',
            label: 'Open requests',
            accent: p.warning,
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

  void _showAllServices(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All services are on the home screen.')),
    );
  }
}