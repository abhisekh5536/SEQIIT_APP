import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/services/home_summary_service.dart';
import 'package:society_management/theme/app_theme.dart';
import 'package:society_management/widgets/hero_carousel.dart';

/// Every home carousel card, with long real-world text, on a 320px phone
/// (280px card). The test font renders each glyph a full em wide, so a row
/// that fits here fits real devices with large text settings.
void main() {
  final cards = <String, Widget>{
    'notice, all caught up': HeroNoticeCard(
      category: 'Notices',
      eyebrow: 'Society notices',
      title: "You're all caught up",
      snippet: 'Circulars from the society office will appear here.',
      meta: 'Nothing new',
      actionLabel: 'View all',
      onRead: () {},
    ),
    'notice, long title': HeroNoticeCard(
      category: 'Maintenance',
      eyebrow: 'New notice',
      title: 'Water supply will be interrupted in all towers for tank cleaning',
      snippet: 'Please store enough water for the day. The work starts at 9 AM.',
      meta: '2 hours ago',
      pinned: true,
      onRead: () {},
    ),
    'my flat': HeroSummaryCard(
      pill: 'Family Member',
      title: 'Tower A Block · Flat A-1203',
      subtitle: 'Floor 12 · 3BHK · Anand Dham Society',
      stats: const [
        HeroStat('4', 'Members'),
        HeroStat('2', 'Vehicles'),
        HeroStat('P-12, P-13', 'Parking bays'),
      ],
      actionLabel: 'My Flat',
      actionIcon: Icons.home_rounded,
      onAction: () {},
      secondaryActionLabel: 'Vehicles',
      onSecondaryAction: () {},
    ),
    'security desk, open SOS': HeroSummaryCard(
      pill: 'Security desk',
      alert: '2 open SOS',
      title: '3 guards on duty',
      subtitle: 'An SOS is open — the security team has been alerted',
      stats: const [
        HeroStat('3', 'Gates'),
        HeroStat('3', 'On duty'),
        HeroStat('12', 'Emergency contacts'),
      ],
      actionLabel: 'View SOS',
      actionIcon: Icons.crisis_alert_rounded,
      onAction: () {},
    ),
    'security desk, calm': HeroSummaryCard(
      pill: 'Security desk',
      title: 'Security desk',
      subtitle: 'Help is one tap away, day or night',
      stats: const [
        HeroStat('0', 'Gates'),
        HeroStat('0', 'On duty'),
        HeroStat('0', 'Emergency contacts'),
      ],
      actionLabel: 'Emergency contacts',
      actionIcon: Icons.call_rounded,
      onAction: () {},
      secondaryActionLabel: 'SOS',
      onSecondaryAction: () {},
    ),
    'marketplace, listing': HeroMarketCard(
      title: 'Barely used study table with chair and bookshelf',
      price: '₹12,500',
      sellerLine: 'Priya Sharma · Tower B · Flat 1204',
      postedAgo: '3d ago',
      imageUrl: null,
      onOpen: () {},
      onBrowse: () {},
    ),
    'marketplace, empty': HeroMarketCard.empty(onOpen: () {}, onBrowse: () {}),
    'guest pass, valid now': HeroTicketCard(
      guestName: 'Abhishek Yadav and family',
      time: 'Now',
      period: '',
      dayLabel: 'Valid till Tomorrow, 10:00 PM',
      location: 'A · Flat A-003 · Guest',
      passNumber: '482913',
      onShow: () {},
      onDetails: () {},
    ),
    'request, resolved': HeroStatusCard(
      pill: 'Request · Plumbing',
      eyebrow: 'A · Flat A-003',
      title: 'Kitchen sink leaking under the counter',
      detail: 'Marked resolved · confirm or reopen',
      steps: const ['Received', 'In progress', 'Resolved'],
      current: 2,
      actionLabel: 'Confirm or reopen',
      onAction: () {},
      secondaryActionLabel: 'All',
      onSecondaryAction: () {},
    ),
    'approvals': HeroStatusCard(
      pill: 'Approvals',
      eyebrow: 'Resident join requests',
      title: '12 waiting for review',
      detail: 'New residents cannot use the app until approved',
      steps: const ['Requested', 'In review', 'Approved'],
      current: 1,
      actionLabel: 'Review now',
      onAction: () {},
    ),
  };

  group('home hero cards fit a 320px phone', () {
    for (final e in cards.entries) {
      testWidgets(e.key, (tester) async {
        tester.view.physicalSize = const Size(280, 264);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(width: 280, height: 264, child: e.value),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('home summary parses server counts; residents get no society totals',
      () {
    final admin = HomeSummary.fromMap({
      'gates_active': 3,
      'guards_active': 1,
      'emergency_contacts': 9,
      'open_sos': 0,
      'total_flats': 30,
      'occupied_flats': 2,
      'active_residents': 2,
      'blocks': 3,
      'my_block': null,
      'my_parking_slots': [],
    });
    expect(admin.totalFlats, 30);
    expect(admin.myBlock, isNull);

    final resident = HomeSummary.fromMap({
      'gates_active': 3,
      'guards_active': 1,
      'emergency_contacts': 9,
      'open_sos': 1,
      'total_flats': null,
      'my_block': ' A ',
      'my_parking_slots': ['P-12'],
    });
    expect(resident.totalFlats, isNull);
    expect(resident.myBlock, 'A');
    expect(resident.myParkingSlots, ['P-12']);
    expect(resident.openSos, 1);
  });
}
