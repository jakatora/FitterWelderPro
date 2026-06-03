// ASME B16.5 flange bolting catalog. Lets the bolt-torque calculator pick
// bolt size + count straight from a flange spec (DN × Class) instead of
// forcing the monter to look up the table on the side of his calc card.
//
// Coverage: Class 150 / 300 / 600 / 900 / 1500 for DN15..DN300. Above DN300
// the bolting gets job-specific (longer bolts, special studs); user falls
// back to the manual bolt picker for those.

class FlangeBolting {
  final int boltCount;
  final String boltSize; // matches keys in BoltTorqueScreen._boltDiamMm
  const FlangeBolting(this.boltCount, this.boltSize);
}

class FlangeCatalog {
  static const dns = <int>[
    15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300,
  ];

  static const classes = <int>[150, 300, 600, 900, 1500];

  // Key = "${dn}_${class}" → bolting. Values from ASME B16.5 Table 11.
  static const _table = <String, FlangeBolting>{
    // ── Class 150 ──────────────────────────────────────────────────────────
    '15_150':  FlangeBolting(4, '1/2'),
    '20_150':  FlangeBolting(4, '1/2'),
    '25_150':  FlangeBolting(4, '1/2'),
    '32_150':  FlangeBolting(4, '1/2'),
    '40_150':  FlangeBolting(4, '1/2'),
    '50_150':  FlangeBolting(4, '5/8'),
    '65_150':  FlangeBolting(4, '5/8'),
    '80_150':  FlangeBolting(4, '5/8'),
    '100_150': FlangeBolting(8, '5/8'),
    '150_150': FlangeBolting(8, '3/4'),
    '200_150': FlangeBolting(8, '3/4'),
    '250_150': FlangeBolting(12, '7/8'),
    '300_150': FlangeBolting(12, '7/8'),
    // ── Class 300 ──────────────────────────────────────────────────────────
    '15_300':  FlangeBolting(4, '1/2'),
    '20_300':  FlangeBolting(4, '5/8'),
    '25_300':  FlangeBolting(4, '5/8'),
    '32_300':  FlangeBolting(4, '5/8'),
    '40_300':  FlangeBolting(4, '3/4'),
    '50_300':  FlangeBolting(8, '5/8'),
    '65_300':  FlangeBolting(8, '3/4'),
    '80_300':  FlangeBolting(8, '3/4'),
    '100_300': FlangeBolting(8, '3/4'),
    '150_300': FlangeBolting(12, '3/4'),
    '200_300': FlangeBolting(12, '7/8'),
    '250_300': FlangeBolting(16, '1'),
    '300_300': FlangeBolting(16, '1-1/8'),
    // ── Class 600 ──────────────────────────────────────────────────────────
    '50_600':  FlangeBolting(8, '5/8'),
    '65_600':  FlangeBolting(8, '3/4'),
    '80_600':  FlangeBolting(8, '3/4'),
    '100_600': FlangeBolting(8, '7/8'),
    '150_600': FlangeBolting(12, '1'),
    '200_600': FlangeBolting(12, '1-1/8'),
    '250_600': FlangeBolting(16, '1-1/4'),
    '300_600': FlangeBolting(20, '1-1/4'),
    // ── Class 900 ──────────────────────────────────────────────────────────
    '50_900':  FlangeBolting(8, '7/8'),
    '80_900':  FlangeBolting(8, '7/8'),
    '100_900': FlangeBolting(8, '1-1/8'),
    '150_900': FlangeBolting(12, '1-1/8'),
    '200_900': FlangeBolting(12, '1-3/8'),
    '250_900': FlangeBolting(16, '1-3/8'),
    '300_900': FlangeBolting(20, '1-3/8'),
    // ── Class 1500 ─────────────────────────────────────────────────────────
    '50_1500':  FlangeBolting(8, '7/8'),
    '80_1500':  FlangeBolting(8, '1-1/8'),
    '100_1500': FlangeBolting(8, '1-1/4'),
    '150_1500': FlangeBolting(12, '1-3/8'),
    '200_1500': FlangeBolting(12, '1-5/8'),
    '250_1500': FlangeBolting(12, '1-7/8'),
    '300_1500': FlangeBolting(16, '2'),
  };

  static FlangeBolting? lookup(int dn, int cls) => _table['${dn}_$cls'];

  static String dnLabel(int dn) {
    const m = <int, String>{
      15: '1/2"', 20: '3/4"', 25: '1"', 32: '1¼"', 40: '1½"',
      50: '2"', 65: '2½"', 80: '3"', 100: '4"', 150: '6"',
      200: '8"', 250: '10"', 300: '12"',
    };
    return 'DN$dn (${m[dn] ?? '?'})';
  }
}
