// iso-scanner (P0 audytu): podpowiedzi take-outu i odczyt odpowiedzi serwera.
//
// Wartości oczekiwane policzone ręcznie z ASME B16.9, nie z kodu aplikacji:
//   • kolano 90° LR NPS 4 (DN100): środek–czoło = 1,5 × 4" = 6" = 152,4 mm
//   • kolano 45° LR NPS 4 (DN100): środek–czoło = 2,5" = 63,5 mm

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';

void main() {
  group('AiNeedsInput — podpowiedź take-outu z tabeli B16.9', () {
    test('DN100 kolano 90° LR: 6" × 25,4 = 152,4 → 152 mm', () {
      final need = AiNeedsInput(
        ask: 'Podaj take-out kolana E3',
        hint: 'DN100 LR 90°',
        type: 'takeout',
      );
      expect(need.guessDn(), 100);
      expect(need.is45, isFalse);
      expect(need.isShortRadius, isFalse);
      expect(need.suggestedTakeoutMm(), 152);
    });

    test('zapis calowy 4" daje DN100 i take-out 152 mm', () {
      final need = AiNeedsInput(ask: 'Elbow 4" long radius take-out?');
      expect(need.guessDn(), 100);
      expect(need.suggestedTakeoutMm(), 152);
    });

    test('DN100 kolano 45° LR: 2,5" = 63,5 mm', () {
      final need = AiNeedsInput(ask: 'Take-out?', hint: 'DN100 45° LR');
      expect(need.is45, isTrue);
      final v = need.suggestedTakeoutMm();
      expect(v, isNotNull);
      expect(v!.toDouble(), closeTo(63.5, 1.0));
    });

    test('typ elbow45 w pytaniu nadal oznacza kolano 45°', () {
      final need = AiNeedsInput(ask: 'Take-out for elbow45 DN100');
      expect(need.is45, isTrue);
      expect(need.suggestedTakeoutMm(), closestByDn(100).lr45);
    });

    test('DN450 kolano 90° nie jest brane za kolano 45°', () {
      final need = AiNeedsInput(ask: 'Take-out for elbow DN450 LR 90°');
      expect(need.guessDn(), 450);
      expect(need.is45, isFalse);
      expect(need.suggestedTakeoutMm(), closestByDn(450).lr90);
    });

    test('identyfikator E-145 nie zmienia kolana 90° na 45°', () {
      final need = AiNeedsInput(
        ask: 'Podaj take-out kolana E-145',
        hint: 'DN100 LR',
      );
      expect(need.is45, isFalse);
      expect(need.suggestedTakeoutMm(), 152);
    });

    test('pytanie bez średnicy nie daje żadnej podpowiedzi', () {
      final need = AiNeedsInput(ask: 'Jaka jest grubość ścianki?');
      expect(need.guessDn(), isNull);
      expect(need.suggestedTakeoutMm(), isNull);
    });
  });

  group('AiScanResult.fromEnvelope — odczyt odpowiedzi serwera', () {
    test('ostrzeżenie NOT_AN_ISOMETRIC oznacza błąd skanu', () {
      final r = AiScanResult.fromEnvelope(<String, dynamic>{
        'result': {
          'warnings': ['NOT_AN_ISOMETRIC: zdjęcie nie przedstawia rysunku'],
        },
      });
      expect(r.isError, isTrue);
    });

    test('pole error oznacza błąd skanu', () {
      final r = AiScanResult.fromEnvelope(<String, dynamic>{
        'result': {'error': 'unreadable'},
      });
      expect(r.isError, isTrue);
    });

    test('poprawny wynik: odcinki, spoiny i czas są odczytane', () {
      final r = AiScanResult.fromEnvelope(<String, dynamic>{
        'tookMs': 31500,
        'model': 'vision',
        'result': {
          'segments': [
            {'id': 'S1', 'dimensionMm': 3445, 'confidence': 'high'},
            'śmieć',
            {
              'id': 'S2',
              'rawDimension': '3000+525-80',
              'auxiliary': true,
            },
          ],
          'components': [
            {'id': 'W1', 'type': 'weld', 'weldNo': 12},
            {'id': 'W2', 'type': 'fieldWeld'},
            {'id': 'F1', 'type': 'flange'},
          ],
        },
      });
      expect(r.isError, isFalse);
      expect(r.tookMs, 31500);
      expect(r.segments, hasLength(2));
      expect(r.segments[0].dimensionMm, 3445.0);
      expect(r.segments[0].confidence, AiConfidence.high);
      expect(r.segments[1].dimensionMm, isNull);
      expect(r.segments[1].rawDimension, '3000+525-80');
      expect(r.segments[1].auxiliary, isTrue);
      expect(r.welds, hasLength(2));
      expect(r.welds[0].weldNo, '12');
      expect(r.components[2].isTakeOutBearing, isTrue);
      expect(r.components[2].isWeld, isFalse);
    });

    test('pusta odpowiedź nie jest błędem, ale nie ma odcinków', () {
      final r = AiScanResult.fromEnvelope(<String, dynamic>{});
      expect(r.isError, isFalse);
      expect(r.segments, isEmpty);
      expect(r.components, isEmpty);
    });
  });
}
