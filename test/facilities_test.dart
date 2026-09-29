import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/facility_models.dart';
import 'package:society_management/screens/facilities/facility_detail_screen.dart';
import 'package:society_management/screens/facilities/resident_facilities_screen.dart';
import 'package:society_management/screens/facilities/widgets/facility_widgets.dart';
import 'package:society_management/services/notification_preferences_service.dart';
import 'package:society_management/theme/app_theme.dart';

Map<String, dynamic> _facilityMap({
  String status = 'active',
  List<Map<String, dynamic>> images = const [],
}) =>
    {
      'id': 'fac-1',
      'society_id': 'soc-1',
      'category_id': 'cat-1',
      'facility_categories': {'name': 'Sports'},
      'name': 'Swimming Pool',
      'description': 'Olympic size',
      'status': status,
      'status_note': '  ',
      'operating_hours': '6:00 AM – 10:00 PM',
      'location': null,
      'rules_text': '- Shower first\n\n2) No glass',
      'facility_images': images,
      'created_at': '2026-09-01T10:00:00Z',
      'updated_at': '2026-09-02T10:00:00Z',
    };

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  group('Facility models', () {
    test('status parses db values and falls back to active', () {
      expect(FacilityStatus.fromDb('maintenance'), FacilityStatus.maintenance);
      expect(FacilityStatus.fromDb('CLOSED'), FacilityStatus.closed);
      expect(FacilityStatus.fromDb('bogus'), FacilityStatus.active);
      expect(FacilityStatus.fromDb(null), FacilityStatus.active);
      expect(FacilityStatus.active.isAvailable, isTrue);
      expect(FacilityStatus.maintenance.isAvailable, isFalse);
    });

    test('record parses joins, blanks and orders images by sort_order', () {
      final f = FacilityRecord.fromMap(_facilityMap(images: [
        {'id': 'i2', 'facility_id': 'fac-1', 'image_url': 'b.jpg', 'sort_order': 1},
        {'id': 'i1', 'facility_id': 'fac-1', 'image_url': 'a.jpg', 'sort_order': 0},
      ]));

      expect(f.categoryName, 'Sports');
      expect(f.statusNote, isNull, reason: 'whitespace-only note is dropped');
      expect(f.location, isNull);
      expect(f.images.map((i) => i.id), ['i1', 'i2']);
      expect(f.coverUrl, 'a.jpg');
      expect(f.fallbackIcon, Icons.pool_rounded);
    });

    test('category default vs society-owned', () {
      final shared = FacilityCategory.fromMap(
          {'id': 'c1', 'society_id': null, 'name': 'Outdoor', 'sort_order': 40});
      final own = FacilityCategory.fromMap(
          {'id': 'c2', 'society_id': 'soc-1', 'name': 'Indoor Games'});
      expect(shared.isDefault, isTrue);
      expect(own.isDefault, isFalse);
      expect(own.sortOrder, 100);
      expect(shared.icon, Icons.park_rounded);
    });

    test('facility push is opt-in, other modules opt-out', () {
      expect(PushModule.facilities.defaultEnabled, isFalse);
      expect(
        PushModule.values
            .where((m) => m != PushModule.facilities)
            .every((m) => m.defaultEnabled),
        isTrue,
      );
    });
  });

  group('Facility widgets', () {
    testWidgets('grid card keeps unavailable facilities visible with badge',
        (tester) async {
      final f = FacilityRecord.fromMap(_facilityMap(status: 'maintenance'));
      await tester.pumpWidget(_wrap(Scaffold(
        body: SizedBox(
          width: 180,
          height: 230,
          child: FacilityGridCard(facility: f, onTap: () {}),
        ),
      )));

      expect(find.text('Swimming Pool'), findsOneWidget);
      expect(find.text('Maintenance'), findsOneWidget);
    });

    testWidgets('resident screen shows empty state without a backend',
        (tester) async {
      await tester.pumpWidget(_wrap(const ResidentFacilitiesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No facilities listed yet'), findsOneWidget);
    });

    testWidgets('detail page shows rules as a list and a disabled Book Now',
        (tester) async {
      final f = FacilityRecord.fromMap(_facilityMap(status: 'closed'));
      await tester.pumpWidget(
          _wrap(FacilityDetailScreen(facilityId: f.id, initial: f)));
      await tester.pumpAndSettle();

      expect(find.text('Currently closed'), findsOneWidget);
      expect(find.text('Shower first'), findsOneWidget);
      expect(find.text('No glass'), findsOneWidget);

      final book = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Book Now'));
      expect(book.onPressed, isNull);
    });

    testWidgets('status badge labels', (tester) async {
      await tester.pumpWidget(_wrap(const Scaffold(
        body: Column(children: [
          FacilityStatusBadge(status: FacilityStatus.active),
          FacilityStatusBadge(status: FacilityStatus.closed, compact: true),
        ]),
      )));
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
    });
  });
}
