// Odbiór wizualny spoin — EN ISO 5817:2014, tablica 1.
//
// Wartości oczekiwane policzone ręcznie z tablicy 1 (numer pozycji przy
// każdym przypadku), np. 1.7 podtopienie, t = 10 mm, C:
//   h ≤ 0,1·t = 1 mm, ale maks. 0,5 mm → 0,5 mm.
// Sprawdzamy: wzory na wartościach granicznych, „maks. X mm”, B ≤ C ≤ D dla
// każdej pozycji na siatce wymiarów, granicę 0,5–3 mm / > 3 mm, zaokrąglenie
// w dół i ocenę pomiaru.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/iso5817/iso5817_limits.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_table.dart';

const _b = Iso5817Level.b;
const _c = Iso5817Level.c;
const _d = Iso5817Level.d;

Iso5817Item _item(String id) {
  final item = iso5817ItemById(id);
  if (item == null) throw StateError('brak pozycji $id');
  return item;
}

Iso5817Limit _limit(String id, Iso5817Level level,
        {double? t, double? b, double? bRoot, double? a}) =>
    iso5817Limit(
        _item(id), level, Iso5817Input(t: t, b: b, bRoot: bRoot, a: a));

/// Wartość limitu (mm / °) albo błąd testu, gdy to nie jest liczba.
double _v(String id, Iso5817Level level,
    {double? t, double? b, double? bRoot, double? a}) {
  final l = _limit(id, level, t: t, b: b, bRoot: bRoot, a: a);
  expect(l.status, Iso5817LimitStatus.value,
      reason: '$id ${level.letter}: oczekiwano liczby, jest ${l.status}');
  return l.value!;
}

Iso5817LimitStatus _st(String id, Iso5817Level level,
        {double? t, double? b, double? bRoot, double? a}) =>
    _limit(id, level, t: t, b: b, bRoot: bRoot, a: a).status;

Iso5817Assessment _assess(
  String id,
  Iso5817Level required, {
  double? t,
  double? b,
  double? bRoot,
  double? a,
  double? measured,
  bool isShort = true,
}) =>
    assessIso5817(
      item: _item(id),
      required: required,
      input: Iso5817Input(t: t, b: b, bRoot: bRoot, a: a),
      measured: measured,
      isShort: isShort,
    );

String _pl(Iso5817Assessment a) => iso5817Headline(a, en: false);

