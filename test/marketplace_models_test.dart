import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/marketplace_models.dart';

void main() {
  group('formatting', () {
    test('formatInr uses Indian digit grouping without paise', () {
      expect(formatInr(1200), '₹1,200');
      expect(formatInr(120000), '₹1,20,000');
      expect(formatInr(499.6), '₹500');
    });

    test('flatLabel matches the vehicles module shape', () {
      expect(flatLabel('Tower A', '101'), 'Tower A · Flat 101');
      expect(flatLabel(null, '101'), 'Flat 101');
      expect(flatLabel('Tower A', null), isNull);
    });

    test('timeAgo buckets', () {
      final now = DateTime(2026, 9, 24, 12);
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now),
          'Just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
          '5m ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now),
          '3h ago');
      expect(timeAgo(now.subtract(const Duration(days: 2)), now: now),
          '2d ago');
      expect(timeAgo(DateTime(2026, 8, 1), now: now), '1 Aug');
    });
  });

  group('MarketplaceListing', () {
    test('parses a feed RPC row (flattened seller fields)', () {
      final l = MarketplaceListing.fromMap({
        'id': 'l-1',
        'title': 'Study table',
        'price': '2500.00',
        'price_type': 'negotiable',
        'status': 'active',
        'category_id': 'c-1',
        'category_name': 'Furniture',
        'category_icon': 'furniture',
        'created_at': DateTime.now().toIso8601String(),
        'expires_at':
            DateTime.now().add(const Duration(days: 10)).toIso8601String(),
        'cover_image_url': 'https://x/marketplace-images/u/1.jpeg',
        'image_count': 3,
        'seller_name': 'Asha Rao',
        'flat_number': '304',
        'block_name': 'B',
        'is_mine': false,
      });

      expect(l.priceLabel, '₹2,500');
      expect(l.isNegotiable, isTrue);
      expect(l.coverImageUrl, endsWith('1.jpeg'));
      expect(l.imageCount, 3);
      expect(l.sellerFlatLabel, 'B · Flat 304');
      expect(l.isLive, isTrue);
      expect(l.daysLeft, inInclusiveRange(9, 10));
    });

    test('parses a detail RPC payload with ordered images', () {
      final l = MarketplaceListing.fromMap({
        'id': 'l-2',
        'title': 'Kids cycle',
        'price': null,
        'price_type': 'free',
        'status': 'sold',
        'sold_at': '2026-09-20T10:00:00Z',
        'created_at': '2026-09-01T10:00:00Z',
        'has_seller_phone': true,
        'is_mine': true,
        'my_report_pending': false,
        'images': [
          {'id': 'i2', 'image_url': 'https://x/b.jpeg', 'sort_order': 1},
          {'id': 'i1', 'image_url': 'https://x/a.jpeg', 'sort_order': 0},
        ],
      });

      expect(l.priceLabel, 'Free');
      expect(l.status, ListingStatus.sold);
      expect(l.images.map((i) => i.id), ['i1', 'i2']);
      expect(l.coverImageUrl, 'https://x/a.jpeg');
      expect(l.imageCount, 2);
      expect(l.hasSellerPhone, isTrue);
      expect(l.isMine, isTrue);
      expect(l.isLive, isFalse);
      expect(l.daysLeft, isNull);
    });

    test('parses an admin select with embedded resident / flat / block', () {
      final l = MarketplaceListing.fromMap({
        'id': 'l-3',
        'title': 'Old TV',
        'price': 4000,
        'price_type': 'fixed',
        'status': 'flagged',
        'report_count': 3,
        'created_at': '2026-09-10T10:00:00Z',
        'marketplace_categories': {'name': 'Electronics', 'icon_key': 'electronics'},
        'marketplace_images': [
          {'id': 'i1', 'image_url': 'https://x/tv.jpeg', 'sort_order': 0},
        ],
        'residents': {
          'full_name': 'Vikram S',
          'phone': '+91 98765 43210',
          'flats': {
            'flat_number': '1102',
            'blocks': {'name': 'Tower C'},
          },
        },
      });

      expect(l.categoryName, 'Electronics');
      expect(l.categoryIcon, 'electronics');
      expect(l.sellerName, 'Vikram S');
      expect(l.sellerFlatLabel, 'Tower C · Flat 1102');
      expect(l.sellerPhone, '+91 98765 43210');
      expect(l.hasSellerPhone, isTrue);
      expect(l.status.label, 'Under review');
      expect(l.reportCount, 3);
    });

    test('active listing past expires_at reads as expired', () {
      final l = MarketplaceListing.fromMap({
        'id': 'l-4',
        'title': 'Lamp',
        'price_type': 'on_request',
        'status': 'active',
        'created_at': '2026-07-01T10:00:00Z',
        'expires_at': '2026-07-31T10:00:00Z',
      });
      expect(l.isStale, isTrue);
      expect(l.isLive, isFalse);
      expect(l.effectiveStatus, ListingStatus.expired);
      expect(l.priceLabel, 'Price on ask');
    });
  });

  group('enums', () {
    test('db values round-trip', () {
      for (final t in PriceType.values) {
        expect(PriceType.fromDb(t.toDbValue()), t);
      }
      for (final s in ListingStatus.values) {
        expect(ListingStatus.fromDb(s.toDbValue()), s);
      }
      for (final r in ReportReason.values) {
        expect(ReportReason.fromDb(r.toDbValue()), r);
      }
      expect(PriceType.onRequest.toDbValue(), 'on_request');
      expect(ReportAction.blockSeller.toDbValue(), 'block_seller');
      expect(FeedSort.priceLow.toDbValue(), 'price_low');
    });

    test('only fixed / negotiable need an amount', () {
      expect(PriceType.fixed.needsAmount, isTrue);
      expect(PriceType.negotiable.needsAmount, isTrue);
      expect(PriceType.free.needsAmount, isFalse);
      expect(PriceType.onRequest.needsAmount, isFalse);
    });
  });

  group('MarketplaceContext', () {
    test('resident context can post', () {
      final c = MarketplaceContext.fromMap({
        'success': true,
        'society_id': 's-1',
        'enabled': true,
        'is_admin': false,
        'resident_id': 'r-1',
        'is_blocked': false,
        'seller_name': 'Asha Rao',
        'flat_number': '304',
        'block_name': 'B',
        'has_phone': true,
        'listing_expiry_days': 45,
        'auto_flag_threshold': 2,
      });
      expect(c.canPost, isTrue);
      expect(c.sellerFlatLabel, 'B · Flat 304');
      expect(c.listingExpiryDays, 45);
      expect(c.autoFlagThreshold, 2);
    });

    test('blocked, disabled, admin-only and error contexts cannot post', () {
      expect(
        MarketplaceContext.fromMap({
          'success': true,
          'enabled': true,
          'resident_id': 'r-1',
          'is_blocked': true,
        }).canPost,
        isFalse,
      );
      expect(
        MarketplaceContext.fromMap({
          'success': true,
          'enabled': false,
          'resident_id': 'r-1',
        }).canPost,
        isFalse,
      );
      expect(
        MarketplaceContext.fromMap({'success': true, 'is_admin': true})
            .canPost,
        isFalse,
      );
      final err = MarketplaceContext.fromMap(
          {'success': false, 'error': 'Not linked'});
      expect(err.enabled, isFalse);
      expect(err.error, 'Not linked');
    });
  });

  test('MarketplaceReport parses reporter and nested listing', () {
    final r = MarketplaceReport.fromMap({
      'id': 'rep-1',
      'listing_id': 'l-3',
      'reason': 'fraud',
      'details': 'Asked for UPI in advance',
      'status': 'pending',
      'created_at': '2026-09-23T08:00:00Z',
      'residents': {
        'full_name': 'Neha P',
        'flats': {
          'flat_number': '702',
          'blocks': {'name': 'A'},
        },
      },
      'marketplace_listings': {
        'id': 'l-3',
        'title': 'Old TV',
        'price': 4000,
        'price_type': 'fixed',
        'status': 'active',
        'created_at': '2026-09-10T10:00:00Z',
      },
    });
    expect(r.reason, ReportReason.fraud);
    expect(r.isPending, isTrue);
    expect(r.actionLabel, 'Pending');
    expect(r.reporterName, 'Neha P');
    expect(r.reporterFlat, 'A · Flat 702');
    expect(r.listing?.title, 'Old TV');
  });
}
