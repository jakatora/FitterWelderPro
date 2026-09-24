import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';

void main() {
  test('table covers DN15 through DN600', () {
    expect(kElbowTakeouts.first.dn, 15);
    expect(kElbowTakeouts.last.dn, 600);
  });

  test('all DN values are unique and increasing', () {
    for (var i = 1; i < kElbowTakeouts.length; i++) {
      expect(kElbowTakeouts[i].dn > kElbowTakeouts[i - 1].dn, isTrue,
          reason: 'DN table must be strictly increasing');
    }
  });

  test('all takeouts are positive and non-decreasing with DN', () {
    // B16.9 keeps small NPS rows at a 1-1/2" minimum, so DN15/20/25 share
    // the same takeout; we only require monotonic non-decrease.
    for (var i = 1; i < kElbowTakeouts.length; i++) {
      final p = kElbowTakeouts[i - 1];
      final c = kElbowTakeouts[i];
      expect(c.lr90 >= p.lr90, isTrue, reason: 'DN${c.dn}: lr90 dropped');
      if (p.sr90 != null && c.sr90 != null) {
        expect(c.sr90! >= p.sr90!, isTrue, reason: 'DN${c.dn}: sr90 dropped');
      }
      expect(c.lr45 > 0, isTrue);
      expect(c.lr90 > 0, isTrue);
      if (c.sr90 != null) expect(c.sr90! > 0, isTrue);
    }
  });

  test('LR90 is always longer than SR90 (long vs short radius)', () {
    for (final e in kElbowTakeouts.where((e) => e.sr90 != null)) {
      expect(e.lr90 > e.sr90!, isTrue,
          reason: 'DN${e.dn}: lr90=${e.lr90} should be > sr90=${e.sr90}');
    }
  });

  // ASME B16.9-2018 Tab. 6.1-1 (LR A) — NPS 1/2, 3/4, 1 are all 1.50 in. =
  // 38 mm; from NPS 1-1/4 A = 1.5 × NPS (e.g. NPS 4: 6.00 in. = 152 mm).
  test('lr90 matches ASME B16.9 Table 6.1-1 exactly', () {
    const expected = <int, int>{
      15: 38, 20: 38, 25: 38, 32: 48, 40: 57, 50: 76, 65: 95, 80: 114,
      90: 133, 100: 152, 125: 190, 150: 229, 200: 305, 250: 381, 300: 457,
      350: 533, 400: 610, 450: 686, 500: 762, 600: 914,
    };
    for (final e in kElbowTakeouts) {
      expect(e.lr90, expected[e.dn], reason: 'DN${e.dn}');
    }
  });

  // ASME B16.9-2018 Tab. 6.1-4 (SR A = 1.0 × NPS) starts at NPS 1. DN15 and
  // DN20 used to show 25 mm — an elbow the standard does not define.
  test('sr90 matches ASME B16.9 Table 6.1-4; none below NPS 1', () {
    const expected = <int, int?>{
      15: null, 20: null, 25: 25, 32: 32, 40: 38, 50: 51, 65: 64, 80: 76,
      90: 89, 100: 102, 125: 127, 150: 152, 200: 203, 250: 254, 300: 305,
      350: 356, 400: 406, 450: 457, 500: 508, 600: 610,
    };
    for (final e in kElbowTakeouts) {
      expect(e.sr90, expected[e.dn], reason: 'DN${e.dn}');
    }
  });

  // ASME B16.9-2018 Tab. 6.1-6 (3D radius), A / B; none for NPS 1/2.
  test('3D radius columns match ASME B16.9 Table 6.1-6', () {
    const a = <int, int?>{
      15: null, 20: 57, 25: 76, 32: 95, 40: 114, 50: 152, 65: 190, 80: 229,
      90: 267, 100: 305, 125: 381, 150: 457, 200: 610, 250: 762, 300: 914,
      350: 1067, 400: 1219, 450: 1372, 500: 1524, 600: 1829,
    };
    const b = <int, int?>{
      15: null, 20: 24, 25: 31, 32: 39, 40: 47, 50: 63, 65: 79, 80: 95,
      90: 111, 100: 127, 125: 157, 150: 189, 200: 252, 250: 316, 300: 378,
      350: 441, 400: 505, 450: 568, 500: 632, 600: 757,
    };
    for (final e in kElbowTakeouts) {
      expect(e.r3d90, a[e.dn], reason: 'A DN${e.dn}');
      expect(e.r3d45, b[e.dn], reason: 'B DN${e.dn}');
    }
  });

  test('npsIn agrees with the NPS label', () {
    double parse(String nps) => nps.split(' ').fold(0.0, (sum, part) {
          if (part.contains('/')) {
            final f = part.split('/');
            return sum + double.parse(f[0]) / double.parse(f[1]);
          }
          return sum + double.parse(part);
        });
    for (final e in kElbowTakeouts) {
      expect(e.npsIn, parse(e.nps), reason: 'DN${e.dn}');
    }
  });

  test('elbowTakeoutForDn is exact — no nearest-DN substitution', () {
    expect(elbowTakeoutForDn(100)!.lr90, 152);
    expect(elbowTakeoutForDn(110), isNull);
    expect(elbowTakeoutForDn(550), isNull);
  });

  test('LR45 is always shorter than LR90 on the same DN', () {
    for (final e in kElbowTakeouts) {
      expect(e.lr45 < e.lr90, isTrue,
          reason: 'DN${e.dn}: lr45=${e.lr45} should be < lr90=${e.lr90}');
    }
  });

  test('closestByDn returns exact match when present', () {
    expect(closestByDn(50).dn, 50);
    expect(closestByDn(150).dn, 150);
  });

  test('closestByDn rounds to nearest tabulated DN', () {
    // Between DN200 and DN250: 220 is closer to 200.
    expect(closestByDn(220).dn, 200);
    // Between DN250 (Δ=30) and DN300 (Δ=20): 280 is closer to 300.
    expect(closestByDn(280).dn, 300);
  });

  test('closestByDn clamps to table bounds', () {
    expect(closestByDn(10).dn, 15);
    expect(closestByDn(1000).dn, 600);
  });

  // Regression guard (audit 2026-07-07): the lr45 column for DN90+ used to be
  // lr90/2 (ratio 0.5), overstating the 45° takeout by ~20%. Pin the exact
  // ASME B16.9 45° LR centre-to-end values so this can never come back.
  test('lr45 matches ASME B16.9 45° LR takeout table exactly', () {
    const expected = <int, int>{
      15: 16, 20: 19, 25: 22, 32: 25, 40: 29, 50: 35, 65: 44, 80: 51,
      90: 57, 100: 64, 125: 79, 150: 95, 200: 127, 250: 159, 300: 190,
      350: 222, 400: 254, 450: 286, 500: 318, 600: 381,
    };
    for (final e in kElbowTakeouts) {
      expect(e.lr45, expected[e.dn],
          reason: 'DN${e.dn}: lr45=${e.lr45} != B16.9 ${expected[e.dn]}');
    }
  });

  test('45° takeout ratio is ~tan(22.5°)=0.414, never the buggy 0.5', () {
    // From DN100 up the geometry is clean; a 45° elbow is 0.414 of the 90°,
    // not half. Anything >= 0.45 means the lr90/2 bug regressed.
    for (final e in kElbowTakeouts.where((e) => e.dn >= 100)) {
      final ratio = e.lr45 / e.lr90;
      expect(ratio, lessThan(0.45),
          reason: 'DN${e.dn}: lr45/lr90=$ratio looks like the 0.5 bug');
      expect(ratio, greaterThan(0.38),
          reason: 'DN${e.dn}: lr45/lr90=$ratio too small');
    }
  });
}
