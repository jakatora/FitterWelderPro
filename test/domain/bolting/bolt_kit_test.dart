// Komplet do zamówienia: szpilki, nakrętki (2 na szpilkę), uszczelki,
// zapas w górę, JSON i uszkodzony zapis.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/bolting/bolt_kit.dart';

BoltKitJoint _j(
  String id,
  int dn,
  int cls, {
  FlangeFacing facing = FlangeFacing.rf,
  BoltMaterial material = BoltMaterial.b7,
  RfGasket gasket = RfGasket.spiralWound,
  int count = 1,
}) =>
    BoltKitJoint(
      id: id,
      dn: dn,
      cls: cls,
      facing: facing,
      material: material,
      gasket: gasket,
      count: count,
    );

void main() {
  group('komplet', () {
    test(
        '4 × DN150 Class 300 RF B7: 48 szpilek 3/4" × 4-3/4", 96 nakrętek, '
        '4 uszczelki', () {
      final o = buildBoltKitOrder([_j('a', 150, 300, count: 4)]);
      expect(o.studs, hasLength(1));
      final s = o.studs.single;
      expect(s.qty, 48);
      expect(studLineLabel(s, en: false), '3/4" × 4-3/4" (120,65 mm) A193 B7');
      expect(o.nuts.single.qty, 96);
      expect(nutLineLabel(o.nuts.single, en: false), '3/4" heavy hex A194 2H');
      expect(o.gaskets.single.qty, 4);
      expect(gasketLineLabel(o.gaskets.single, en: false),
          'spiralna (ASME B16.20), NPS 6 Class 300');
      expect(o.totalJoints, 4);
      expect(o.totalStuds, 48);
      expect(o.totalNuts, 96);
      expect(o.totalGaskets, 4);
    });

    test('nakrętki sumowane po średnicy, szpilki osobno po długości', () {
      // DN150 Class 150: 8 × 3/4" × 4"; DN150 Class 300: 12 × 3/4" × 4-3/4".
      final o = buildBoltKitOrder([
        _j('a', 150, 150, count: 2),
        _j('b', 150, 300, count: 1),
      ]);
      expect(
          o.studs.map((l) => (l.lengthQuarterIn, l.qty)), [(16, 16), (19, 12)]);
      expect(o.nuts.single.qty, (16 + 12) * 2);
      expect(o.gaskets.map((g) => (g.cls, g.qty)), [(150, 2), (300, 1)]);
    });

    test('różne materiały nie są łączone', () {
      final o = buildBoltKitOrder([
        _j('a', 100, 300),
        _j('b', 100, 300, material: BoltMaterial.b8m),
      ]);
      expect(
          o.studs.map((l) => l.material), [BoltMaterial.b7, BoltMaterial.b8m]);
      expect(o.nuts.map((l) => l.material.nut), ['A194 2H', 'A194 8M']);
      expect(o.gaskets.single.qty, 2);
    });

    test('RTJ: pierścień R45 zamiast uszczelki RF', () {
      final o = buildBoltKitOrder([
        _j('a', 150, 600, facing: FlangeFacing.rtj, count: 3),
      ]);
      final g = o.gaskets.single;
      expect(g.ring, 'R45');
      expect(g.gasket, isNull);
      expect(gasketLineLabel(g, en: false),
          'pierścień R45 (ASME B16.20), NPS 6 Class 600');
      expect(gasketLineLabel(g, en: true),
          'ring R45 (ASME B16.20), NPS 6 Class 600');
      expect(o.studs.single.qty, 36);
    });

    test('połączenie spoza tabeli jest pomijane, nie zgadywane', () {
      final o = buildBoltKitOrder([
        _j('a', 125, 300),
        _j('b', 15, 150, facing: FlangeFacing.rtj),
        _j('c', 50, 150),
      ]);
      expect(o.joints.map((j) => j.id), ['c']);
      expect(o.totalStuds, 4);
    });
  });

  group('zapas', () {
    test('10 %: 48 → 53, 96 → 106, 4 → 5 (zawsze w górę)', () {
      expect(withSpare(48, 10), 53);
      expect(withSpare(96, 10), 106);
      expect(withSpare(4, 10), 5);
    });

    test('dokładnie na całości: 100 + 5 % = 105, 20 + 5 % = 21, 0 % bez zmian',
        () {
      expect(withSpare(100, 5), 105);
      expect(withSpare(20, 5), 21);
      expect(withSpare(48, 0), 48);
      expect(withSpare(0, 20), 0);
    });

    test('zapas liczony od sumy pozycji, nie od każdego połączenia', () {
      // 2 połączenia × 4 szpilki = 8; 8 × 1,05 = 8,4 → 9 (po połączeniu:
      // 4,2 → 5 dwa razy dałoby 10).
      final o = buildBoltKitOrder([
        _j('a', 50, 150),
        _j('b', 50, 150, gasket: RfGasket.sheet),
      ], sparePercent: 5);
      expect(o.studs.single.qty, 8);
      expect(o.spare(o.studs.single.qty), 9);
      expect(qtyLabel(8, 5, en: false), '8 szt. + zapas 5 % = 9 szt.');
      expect(qtyLabel(8, 5, en: true), '8 pcs + 5 % spare = 9 pcs');
      expect(qtyLabel(8, 0, en: false), '8 szt.');
    });

    test('nieznany zapas → 0', () {
      expect(
          buildBoltKitOrder([_j('a', 50, 150)], sparePercent: 7).sparePercent,
          0);
    });
  });

  group('lista połączeń', () {
    test('sameKindAs: RTJ nie patrzy na typ uszczelki RF', () {
      expect(
          _j('a', 50, 600, facing: FlangeFacing.rtj).sameKindAs(_j('b', 50, 600,
              facing: FlangeFacing.rtj, gasket: RfGasket.sheet)),
          isTrue);
      expect(
          _j('a', 50, 600).sameKindAs(_j('b', 50, 600, gasket: RfGasket.sheet)),
          isFalse);
      expect(
          _j('a', 50, 600)
              .sameKindAs(_j('b', 50, 600, material: BoltMaterial.b7m)),
          isFalse);
    });

    test('liczba połączeń 1–999', () {
      expect(isValidJointCount(0), isFalse);
      expect(isValidJointCount(1), isTrue);
      expect(isValidJointCount(kMaxJointCount), isTrue);
      expect(isValidJointCount(kMaxJointCount + 1), isFalse);
    });
  });

  group('JSON', () {
    test('zapis i odczyt bez strat', () {
      final s = BoltKitState(joints: [
        _j('a', 150, 300, count: 4),
        _j('b', 80, 1500,
            facing: FlangeFacing.rtj, material: BoltMaterial.l7, count: 2),
      ], sparePercent: 10);
      final d = decodeBoltKitReport(encodeBoltKit(s));
      expect(d.intact, isTrue);
      expect(d.state.sparePercent, 10);
      expect(encodeBoltKit(d.state), encodeBoltKit(s));
    });

    test('pusty zapis → pusty stan, nienaruszony', () {
      expect(decodeBoltKitReport(null).intact, isTrue);
      expect(decodeBoltKitReport('  ').state.joints, isEmpty);
    });

    test('uszkodzony JSON → pusty stan zamiast wyjątku', () {
      for (final raw in ['{"v":1,"joints":[{', 'null', '[]', '"x"', '{}']) {
        final d = decodeBoltKitReport(raw);
        expect(d.state.joints, isEmpty, reason: raw);
        expect(d.intact, isFalse, reason: raw);
      }
    });

    test('wpisy uszkodzone / spoza tabeli pomijane, reszta zostaje', () {
      final good = _j('ok', 100, 300, count: 2).toJson();
      final raw = jsonEncode({
        'v': 1,
        'spare': 5,
        'joints': [
          good,
          {...good, 'id': 'dn125', 'dn': 125},
          {...good, 'id': 'rtj', 'dn': 15, 'cls': 150, 'facing': 'rtj'},
          {...good, 'id': 'zero', 'count': 0},
          {...good, 'id': 'big', 'count': 1000},
          {...good, 'id': 'mat', 'material': 'b99'},
          {...good, 'id': 'str', 'dn': '100'},
          good, // powtórzone id
          'śmieć',
        ],
      });
      final d = decodeBoltKitReport(raw);
      expect(d.state.joints.map((j) => j.id), ['ok']);
      expect(d.state.sparePercent, 5);
      expect(d.intact, isFalse);
    });

    test('nieznane pole wpisu (nowsza wersja) → wpis zostaje, zapis naruszony',
        () {
      final raw = jsonEncode({
        'v': 1,
        'spare': 0,
        'joints': [
          {..._j('a', 100, 300).toJson(), 'tag': 'L-101'},
        ],
      });
      final d = decodeBoltKitReport(raw);
      expect(d.state.joints.single.id, 'a');
      expect(d.intact, isFalse);
    });

    test('zły zapas → 0 i zapis oznaczony jako naruszony', () {
      final d = decodeBoltKitReport(
          jsonEncode({'v': 1, 'spare': 12, 'joints': <Object>[]}));
      expect(d.state.sparePercent, 0);
      expect(d.intact, isFalse);
    });
  });
}
