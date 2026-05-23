import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/support_spacing.dart';

void main() {
  group('support spacing table', () {
    test('covers DN15 through DN600', () {
      expect(kSupportSpans.first.dn, 15);
      expect(kSupportSpans.last.dn, 600);
    });

    test('DN strictly increases', () {
      for (var i = 1; i < kSupportSpans.length; i++) {
        expect(kSupportSpans[i].dn > kSupportSpans[i - 1].dn, isTrue);
      }
    });

    test('vapor spacing is always ≥ water spacing (empty pipe lighter)', () {
      for (final s in kSupportSpans) {
        expect(s.vaporMm >= s.waterMm, isTrue,
            reason: 'DN${s.dn}: vapor ${s.vaporMm} < water ${s.waterMm}');
      }
    });

    test('every spacing is positive and within real-world bounds', () {
      for (final s in kSupportSpans) {
        expect(s.vaporMm > 1000 && s.vaporMm < 12000, isTrue);
        expect(s.waterMm > 1000 && s.waterMm < 12000, isTrue);
      }
    });
  });

  group('closestSpanByDn', () {
    test('exact match returns that row', () {
      expect(closestSpanByDn(50).dn, 50);
      expect(closestSpanByDn(150).dn, 150);
    });

    test('rounds to the nearest tabulated DN', () {
      expect(closestSpanByDn(70).dn, 65);
      expect(closestSpanByDn(120).dn, 100);
    });

    test('clamps to bounds', () {
      expect(closestSpanByDn(5).dn, 15);
      expect(closestSpanByDn(1000).dn, 600);
    });
  });

  group('reference data integrity', () {
    test('every support type carries description and placement note', () {
      for (final t in kSupportTypes) {
        expect(t.namePl.isNotEmpty, isTrue);
        expect(t.nameEn.isNotEmpty, isTrue);
        expect(t.descPl.isNotEmpty, isTrue);
        expect(t.descEn.isNotEmpty, isTrue);
        expect(t.wherePl.isNotEmpty, isTrue);
        expect(t.whereEn.isNotEmpty, isTrue);
      }
    });

    test('placement rules are bilingual', () {
      for (final r in kPlacementRules) {
        expect(r.pl.isNotEmpty, isTrue);
        expect(r.en.isNotEmpty, isTrue);
      }
    });
  });
}
