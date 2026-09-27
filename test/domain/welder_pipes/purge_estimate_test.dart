import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/heat_tint.dart';
import 'package:cut_list_app/domain/welder_pipes/purge_estimate.dart';

void main() {
  group('purge — model wykładniczego rozcieńczania', () {
    // Ten sam model co zakładka O₂ w Narzędziach spawacza
    // (welder_tools_screen.dart): C = C₀·e^(−Q·t/V), gdzie Q·t/V = N,
    // C₀ domyślnie 210 000 ppm (powietrze).
    test('C₀ to 210 000 ppm, jak w zakładce O₂', () {
      expect(kPurgeAirO2Ppm, 210000);
    });

    test('N = 6 wymian → ≈ 520,5 ppm O₂ (210 000·e^−6)', () {
      final ppm = residualO2PpmAfterVolumeChanges(6);
      expect(ppm, closeTo(210000 * math.exp(-6), 1e-9));
      expect(ppm, closeTo(520.5, 0.1));
    });

    test('N = 10 wymian → ≈ 9,5 ppm O₂', () {
      expect(residualO2PpmAfterVolumeChanges(10), closeTo(9.53, 0.01));
    });

    test('N = 0 zostawia powietrze', () {
      expect(residualO2PpmAfterVolumeChanges(0), 210000);
    });

    test('odwrotność: cel 20 ppm wymaga N = ln(210 000/20) ≈ 9,26', () {
      expect(volumeChangesForTargetPpm(20), closeTo(9.259, 0.001));
      expect(residualO2PpmAfterVolumeChanges(volumeChangesForTargetPpm(20)),
          closeTo(20, 1e-9));
    });

    test('520 ppm to najbliżej wzorca AWS D18.2 nr 6 (500 ppm)', () {
      final level =
          heatTintLevelForO2Ppm(residualO2PpmAfterVolumeChanges(6));
      expect(level.level, 6);
      expect(level.o2Ppm, 500);
    });
  });

  group('purge — zalecenia przepływu (HFT WP-269)', () {
    test('przedmuch 15–20 L/min, podczas spawania ok. 5 L/min', () {
      expect(kPrePurgeFlowLpmMin, 15);
      expect(kPrePurgeFlowLpmMax, 20);
      expect(kWeldingPurgeFlowLpmMax, 5);
      expect(kWeldingPurgeFlowLpmMax, lessThan(kPrePurgeFlowLpmMin));
    });
  });

  // 2 otwory Ø2,4: A = 2·π·2,4²/4 = 9,048 mm². 2 m/s = 2000 mm/s →
  // 18 096 mm³/s = 1,086 L/min. Dawny „złoty środek” 6,0 L/min dawał
  // 6e6/60/9,048/1000 = 11,05 m/s > próg 6 m/s.
  group('prędkość na wylotach i złoty środek', () {
    test('liczby', () {
      expect(ventAreaMm2(holes: 2, holeDiaMm: 2.4), closeTo(9.0478, 1e-3));
      expect(
          flowForVentVelocityLpm(velocityMs: 2, holes: 2, holeDiaMm: 2.4),
          closeTo(1.0857, 1e-3));
      expect(ventVelocityMs(flowLpm: 6, holes: 2, holeDiaMm: 2.4),
          closeTo(11.05, 0.01));
    });
    test('złoty środek nigdy nie wywołuje ostrzeżenia back-pressure', () {
      for (final holes in [1, 2, 4, 8]) {
        for (final d in [1.0, 1.2, 2.4, 3.0, 5.0]) {
          final q = flowForVentVelocityLpm(
              velocityMs: kVentVelocityTargetMs, holes: holes, holeDiaMm: d);
          final v = ventVelocityMs(flowLpm: q, holes: holes, holeDiaMm: d);
          expect(v, lessThanOrEqualTo(kVentVelocityComfortMs));
          expect(v, lessThan(kVentVelocityBackPressureMs));
          expect(v, greaterThan(kVentVelocityLowMs));
        }
      }
    });
    test('brak otworów → nieskończona prędkość, zero przepływu', () {
      expect(ventVelocityMs(flowLpm: 2, holes: 0, holeDiaMm: 2.4),
          double.infinity);
      expect(flowForVentVelocityLpm(velocityMs: 2, holes: 0, holeDiaMm: 2.4),
          0);
    });
  });
}
