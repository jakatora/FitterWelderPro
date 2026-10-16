import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/pwht/pwht_cycle.dart';

void main() {
  const rule = PwhtRateRule(
    id: 'test',
    namePl: 'test',
    nameEn: 'test',
    source: 'test',
    controlTempC: 400,
    heatCoefficient: 5000,
    heatCapCPerH: 200,
    coolCoefficient: 6000,
    coolCapCPerH: null,
    floorCPerH: 50,
    notePl: '',
    noteEn: '',
    belowControlPl: '',
    belowControlEn: '',
  );

  group('PwhtRateRule', () {
    test('k / t poniżej limitu', () {
      expect(rule.maxHeatingRate(50), 100);
      expect(rule.maxCoolingRate(50), 120);
    });

    test('limit górny obcina cienkie ścianki', () {
      expect(rule.maxHeatingRate(10), 200);
      // Chłodzenie bez limitu górnego w tej regule.
      expect(rule.maxCoolingRate(10), 600);
    });

    test('„nie musi być mniejsza niż” podnosi grube ścianki do floor', () {
      expect(rule.maxHeatingRate(200), 50);
      expect(rule.maxCoolingRate(200), 50);
    });

    test('grubość ≤ 0 / NaN → null', () {
      expect(rule.maxHeatingRate(0), isNull);
      expect(rule.maxHeatingRate(-5), isNull);
      expect(rule.maxCoolingRate(double.nan), isNull);
    });
  });

  group('buildPwhtCycle', () {
    test('rampy, wytrzymanie i suma', () {
      final c = buildPwhtCycle(
        controlTempC: 400,
        holdTempC: 600,
        heatingRateCPerH: 100,
        coolingRateCPerH: 200,
        holdMinutes: 90,
      )!;
      expect(c.rampUpHours, 2);
      expect(c.holdHours, 1.5);
      expect(c.rampDownHours, 1);
      expect(c.totalHours, 4.5);
      final p = c.points;
      expect(p.map((e) => e.hours).toList(), [0, 2, 3.5, 4.5]);
      expect(p.map((e) => e.tempC).toList(), [400, 600, 600, 400]);
    });

    test('nonsens → null', () {
      expect(
          buildPwhtCycle(
              controlTempC: 600,
              holdTempC: 600,
              heatingRateCPerH: 100,
              coolingRateCPerH: 100,
              holdMinutes: 60),
          isNull);
      expect(
          buildPwhtCycle(
              controlTempC: 400,
              holdTempC: 600,
              heatingRateCPerH: 0,
              coolingRateCPerH: 100,
              holdMinutes: 60),
          isNull);
    });
  });

  group('formatPwhtDuration', () {
    test('zaokrągla w górę do pełnej minuty', () {
      expect(formatPwhtDuration(0.76), '46 min'); // 45,6 min
      expect(formatPwhtDuration(1), '1 h 00 min');
      expect(formatPwhtDuration(2.1), '2 h 06 min');
      expect(formatPwhtDuration(0.25), '15 min');
    });

    test('błędne → kreska', () {
      expect(formatPwhtDuration(double.nan), '—');
      expect(formatPwhtDuration(-1), '—');
    });
  });
}
