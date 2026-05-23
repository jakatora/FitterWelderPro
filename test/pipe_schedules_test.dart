import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/pipe_schedules.dart';

void main() {
  group('pipe schedule table', () {
    test('covers DN15 through DN600', () {
      expect(kPipeWalls.first.dn, 15);
      expect(kPipeWalls.last.dn, 600);
    });

    test('DN strictly increases', () {
      for (var i = 1; i < kPipeWalls.length; i++) {
        expect(kPipeWalls[i].dn > kPipeWalls[i - 1].dn, isTrue);
      }
    });

    test('OD strictly increases', () {
      for (var i = 1; i < kPipeWalls.length; i++) {
        expect(kPipeWalls[i].od > kPipeWalls[i - 1].od, isTrue);
      }
    });

    test('every listed wall is positive and below half the OD', () {
      for (final r in kPipeWalls) {
        for (final s in kSchedules) {
          final w = r.walls[s];
          if (w == null) continue;
          expect(w > 0, isTrue, reason: 'DN${r.dn} $s');
          expect(w < r.od / 2, isTrue, reason: 'DN${r.dn} $s');
        }
      }
    });

    test('STD and XS exist for every row (always produced)', () {
      for (final r in kPipeWalls) {
        expect(r.walls['STD'], isNotNull, reason: 'DN${r.dn}');
        expect(r.walls['XS'], isNotNull, reason: 'DN${r.dn}');
      }
    });
  });

  group('massPerMeter', () {
    test('is positive for a produced schedule', () {
      final dn50 = kPipeWalls.firstWhere((r) => r.dn == 50);
      expect(massPerMeter(dn50, '40')! > 0, isTrue);
    });

    test('returns null for a schedule not produced in that size', () {
      final dn600 = kPipeWalls.firstWhere((r) => r.dn == 600);
      // XXS is not tabulated above DN300.
      expect(dn600.walls['XXS'], isNull);
      expect(massPerMeter(dn600, 'XXS'), isNull);
    });

    test('stainless is slightly heavier than carbon for equal geometry', () {
      final dn100 = kPipeWalls.firstWhere((r) => r.dn == 100);
      final cs = massPerMeter(dn100, '40', stainless: false)!;
      final ss = massPerMeter(dn100, '40', stainless: true)!;
      expect(ss > cs, isTrue);
    });
  });
}
