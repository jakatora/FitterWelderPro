import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/screens/hydrotest_screen.dart';

/// The hydrotest screen collects pressures in bar, MPa or psi and stores them
/// in bar. These two functions are the ONLY place the conversion factors live
/// — the design-pressure field and the gauge readings on the save sheet both
/// route through them, so a bug here would put a pressure on a signed protocol
/// that the crew never ran.
void main() {
  group('pressureToBar', () {
    test('bar is the identity', () {
      expect(pressureToBar(15.0, 'bar'), 15.0);
      expect(pressureToBar(0, 'bar'), 0);
    });

    test('1 MPa is exactly 10 bar', () {
      expect(pressureToBar(1.0, 'MPa'), 10.0);
      expect(pressureToBar(1.5, 'MPa'), closeTo(15.0, 1e-9));
    });

    test('psi converts at 14.5038 psi per bar', () {
      expect(pressureToBar(14.5038, 'psi'), closeTo(1.0, 1e-9));
      expect(pressureToBar(217.557, 'psi'), closeTo(15.0, 1e-4));
    });

    test('an unknown unit falls back to bar instead of throwing', () {
      // The value comes from a three-way toggle that cannot produce anything
      // else; a calculator that crashes mid-typing is worse than one that
      // assumes its default.
      expect(pressureToBar(15.0, 'kPa'), 15.0);
      expect(pressureToBar(15.0, ''), 15.0);
    });
  });

  group('pressureFromBar', () {
    test('is the inverse of pressureToBar', () {
      for (final unit in ['bar', 'MPa', 'psi']) {
        expect(pressureToBar(pressureFromBar(15.0, unit), unit),
            closeTo(15.0, 1e-9),
            reason: 'round-trip through $unit');
      }
    });

    test('renders the pre-filled gauge value in the crew\'s unit', () {
      // 15 bar on the calculator opens the save sheet's "start pressure"
      // field at 1.5 MPa or 217.56 psi, depending on the gauge in hand.
      expect(pressureFromBar(15.0, 'MPa'), closeTo(1.5, 1e-9));
      expect(pressureFromBar(15.0, 'psi'), closeTo(217.557, 1e-3));
      expect(pressureFromBar(15.0, 'bar'), 15.0);
    });

    test('an unknown unit falls back to bar', () {
      expect(pressureFromBar(15.0, 'kPa'), 15.0);
    });
  });
}
