import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/sanitary_tube.dart';

void main() {
  group('SanitaryTube geometry', () {
    test('ID = OD − 2·wall', () {
      const t = SanitaryTube(size: '1"', od: 25.4, wall: 1.65);
      expect(t.id, closeTo(22.1, 1e-9));
    });

    test('volume per metre is positive and grows with bore', () {
      const small = SanitaryTube(size: 'a', od: 25.4, wall: 1.65);
      const big = SanitaryTube(size: 'b', od: 101.6, wall: 2.11);
      expect(small.litresPerMeter > 0, isTrue);
      expect(big.litresPerMeter > small.litresPerMeter, isTrue);
    });

    test('mass per metre is positive', () {
      for (final t in kBpeTube) {
        expect(t.massPerMeter > 0, isTrue, reason: t.size);
      }
    });
  });

  group('BPE table', () {
    test('covers 1/4" through 6"', () {
      expect(kBpeTube.first.size, '1/4"');
      expect(kBpeTube.last.size, '6"');
    });

    test('OD strictly increases', () {
      for (var i = 1; i < kBpeTube.length; i++) {
        expect(kBpeTube[i].od > kBpeTube[i - 1].od, isTrue);
      }
    });

    test('wall never exceeds half the OD', () {
      for (final t in kBpeTube) {
        expect(t.wall < t.od / 2, isTrue, reason: t.size);
      }
    });
  });

  group('DIN 11850 table', () {
    test('covers DN10 through DN150', () {
      expect(kDin11850Tube.first.size, 'DN10');
      expect(kDin11850Tube.last.size, 'DN150');
    });

    test('OD strictly increases', () {
      for (var i = 1; i < kDin11850Tube.length; i++) {
        expect(kDin11850Tube[i].od > kDin11850Tube[i - 1].od, isTrue);
      }
    });
  });
}
