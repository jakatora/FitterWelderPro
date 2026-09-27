import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/tungsten.dart';

void main() {
  group('sizeForCurrent', () {
    test('90 A picks the 1.6 mm electrode', () {
      expect(sizeForCurrent(90)!.diaMm, 1.6);
    });

    test('40 A picks the 1.0 mm electrode', () {
      expect(sizeForCurrent(40)!.diaMm, 1.0);
    });

    test('200 A picks the 2.4 mm electrode', () {
      expect(sizeForCurrent(200)!.diaMm, 2.4);
    });

    test('below the lowest band clamps to the smallest electrode', () {
      expect(sizeForCurrent(5)!.diaMm, 1.0);
    });

    test('above the highest band clamps to the largest electrode', () {
      expect(sizeForCurrent(900)!.diaMm, 3.2);
    });

    // Pasma 1,0 (15–80 A) i 1,6 (70–150 A) zachodzą na siebie: w zakładce
    // wybierana jest większa elektroda (1,0 mm przy 75 A jest na górze pasma).
    test('overlap 70–80 A picks the larger electrode', () {
      expect(sizeForCurrent(69)!.diaMm, 1.0);
      expect(sizeForCurrent(75)!.diaMm, 1.6);
      expect(sizeForCurrent(80)!.diaMm, 1.6);
      expect(sizeForCurrent(150)!.diaMm, 2.4);
    });
  });

  group('tungsten reference data', () {
    // ISO 6848:2015: WLa20, WLa15, WCe20, WTh20, WZr8, WP.
    test('ISO 6848:2015 designations', () {
      final byCode = {for (final t in kTungstenTypes) t.code: t.isoCode};
      expect(byCode, {
        'WL20': 'WLa20',
        'WL15': 'WLa15',
        'WC20': 'WCe20',
        'WT20': 'WTh20',
        'WP': 'WP',
        'WZ8': 'WZr8',
      });
    });

    test('torch gas table covers every electrode size', () {
      for (final s in kTungstenSizes) {
        final e = tungstenExtrasFor(s.diaMm);
        expect(e, isNotNull, reason: '${s.diaMm}');
        expect(e!.argonMinLpm < e.argonMaxLpm, isTrue);
      }
    });

    test('current bands are ordered going up (neighbours may overlap)', () {
      for (var i = 1; i < kTungstenSizes.length; i++) {
        expect(kTungstenSizes[i].diaMm > kTungstenSizes[i - 1].diaMm, isTrue);
        expect(kTungstenSizes[i].minA >= kTungstenSizes[i - 1].minA, isTrue);
      }
    });

    test('every band has min < max', () {
      for (final s in kTungstenSizes) {
        expect(s.minA < s.maxA, isTrue);
      }
    });

    test('at least one electrode type is flagged for stainless DC', () {
      expect(kTungstenTypes.any((t) => t.bestForSs), isTrue);
    });

    // ISO 6848 colour code: WP = green, WZ8 = white, WL20 = blue,
    // WL15 = gold, WC20 = grey, WT20 = red (EWM „Colour codes for tungsten
    // electrodes”; ISO 6848:2015).
    test('ISO 6848 tip colours: WP green, WZ8 white', () {
      final wp = kTungstenTypes.firstWhere((t) => t.code == 'WP');
      final wz8 = kTungstenTypes.firstWhere((t) => t.code == 'WZ8');
      expect(wp.tipColor, 'zielony / green');
      expect(wz8.tipColor, 'biały / white');
      expect(wz8.bestForSs, isFalse);
    });

    test('pure tungsten is not recommended for stainless DC', () {
      final wp = kTungstenTypes.firstWhere((t) => t.code == 'WP');
      expect(wp.bestForSs, isFalse);
    });
  });
}
