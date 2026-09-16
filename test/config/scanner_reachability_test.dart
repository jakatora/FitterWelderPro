import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/config/feature_flags.dart';

// The ISO scanner screen is always behind a Premium gate. While the paid tier
// is switched off, no menu tile may lead there — it would open only a
// Premium overlay the user cannot act on.
void main() {
  test('scanner tile is reachable only when the scanner and paid tier are on',
      () {
    expect(kAiScannerReachable, kAiScannerEnabled && kPaidFeaturesEnabled);
  });

  test('with paid features off the scanner tile never leads to Premium', () {
    expect(kAiScannerReachable && !kPaidFeaturesEnabled, isFalse);
  });
}
