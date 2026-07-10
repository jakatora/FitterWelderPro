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
      expect(c.sr90 >= p.sr90, isTrue, reason: 'DN${c.dn}: sr90 dropped');
      expect(c.lr45 > 0, isTrue);
      expect(c.lr90 > 0, isTrue);
      expect(c.sr90 > 0, isTrue);
    }
  });

  test('LR90 is always longer than SR90 (long vs short radius)', () {
    for (final e in kElbowTakeouts) {
      expect(e.lr90 > e.sr90, isTrue,
          reason: 'DN${e.dn}: lr90=${e.lr90} should be > sr90=${e.sr90}');
    }
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