void main() {
  group('tablica — kompletność i numeracja', () {
    test('identyfikatory unikalne, każda reguła na każdym poziomie', () {
      final ids = kIso5817Items.map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final item in kIso5817Items) {
        expect(item.codes, isNotEmpty, reason: item.id);
        expect(item.namePl, isNotEmpty, reason: item.id);
        expect(item.nameEn, isNotEmpty, reason: item.id);
        expect(item.kinds, isNotEmpty, reason: item.id);
        expect(RegExp(r'^[13]\.\d{1,2}$').hasMatch(item.no), isTrue,
            reason: item.id);
        for (final level in Iso5817Level.values) {
          for (final rule in [item.thin[level], item.thick[level]]) {
            expect(rule, isNotNull, reason: '${item.id} ${level.letter}');
            if (rule!.kind == Iso5817RuleKind.formula && rule.factor != 0) {
              expect(rule.dim, isNotNull, reason: item.id);
            }
            if (rule.kind == Iso5817RuleKind.qualitative) {
              expect(rule.textPl, isNotEmpty, reason: item.id);
              expect(rule.textEn, isNotEmpty, reason: item.id);
            }
          }
        }
      }
    });

    test('numer pozycji ↔ referencja ISO 6520-1 jak w tablicy 1 (2014)', () {
      const expected = <String, (String, List<int>)>{
        '1.1': ('1.1', [100]),
        '1.2': ('1.2', [104]),
        '1.3-butt': ('1.3', [2017]),
        '1.3-fillet': ('1.3', [2017]),
        '1.4': ('1.4', [2025]),
        '1.5': ('1.5', [401]),
        '1.6': ('1.6', [4021]),
        '1.7': ('1.7', [5011, 5012]),
        '1.8': ('1.8', [5013]),
        '1.9': ('1.9', [502]),
        '1.10': ('1.10', [503]),
        '1.11': ('1.11', [504]),
        '1.12-butt': ('1.12', [505]),
        '1.12-fillet': ('1.12', [505]),
        '1.13': ('1.13', [506]),
        '1.14': ('1.14', [509, 511]),
        '1.15': ('1.15', [510]),
        '1.16': ('1.16', [512]),
        '1.17': ('1.17', [515]),
        '1.18': ('1.18', [516]),
        '1.19': ('1.19', [517]),
        '1.20': ('1.20', [5213]),
        '1.21': ('1.21', [5214]),
        '1.22': ('1.22', [601]),
        '1.23': ('1.23', [602]),
        '1.24': ('1.24', [610]),
        '3.1-5071': ('3.1', [507, 5071]),
        '3.1-5072': ('3.1', [507, 5072]),
        '3.2': ('3.2', [617]),
      };
      expect(kIso5817Items.map((i) => i.id).toSet(), expected.keys.toSet());
      for (final e in expected.entries) {
        final item = _item(e.key);
        expect(item.no, e.value.$1, reason: e.key);
        expect(item.codes, e.value.$2, reason: e.key);
      }
    });

    test('rodzaj spoiny: lista czołowych i pachwinowych', () {
      final butt =
          iso5817ItemsFor(Iso5817WeldKind.butt).map((i) => i.id).toSet();
      final fillet =
          iso5817ItemsFor(Iso5817WeldKind.fillet).map((i) => i.id).toSet();
      // Tylko czołowe.
      for (final id in [
        '1.3-butt', '1.6', '1.8', '1.9', '1.11', '1.12-butt', '1.14',
        '1.17', '1.18', '3.1-5071', '3.1-5072',
      ]) {
        expect(butt, contains(id));
        expect(fillet, isNot(contains(id)));
      }
      // Tylko pachwinowe.
      for (final id in [
        '1.3-fillet', '1.10', '1.12-fillet', '1.16', '1.20', '1.21', '3.2',
      ]) {
        expect(fillet, contains(id));
        expect(butt, isNot(contains(id)));
      }
      // Obie.
      for (final id in ['1.1', '1.2', '1.4', '1.5', '1.7', '1.13', '1.15',
          '1.19', '1.22', '1.23', '1.24']) {
        expect(butt, contains(id));
        expect(fillet, contains(id));
      }
    });

    test('podział 0,5–3 / > 3 tylko tam, gdzie norma go podaje', () {
      const split = {
        '1.3-butt', '1.3-fillet', '1.4', '1.7', '1.8', '1.11', '1.14',
        '1.17', '1.20', '3.1-5071', '3.2',
      };
      for (final item in kIso5817Items) {
        expect(item.splitsThickness, split.contains(item.id), reason: item.id);
      }
    });
  });

  group('wzory — wartości graniczne i „maks.”', () {
    test('1.7 podtopienie 5011/5012', () {
      // t > 3: D 0,2t maks. 1; C 0,1t maks. 0,5; B 0,05t maks. 0,5.
      expect(_v('1.7', _d, t: 10), 1.0);
      expect(_v('1.7', _c, t: 10), 0.5);
      expect(_v('1.7', _b, t: 10), 0.5);
      expect(_limit('1.7', _b, t: 10).capped, isFalse); // 0,5 = maks.
      expect(_limit('1.7', _c, t: 10).capped, isTrue); // 1 → 0,5
      expect(_v('1.7', _d, t: 6), 1.0); // 1,2 → 1
      expect(_v('1.7', _c, t: 6), 0.5); // 0,6 → 0,5
      expect(_v('1.7', _b, t: 6), 0.3);
      // 0,5–3: D krótkie 0,2t; C krótkie 0,1t; B niedopuszczalne.
      expect(_v('1.7', _d, t: 3), 0.6);
      expect(_v('1.7', _c, t: 3), 0.3);
      expect(_limit('1.7', _c, t: 3).shortOnly, isTrue);
      expect(_st('1.7', _b, t: 3), Iso5817LimitStatus.notPermitted);
      expect(_v('1.7', _d, t: 0.5), 0.1);
      expect(_v('1.7', _c, t: 0.5), 0.05);
    });

    test('1.8 rowek skurczowy 5013', () {
      expect(_v('1.8', _d, t: 2), 0.4); // 0,2 + 0,1·2
      expect(_v('1.8', _c, t: 2), 0.2);
      expect(_st('1.8', _b, t: 2), Iso5817LimitStatus.notPermitted);
      expect(_v('1.8', _d, t: 10), 2.0); // 0,2·10 = 2 = maks.
      expect(_v('1.8', _c, t: 10), 1.0);
      expect(_v('1.8', _b, t: 10), 0.5);
      expect(_v('1.8', _d, t: 30), 2.0); // 6 → 2
      for (final l in Iso5817Level.values) {
        expect(_limit('1.8', l, t: 10).shortOnly, isTrue);
      }
    });

    test('1.9 nadlew lica 502: 1 mm + k·b, maks. 10 / 7 / 5 mm', () {
      expect(_v('1.9', _d, t: 10, b: 12), 4.0);
      expect(_v('1.9', _c, t: 10, b: 12), 2.8);
      expect(_v('1.9', _b, t: 10, b: 12), 2.2);
      expect(_v('1.9', _b, t: 10, b: 40), 5.0); // dokładnie maks.
      expect(_limit('1.9', _b, t: 10, b: 40).capped, isFalse);
      expect(_v('1.9', _b, t: 10, b: 50), 5.0); // 6 → 5
      expect(_limit('1.9', _b, t: 10, b: 50).capped, isTrue);
      expect(_v('1.9', _c, t: 10, b: 50), 7.0); // 8,5 → 7
      expect(_v('1.9', _d, t: 10, b: 50), 10.0); // 13,5 → 10
      // Ta sama reguła dla cienkich (t ≥ 0,5).
      expect(_v('1.9', _c, t: 2, b: 6), 1.9);
    });

    test('1.10 wypukłość spoiny pachwinowej 503: maks. 5 / 4 / 3 mm', () {
      expect(_v('1.10', _d, t: 8, b: 10), 3.5);
      expect(_v('1.10', _c, t: 8, b: 10), 2.5);
      expect(_v('1.10', _b, t: 8, b: 10), 2.0);
      expect(_v('1.10', _d, t: 8, b: 30), 5.0);
      expect(_v('1.10', _c, t: 8, b: 30), 4.0);
      expect(_v('1.10', _b, t: 8, b: 30), 3.0);
    });

    test('1.11 nadlew grani 504 — b = szerokość grani', () {
      // 0,5–3: 1 + 0,6b / 0,3b / 0,1b, bez maksimum.
      expect(_v('1.11', _d, t: 2, bRoot: 4), 3.4);
      expect(_v('1.11', _c, t: 2, bRoot: 4), 2.2);
      expect(_v('1.11', _b, t: 2, bRoot: 4), 1.4);
      // > 3: 1 + 1,0b maks. 5; 1 + 0,6b maks. 4; 1 + 0,2b maks. 3.
      expect(_v('1.11', _d, t: 8, bRoot: 3), 4.0);
      expect(_v('1.11', _c, t: 8, bRoot: 3), 2.8);
      expect(_v('1.11', _b, t: 8, bRoot: 3), 1.6);
      expect(_v('1.11', _d, t: 8, bRoot: 6), 5.0);
      expect(_v('1.11', _c, t: 8, bRoot: 6), 4.0);
      expect(_v('1.11', _b, t: 8, bRoot: 6), 2.2);
      // Szerokość lica nie zastępuje szerokości grani.
      expect(_st('1.11', _c, t: 8, b: 12), Iso5817LimitStatus.needsDimension);
    });

    test('1.12 kąt przejścia lica 505', () {
      expect(_v('1.12-butt', _d, t: 10), 90);
      expect(_v('1.12-butt', _c, t: 10), 110);
      expect(_v('1.12-butt', _b, t: 10), 150);
      expect(_v('1.12-fillet', _d, t: 10), 90);
      expect(_v('1.12-fillet', _c, t: 10), 100);
      expect(_v('1.12-fillet', _b, t: 10), 110);
      expect(_limit('1.12-butt', _c, t: 2).isAngle, isTrue);
    });

    test('1.13 nawis 506: D h ≤ 0,2·b, C i B niedopuszczalne', () {
      expect(_v('1.13', _d, t: 6, b: 10), 2.0);
      expect(_st('1.13', _c, t: 6, b: 10), Iso5817LimitStatus.notPermitted);
      expect(_st('1.13', _b, t: 6, b: 10), Iso5817LimitStatus.notPermitted);
    });

    test('1.14 zwis / niepełne wypełnienie 509/511', () {
      expect(_v('1.14', _d, t: 2), 0.5);
      expect(_v('1.14', _c, t: 2), 0.2);
      expect(_st('1.14', _b, t: 2), Iso5817LimitStatus.notPermitted);
      expect(_v('1.14', _d, t: 10), 2.0); // 2,5 → 2
      expect(_v('1.14', _c, t: 10), 1.0);
      expect(_v('1.14', _b, t: 10), 0.5);
    });

    test('1.16 asymetria spoiny pachwinowej 512', () {
      expect(_v('1.16', _d, t: 6, a: 5), 3.0);
      expect(_v('1.16', _c, t: 6, a: 5), 2.75);
      expect(_v('1.16', _b, t: 6, a: 5), 2.25);
      expect(_v('1.16', _b, t: 2, a: 10), 3.0); // bez podziału grubości
    });

    test('1.17 wklęśnięcie grani 515', () {
      // 0,5–3: D 0,2 + 0,1t (NIE tylko krótkie); C krótkie 0,1t; B nie.
      expect(_v('1.17', _d, t: 2), 0.4);
      expect(_limit('1.17', _d, t: 2).shortOnly, isFalse);
      expect(_v('1.17', _c, t: 2), 0.2);
      expect(_limit('1.17', _c, t: 2).shortOnly, isTrue);
      expect(_st('1.17', _b, t: 2), Iso5817LimitStatus.notPermitted);
      // > 3: krótkie 0,2t maks. 2; 0,1t maks. 1; 0,05t maks. 0,5.
      expect(_v('1.17', _d, t: 8), 1.6);
      expect(_v('1.17', _c, t: 8), 0.8);
      expect(_v('1.17', _b, t: 8), 0.4);
      expect(_v('1.17', _d, t: 20), 2.0);
      expect(_v('1.17', _c, t: 20), 1.0);
      expect(_v('1.17', _b, t: 20), 0.5);
    });

    test('1.20 za mała grubość spoiny pachwinowej 5213', () {
      expect(_v('1.20', _d, t: 3, a: 3), 0.5); // 0,2 + 0,1·3
      expect(_v('1.20', _c, t: 3, a: 3), 0.2); // stała 0,2 mm
      expect(_st('1.20', _b, t: 3, a: 3), Iso5817LimitStatus.notPermitted);
      expect(_v('1.20', _d, t: 10, a: 5), 0.8); // 0,3 + 0,5
      expect(_v('1.20', _c, t: 10, a: 5), 0.8);
      expect(_v('1.20', _d, t: 10, a: 20), 2.0); // 2,3 → 2
      expect(_v('1.20', _c, t: 10, a: 20), 1.0); // 2,3 → 1
      expect(_st('1.20', _b, t: 10, a: 20), Iso5817LimitStatus.notPermitted);
      // C w cienkim zakresie nie potrzebuje a.
      expect(_v('1.20', _c, t: 2), 0.2);
      expect(_st('1.20', _d, t: 2), Iso5817LimitStatus.needsDimension);
    });

    test('1.21 za duża grubość spoiny pachwinowej 5214', () {
      expect(_st('1.21', _d, t: 6, a: 5), Iso5817LimitStatus.unlimited);
      expect(_v('1.21', _c, t: 6, a: 5), 2.0);
      expect(_v('1.21', _b, t: 6, a: 5), 1.75);
      expect(_v('1.21', _c, t: 6, a: 20), 4.0); // 5 → 4
      expect(_v('1.21', _b, t: 6, a: 20), 3.0); // 4 → 3
    });

    test('3.1 przesunięcie liniowe 507 — blachy (5071) i obwodowe (5072)', () {
      // 5071, 0,5–3: 0,2 + 0,25t / 0,15t / 0,1t.
      expect(_v('3.1-5071', _d, t: 2), 0.7);
      expect(_v('3.1-5071', _c, t: 2), 0.5);
      expect(_v('3.1-5071', _b, t: 2), 0.4);
      // 5071, > 3: 0,25t maks. 5; 0,15t maks. 4; 0,1t maks. 3.
      expect(_v('3.1-5071', _d, t: 10), 2.5);
      expect(_v('3.1-5071', _c, t: 10), 1.5);
      expect(_v('3.1-5071', _b, t: 10), 1.0);
      expect(_v('3.1-5071', _d, t: 40), 5.0);
      expect(_v('3.1-5071', _c, t: 40), 4.0);
      expect(_v('3.1-5071', _b, t: 40), 3.0);
      // 5072: 0,5t maks. 4 / 3 / 2, bez podziału grubości.
      expect(_v('3.1-5072', _d, t: 5), 2.5);
      expect(_v('3.1-5072', _c, t: 5), 2.5);
      expect(_v('3.1-5072', _b, t: 5), 2.0);
      expect(_v('3.1-5072', _d, t: 10), 4.0);
      expect(_v('3.1-5072', _c, t: 10), 3.0);
      expect(_v('3.1-5072', _b, t: 10), 2.0);
      expect(_v('3.1-5072', _b, t: 2), 1.0);
    });

    test('3.2 szczelina w spoinie pachwinowej 617', () {
      expect(_v('3.2', _d, t: 2, a: 2), 0.7);
      expect(_v('3.2', _c, t: 2, a: 2), 0.5);
      expect(_v('3.2', _b, t: 2, a: 2), 0.4);
      expect(_v('3.2', _d, t: 10, a: 5), 2.5);
      expect(_v('3.2', _c, t: 10, a: 5), 1.5);
      expect(_v('3.2', _b, t: 10, a: 5), 1.0);
      expect(_v('3.2', _d, t: 10, a: 12), 4.0); // 4,6 → 4
      expect(_v('3.2', _c, t: 10, a: 12), 2.9);
      expect(_v('3.2', _b, t: 10, a: 12), 1.7);
    });

    test('1.3 por, 1.4 jama kraterowa, 1.6 brak przetopu', () {
      expect(_v('1.3-butt', _d, t: 2), 0.6); // s = t
      expect(_st('1.3-butt', _c, t: 2), Iso5817LimitStatus.notPermitted);
      expect(_v('1.3-butt', _d, t: 10), 3.0);
      expect(_v('1.3-butt', _c, t: 10), 2.0);
      expect(_v('1.3-butt', _d, t: 20), 3.0); // 6 → 3
      expect(_v('1.3-butt', _c, t: 20), 2.0); // 4 → 2
      expect(_st('1.3-butt', _b, t: 20), Iso5817LimitStatus.notPermitted);
      expect(_v('1.3-fillet', _d, t: 10, a: 5), 1.5);
      expect(_v('1.3-fillet', _c, t: 10, a: 5), 1.0);

      expect(_v('1.4', _d, t: 2), 0.4);
      expect(_st('1.4', _c, t: 2), Iso5817LimitStatus.notPermitted);
      expect(_v('1.4', _d, t: 10), 2.0);
      expect(_v('1.4', _c, t: 10), 1.0);
      expect(_st('1.4', _b, t: 10), Iso5817LimitStatus.notPermitted);

      expect(_v('1.6', _d, t: 5), 1.0);
      expect(_v('1.6', _d, t: 20), 2.0); // 4 → 2
      expect(_limit('1.6', _d, t: 5).shortOnly, isTrue);
      expect(_st('1.6', _c, t: 5), Iso5817LimitStatus.notPermitted);
      expect(_st('1.6', _b, t: 5), Iso5817LimitStatus.notPermitted);
    });

    test('niedopuszczalne zawsze i oceny słowne', () {
      for (final id in ['1.1', '1.2', '1.5', '1.15']) {
        for (final l in Iso5817Level.values) {
          expect(_st(id, l, t: 8), Iso5817LimitStatus.notPermitted,
              reason: '$id ${l.letter}');
        }
      }
      for (final id in ['1.23', '1.24']) {
        for (final l in Iso5817Level.values) {
          expect(_st(id, l, t: 8), Iso5817LimitStatus.qualitative);
        }
      }
      for (final id in ['1.18', '1.19', '1.22']) {
        expect(_st(id, _d, t: 8), Iso5817LimitStatus.qualitative);
        expect(_st(id, _c, t: 8), Iso5817LimitStatus.notPermitted);
        expect(_st(id, _b, t: 8), Iso5817LimitStatus.notPermitted);
      }
    });
  });

  group('zakres grubości', () {
    test('t = 3 to jeszcze „0,5 to 3”, t > 3 już „> 3”', () {
      expect(iso5817Range(3), Iso5817Range.thin);
      expect(iso5817Range(3.0001), Iso5817Range.thick);
      expect(iso5817Range(0.5), Iso5817Range.thin);
      expect(iso5817Range(0.49), isNull);
      expect(iso5817Range(null), isNull);
      // 1.7 B: przy t = 3 niedopuszczalne, przy t = 3,01 już 0,05·t.
      expect(_st('1.7', _b, t: 3), Iso5817LimitStatus.notPermitted);
      expect(_v('1.7', _b, t: 3.01), 0.15); // 0,1505 → 0,15
      expect(_v('1.7', _c, t: 3.01), 0.30);
      expect(_v('1.7', _d, t: 3.01), 0.60);
      // 3.1 (5071) zmienia wzór na granicy.
      expect(_v('3.1-5071', _b, t: 3), 0.5); // 0,2 + 0,3
      expect(_v('3.1-5071', _b, t: 4), 0.4); // 0,1·4
    });

    test('t < 0,5 mm — poza zakresem normy; brak t — prośba o t', () {
      for (final item in kIso5817Items) {
        for (final l in Iso5817Level.values) {
          expect(iso5817Limit(item, l, const Iso5817Input(t: 0.4)).status,
              Iso5817LimitStatus.outOfScope);
          expect(iso5817Limit(item, l, const Iso5817Input()).status,
              Iso5817LimitStatus.needsThickness);
        }
      }
    });
  });

  group('B ≤ C ≤ D', () {
    // Liberalność limitu: im większa, tym łagodniej. Kąt: im mniejszy
    // wymagany kąt, tym łagodniej.
    double? permissiveness(Iso5817Limit l) => switch (l.status) {
          Iso5817LimitStatus.notPermitted => -1,
          Iso5817LimitStatus.unlimited => double.infinity,
          Iso5817LimitStatus.value => l.isAngle ? -l.value! : l.value!,
          _ => null,
        };

    test('dla każdej pozycji na siatce t, b, a', () {
      const ts = [0.5, 1.0, 2.0, 3.0, 3.01, 4.0, 6.0, 8.0, 10.0, 15.0, 20.0,
          30.0, 50.0, 100.0];
      const bs = [2.0, 6.0, 12.0, 25.0, 60.0];
      const as = [2.0, 4.0, 7.0, 12.0, 25.0];
      var checked = 0;
      for (final item in kIso5817Items) {
        for (final t in ts) {
          for (final b in bs) {
            for (final a in as) {
              final input = Iso5817Input(t: t, b: b, bRoot: b / 2, a: a);
              final lim = iso5817Limits(item, input);
              final pb = permissiveness(lim[_b]!);
              final pc = permissiveness(lim[_c]!);
              final pd = permissiveness(lim[_d]!);
              final where = '${item.id} t=$t b=$b a=$a';
              if (pb != null && pc != null) {
                expect(pb, lessThanOrEqualTo(pc), reason: where);
              }
              if (pc != null && pd != null) {
                expect(pc, lessThanOrEqualTo(pd), reason: where);
                checked++;
              }
              // Łagodniejszy poziom „tylko krótkie” ⇒ ostrzejszy też
              // tylko krótkie albo niedopuszczalny.
              for (final (stricter, looser) in [(_b, _c), (_c, _d)]) {
                if (lim[looser]!.shortOnly) {
                  final s = lim[stricter]!;
                  expect(
                      s.shortOnly ||
                          s.status == Iso5817LimitStatus.notPermitted,
                      isTrue,
                      reason: where);
                }
              }
            }
          }
        }
      }
      expect(checked, greaterThan(1000));
    });
  });

  group('zaokrąglenie i porównanie', () {
    test('limit w dół do 0,01 mm, pomiar porównywany z tą liczbą', () {
      // 1.9 C: 1 + 0,15·12,5 = 2,875 → 2,87.
      expect(_v('1.9', _c, t: 10, b: 12.5), 2.87);
      expect(_assess('1.9', _c, t: 10, b: 12.5, measured: 2.87).outcome,
          Iso5817Outcome.pass);
      expect(_assess('1.9', _c, t: 10, b: 12.5, measured: 2.875).outcome,
          Iso5817Outcome.below);
      // 1.7 B, t = 6,5: 0,325 → 0,32.
      expect(_v('1.7', _b, t: 6.5), 0.32);
      // Błąd zmiennoprzecinkowy nie zjada setnej: 1 + 0,15·12 = 2,8.
      expect(_v('1.9', _c, t: 10, b: 12), 2.8);
      expect(_v('1.17', _c, t: 3), 0.3);
    });

    test('pomiar równy limitowi mieści się', () {
      expect(_assess('1.7', _c, t: 10, measured: 0.5).outcome,
          Iso5817Outcome.pass);
      expect(_assess('1.12-butt', _c, t: 10, measured: 110).outcome,
          Iso5817Outcome.pass);
    });
  });

  group('ocena pomiaru', () {
    test('mieści się / przekracza wymagany / niedopuszczalne', () {
      final pass = _assess('1.7', _c, t: 10, measured: 0.4);
      expect(pass.outcome, Iso5817Outcome.pass);
      expect(pass.strictestMet, _b);
      expect(_pl(pass), 'Mieści się w C (limit 0,5 mm)');
      expect(iso5817Subline(pass, en: false),
          'Spełnia również B (limit 0,5 mm)');

      final below = _assess('1.7', _c, t: 10, measured: 0.8);
      expect(below.outcome, Iso5817Outcome.below);
      expect(below.acceptedAt, _d);
      expect(_pl(below),
          'Przekracza C (limit 0,5 mm), mieści się w D (limit 1 mm)');

      final fail = _assess('1.7', _c, t: 10, measured: 1.2);
      expect(fail.outcome, Iso5817Outcome.fail);
      expect(_pl(fail), 'Niedopuszczalne — przekracza też D (limit 1 mm)');

      final failD = _assess('1.7', _d, t: 10, measured: 1.01);
      expect(failD.outcome, Iso5817Outcome.fail);
    });

    test('B niedopuszczalne w cienkim zakresie → mieści się w C', () {
      final a = _assess('1.7', _b, t: 2, measured: 0.15);
      expect(a.outcome, Iso5817Outcome.below);
      expect(a.acceptedAt, _c);
      expect(_pl(a), 'Niedopuszczalne w B, mieści się w C (limit 0,2 mm)');
      // Pomiar 0 = brak niezgodności — mieści się nawet w B.
      final none = _assess('1.6', _c, t: 5, measured: 0);
      expect(none.outcome, Iso5817Outcome.pass);
      expect(_pl(none), 'Brak niezgodności — mieści się w C');
    });

    test('niezgodność długa przy limicie „tylko krótkie”', () {
      // 1.17, t = 2: C krótkie 0,2; D 0,4 (bez warunku krótkości).
      final a = _assess('1.17', _c, t: 2, measured: 0.15, isShort: false);
      expect(a.anyShortOnly, isTrue);
      expect(a.meets[_c], isFalse);
      expect(a.failedOnLength, isTrue);
      expect(a.outcome, Iso5817Outcome.below);
      expect(_pl(a),
          'Przekracza C (dopuszcza tylko niezgodność krótką), mieści się '
          'w D (limit 0,4 mm)');
      // Ta sama wartość jako krótka — mieści się w C.
      expect(_assess('1.17', _c, t: 2, measured: 0.15).outcome,
          Iso5817Outcome.pass);
      // 1.17, t = 10: wszystkie poziomy „krótkie” — długa jest odrzucona.
      final long = _assess('1.17', _c, t: 10, measured: 0.3, isShort: false);
      expect(long.outcome, Iso5817Outcome.fail);
      expect(_pl(long),
          'Niedopuszczalne — niezgodność długa, a limity dotyczą tylko '
          'krótkich');
      // 1.7, t > 3: limit nie zależy od długości.
      final undercut = _assess('1.7', _c, t: 10, measured: 0.4, isShort: false);
      expect(undercut.anyShortOnly, isFalse);
      expect(undercut.outcome, Iso5817Outcome.pass);
    });

    test('kąt przejścia lica: większy kąt = lepiej', () {
      expect(_pl(_assess('1.12-butt', _c, t: 10, measured: 120)),
          'Mieści się w C (min. 110°)');
      expect(_pl(_assess('1.12-butt', _c, t: 10, measured: 100)),
          'Nie spełnia C (min. 110°), mieści się w D (min. 90°)');
      expect(_pl(_assess('1.12-butt', _c, t: 10, measured: 80)),
          'Niedopuszczalne — nie spełnia też D (min. 90°)');
      expect(_assess('1.12-fillet', _b, t: 10, measured: 112).outcome,
          Iso5817Outcome.pass);
    });

    test('pozycje „obecność” i opisy słowne', () {
      final crack = _assess('1.1', _d, t: 10);
      expect(crack.outcome, Iso5817Outcome.fail);
      expect(_pl(crack), 'Niedopuszczalne na każdym poziomie (B, C, D)');

      final stray = _assess('1.22', _c, t: 10);
      expect(stray.outcome, Iso5817Outcome.below);
      expect(stray.acceptedConditionally, isTrue);
      expect(_pl(stray),
          'Niedopuszczalne w C; w D warunkowo: dopuszczalne, jeśli nie '
          'zmienia własności materiału rodzimego');

      final strayD = _assess('1.22', _d, t: 10);
      expect(strayD.outcome, Iso5817Outcome.conditional);

      final spatter = _assess('1.23', _b, t: 10);
      expect(spatter.outcome, Iso5817Outcome.conditional);
      expect(_pl(spatter), startsWith('W B: akceptacja zależy od zastosowania'));

      final throat = _assess('1.21', _d, t: 6, a: 5, measured: 3);
      expect(throat.outcome, Iso5817Outcome.pass);
      expect(_pl(throat), 'Mieści się w D (bez limitu)');
      expect(_pl(_assess('1.21', _c, t: 6, a: 5, measured: 3)),
          'Przekracza C (limit 2 mm), mieści się w D (bez limitu)');
    });

    test('brak danych — nigdy fałszywy werdykt', () {
      final noT = _assess('1.7', _c, measured: 0.4);
      expect(noT.outcome, Iso5817Outcome.incomplete);
      expect(_pl(noT), 'Podaj grubość t');

      final thin = _assess('1.7', _c, t: 0.4, measured: 0.01);
      expect(thin.outcome, Iso5817Outcome.incomplete);
      expect(_pl(thin), 't < 0,5 mm — poza zakresem EN ISO 5817');

      final noB = _assess('1.9', _c, t: 10, measured: 2);
      expect(noB.outcome, Iso5817Outcome.incomplete);
      expect(_pl(noB), 'Podaj szerokość lica b');

      final noMeasure = _assess('1.7', _c, t: 10);
      expect(noMeasure.outcome, Iso5817Outcome.incomplete);
      expect(_pl(noMeasure), 'Wpisz zmierzoną wartość');
      expect(noMeasure.meets.values.every((m) => m == null), isTrue);
    });

    test('teksty EN', () {
      final a = _assess('1.7', _c, t: 10, measured: 0.8);
      expect(iso5817Headline(a, en: true),
          'Exceeds C (limit 0.5 mm), within D (limit 1 mm)');
      expect(
          iso5817Headline(_assess('1.7', _c, t: 10, measured: 0.4), en: true),
          'Within C (limit 0.5 mm)');
    });
  });

  group('teksty wzorów i protokół', () {
    test('reguła tak jak w normie, z podstawieniem', () {
      final rule = iso5817RuleFor(_item('1.9'), _b, Iso5817Range.thick);
      expect(iso5817RuleText(rule, en: false), 'h ≤ 1 mm + 0,1·b, maks. 5 mm');
      expect(iso5817RuleText(rule, en: true), 'h ≤ 1 mm + 0.1·b, max. 5 mm');
      final shortRule = iso5817RuleFor(_item('1.17'), _c, Iso5817Range.thick);
      expect(iso5817RuleText(shortRule, en: false),
          'krótkie: h ≤ 0,1·t, maks. 1 mm');
      final angle = iso5817RuleFor(_item('1.12-butt'), _b, Iso5817Range.thin);
      expect(iso5817RuleText(angle, en: false, symbol: 'α'), 'α ≥ 150°');
      expect(
          iso5817LimitCalc(_limit('1.9', _b, t: 10, b: 50),
              const Iso5817Input(t: 10, b: 50),
              en: false),
          '1 mm + 0,1·50 mm = 6 mm → maks. 5 mm');
    });

    test('protokół do udostępnienia', () {
      final a = _assess('1.7', _c, t: 10, b: 12, measured: 0.4);
      final text = buildIso5817Report(
        assessment: a,
        kind: Iso5817WeldKind.butt,
        input: const Iso5817Input(t: 10, b: 12),
        en: false,
        date: DateTime(2026, 10, 17),
      );
      final lines = text.split('\n');
      expect(lines.first,
          'Odbiór wizualny spoiny (VT) — EN ISO 5817:2014, tablica 1');
      expect(lines, contains('Data: 2026-10-17'));
      expect(lines, contains('Spoina czołowa · t = 10 mm · b lica = 12 mm'));
      expect(lines, contains('Wymagany poziom jakości: C'));
      expect(lines,
          contains('Niezgodność: 1.7 Podtopienie ciągłe / przerywane '
              '(ISO 6520-1: 5011, 5012)'));
      expect(lines, contains('Pomiar: h = 0,4 mm'));
      expect(lines, contains('Limity: B ≤ 0,5 mm · C ≤ 0,5 mm · D ≤ 1 mm'));
      expect(lines,
          contains('Wzór (C): h ≤ 0,1·t, maks. 0,5 mm → 0,1·10 mm = 1 mm '
              '→ maks. 0,5 mm'));
      expect(lines,
          contains('Wynik: Mieści się w C (limit 0,5 mm). Spełnia również B '
              '(limit 0,5 mm)'));
      expect(lines.last, iso5817Disclaimer(en: false));

      final en = buildIso5817Report(
        assessment: _assess('1.12-fillet', _b, t: 8, measured: 105),
        kind: Iso5817WeldKind.fillet,
        input: const Iso5817Input(t: 8),
        en: true,
      );
      expect(en, contains('Measurement: α = 105°'));
      expect(en, contains('Result: Does not meet B (min. 110°), within C '
          '(min. 100°)'));
    });

    test('zastrzeżenie: specyfikacja, wydanie, t ≥ 0,5 mm, metalurgia', () {
      final pl = iso5817Disclaimer(en: false);
      expect(pl, contains('specyfikacji'));
      expect(pl, contains('aktualne wydanie'));
      expect(pl, contains('EN ISO 5817:2023'));
      expect(pl, contains('t ≥ 0,5 mm'));
      expect(pl, contains('metalurgii'));
      final en = iso5817Disclaimer(en: true);
      expect(en, contains('specification'));
      expect(en, contains('t ≥ 0.5 mm'));
      expect(en, contains('metallurgy'));
    });
  });
}
