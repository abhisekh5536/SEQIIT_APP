import '../models/society_models.dart';

final List<Announcement> sampleAnnouncements = [
  Announcement(
    title: 'Society maintenance drive',
    description:
        'Annual maintenance of water pumps and lifts is scheduled for this weekend between 10 AM and 4 PM. Vehicles parked in the service lane must be moved.',
    date: DateTime.now().subtract(const Duration(hours: 2)),
    tag: 'Important',
  ),
  Announcement(
    title: 'Independence Day celebration',
    description:
        'Flag hoisting ceremony at the community hall on 15th August at 9 AM. Cultural performances and breakfast for all residents.',
    date: DateTime.now().subtract(const Duration(days: 1)),
    tag: 'Event',
  ),
  Announcement(
    title: 'Fire safety drill',
    description:
        'A mandatory fire safety drill for all residents and staff has been scheduled for the coming Sunday at 11 AM.',
    date: DateTime.now().subtract(const Duration(days: 3)),
    tag: 'Safety',
  ),
];