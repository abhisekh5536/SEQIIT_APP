import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/society_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/home_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _quickActions = [
    QuickAction(label: 'Pay dues', icon: Icons.payments_rounded, route: '/maintenance'),
    QuickAction(label: 'Facility', icon: Icons.event_seat_rounded, route: '/facilities'),
    QuickAction(label: 'Gate pass', icon: Icons.qr_code_rounded, route: '/visitors'),
    QuickAction(label: 'Request', icon: Icons.edit_note_rounded, route: '/complaints'),
  ];

  static List<SocietyService> _servicesFor(bool isAdmin) => [
        SocietyService(
          title: 'Maintenance',
          subtitle: 'Dues & ledger',
          icon: Icons.payments_outlined,
          route: '/maintenance',
        ),
        SocietyService(
          title: 'Visitors',
          subtitle: 'Gate & guests',
          icon: Icons.person_pin_outlined,
          route: '/visitors',
        ),
        SocietyService(
          title: 'Complaints',
          subtitle: 'Track & resolve',
          icon: Icons.report_problem_outlined,
          route: '/complaints',
        ),
        SocietyService(
          title: 'Staff',
          subtitle: 'Roster & payslips',
          icon: Icons.engineering_outlined,
          route: '/staff',
        ),
        SocietyService(
          title: 'Facilities',
          subtitle: 'Hall, gym & more',
          icon: Icons.event_seat_outlined,
          route: '/facilities',
        ),
        SocietyService(
          title: 'Meetings',
          subtitle: 'AGM & minutes',
          icon: Icons.groups_outlined,
          route: '/meetings',
        ),
        SocietyService(
          title: 'Notices',
          subtitle: 'Board updates',
          icon: Icons.campaign_outlined,
          route: '/notices',
        ),
        if (isAdmin) ...[
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
        ] else
          const SocietyService(
            title: 'My Flat',
            subtitle: 'Your home details',
            icon: Icons.home_outlined,
            route: '/my-flat',
          ),
      ];

  static final _announcements = sampleAnnouncements;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final services = _servicesFor(AppSession.instance.isAdmin);
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
                      societyName: 'Sunrise Heights',
                      period: 'August 2026',
                      amount: '₹4,850.00',
                      dueCaption:
                          'Due by 15 August · Tower B, Flat 204',
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
                  'SUNRISE HEIGHTS',
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
          _avatar(context, p),
        ],
      ),
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