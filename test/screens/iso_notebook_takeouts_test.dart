// Regression net for the take-out tables behind `lib/screens/iso_notebook_screen.dart`.
//
// Every defect covered here ends the same way: a pipe cut to the wrong length.
//
//   1. A weld-neck flange was subtracted using ASME B16.5 column C (the
//      thickness of the disc) instead of column Y (the length through the
//      hub). DN100: 24 mm instead of 76 mm, so every WN joint left the pipe
//      52 mm long — and the WN/SO chips did not touch the length field at
//      all, so the fitter had no hint the number was for the other type.
//   2. One B16.10 gate-valve table backed all five valve kinds on the
//      palette. A DN100 butterfly valve is a ~52 mm wafer body; the app
//      subtracted 229 mm and the pipe came out 177 mm short — scrap.
//   3. The automatic take-out pass and the hand-entered "Trójnik (CTE)" row
//      from the ASME catalog picker must not both bill the same fitting.
//      These tests pin the alias table to the strings the picker actually
//      writes, because a rename there would silently double the deduct.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/models/prefab/end_connection.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/takeout_catalog.dart';

void main() {
  group('isoFlangeAxialLengthMm — weld neck uses B16.5 column Y', () {
    test('DN100 WN is the 76 mm hub length, not the 24 mm disc', () {
      expect(isoFlangeAxialLengthMm(dn: 100, type: EndConnection.weldNeck), 76);
    });

    test('DN100 slip-on keeps the disc thickness', () {
      expect(isoFlangeAxialLengthMm(dn: 100, type: EndConnection.slipOn), 24);
    });

    test('WN is longer than SO at every tabulated DN', () {
      for (final dn in const [15, 20, 25, 32, 40, 50, 65, 80, 100, 150, 200, 250, 300]) {
        final wn = isoFlangeAxialLengthMm(dn: dn, type: EndConnection.weldNeck);
        final so = isoFlangeAxialLengthMm(dn: dn, type: EndConnection.slipOn);
        expect(wn, isNotNull, reason: 'no Y value for DN$dn');
        expect(so, isNotNull, reason: 'no C value for DN$dn');
        expect(wn!, greaterThan(so!),
            reason: 'DN$dn: hub length must exceed disc thickness');
      }
    });

    test('whole B16.5 column Y, DN15..DN300', () {
      // B16.5 Class 150 WN, Y incl. 1.6 mm RF: NPS 8 = NPS 10 = 4.00 in.
      // = 101.6 mm (sources without the RF list 3.94 in. / 100 mm for both).
      // DN250 was pinned at 108 here — a value that is in no B16.5 table.
      const expected = <int, int>{
        15: 48, 20: 52, 25: 56, 32: 57, 40: 62, 50: 64, 65: 70, 80: 70,
        100: 76, 150: 89, 200: 102, 250: 102, 300: 114,
      };
      for (final e in expected.entries) {
        expect(isoFlangeAxialLengthMm(dn: e.key, type: EndConnection.weldNeck),
            e.value,
            reason: 'DN${e.key}');
      }
    });

    test('the notebook Y table and the catalog picker Y table agree', () {
      for (final e in TakeoutCatalog.flangeWN150Y.entries) {
        expect(isoFlangeAxialLengthMm(dn: e.key, type: EndConnection.weldNeck),
            e.value,
            reason: 'DN${e.key}');
        expect(isoFlangeAxialLengthMm(dn: e.key, type: EndConnection.slipOn),
            TakeoutCatalog.flangeWN150[e.key],
            reason: 'DN${e.key} C');
      }
    });

    test('socket / threaded / lap joint fall on the disc thickness', () {
      for (final t in const [
        EndConnection.socketWeld,
        EndConnection.threaded,
        EndConnection.lapJoint,
      ]) {
        expect(isoFlangeAxialLengthMm(dn: 100, type: t), 24, reason: t.code);
      }
    });

    test('DN outside the Class 150 tables returns null, never a stand-in', () {
      expect(isoFlangeAxialLengthMm(dn: 400, type: EndConnection.weldNeck),
          isNull);
      expect(isoFlangeAxialLengthMm(dn: 400, type: EndConnection.slipOn),
          isNull);
    });
  });

  group('isoValveFaceToFaceMm — one table per valve kind', () {
    test('DN100 butterfly is a wafer body, not a gate valve', () {
      expect(isoValveFaceToFaceMm('butterflyValve', 100), 52);
    });

    test('the butterfly wafer table, DN50..DN300', () {
      const expected = <int, int>{
        50: 43, 65: 46, 80: 46, 100: 52, 150: 56, 200: 60, 250: 68, 300: 78,
      };
      for (final e in expected.entries) {
        expect(isoValveFaceToFaceMm('butterflyValve', e.key), e.value,
            reason: 'DN${e.key}');
      }
    });

    test('butterfly is far shorter than a gate valve at every shared DN', () {
      for (final dn in const [50, 65, 80, 100, 150, 200, 250, 300]) {
        final wafer = isoValveFaceToFaceMm('butterflyValve', dn)!;
        final gate = isoValveFaceToFaceMm('gateValve', dn)!;
        expect(wafer, lessThan(gate ~/ 2),
            reason: 'DN$dn: wafer $wafer vs gate $gate');
      }
    });

    test('gate and ball read the B16.10 gate/ball column', () {
      expect(isoValveFaceToFaceMm('gateValve', 100), 229);
      expect(isoValveFaceToFaceMm('ballValve', 100), 229);
    });

    test('check valve reuses TakeoutCatalog rather than a private copy', () {
      for (final dn in const [50, 65, 80, 100, 150, 200, 250, 300]) {
        expect(isoValveFaceToFaceMm('checkValve', dn),
            TakeoutCatalog.checkValve150[dn],
            reason: 'DN$dn must come from the shared catalog');
      }
      expect(isoValveFaceToFaceMm('checkValve', 100), 292);
    });

    test('globe sits in the longer B16.10 column, not the gate one', () {
      expect(isoValveFaceToFaceMm('globeValve', 100), 292);
      expect(isoValveFaceToFaceMm('globeValve', 100),
          isNot(isoValveFaceToFaceMm('gateValve', 100)));
    });

    test('B16.10 Class 150: swing check NPS 6 = 356, globe NPS 6 = 406', () {
      // Column "globe / lift check / swing check": NPS 6 = 16.00 in. = 406,
      // footnote: swing check NPS 6 = 356. NPS 8/10/12 = 19.50 / 24.50 /
      // 27.50 in. = 495 / 622 / 698 for both.
      expect(isoValveFaceToFaceMm('checkValve', 150), 356);
      expect(isoValveFaceToFaceMm('globeValve', 150), 406);
      for (final e in const {200: 495, 250: 622, 300: 698}.entries) {
        expect(isoValveFaceToFaceMm('checkValve', e.key), e.value,
            reason: 'check DN${e.key}');
        expect(isoValveFaceToFaceMm('globeValve', e.key), e.value,
            reason: 'globe DN${e.key}');
      }
    });

    test('uncovered DN returns null instead of the DN50 gate length', () {
      for (final dn in const [15, 20, 25, 32, 40]) {
        expect(isoValveFaceToFaceMm('gateValve', dn), isNull, reason: 'DN$dn');
        expect(isoValveFaceToFaceMm('butterflyValve', dn), isNull,
            reason: 'DN$dn');
      }
    });

    test('a non-valve tool name is not silently given a valve length', () {
      expect(isoValveFaceToFaceMm('elbow90', 100), isNull);
      expect(isoValveFaceToFaceMm('tee', 100), isNull);
      expect(isoValveFaceToFaceMm('', 100), isNull);
    });
  });

  group('isoStandardElbowCteMm — only values ASME B16.9 actually lists', () {
    test('LR 90° / LR 45° / SR 90° DN100 = 152 / 64 / 102', () {
      expect(isoStandardElbowCteMm(100, 'lr90'), 152);
      expect(isoStandardElbowCteMm(100, 'lr45'), 64);
      expect(isoStandardElbowCteMm(100, 'sr90'), 102);
    });

    test('SR 45° has no B16.9 value — 0, not the LR 45° number', () {
      // It used to return lr45 (DN100: 64) as if it were normative.
      for (final dn in const [25, 50, 100, 300]) {
        expect(isoStandardElbowCteMm(dn, 'sr45'), 0, reason: 'DN$dn');
      }
    });

    test('SR 90° below NPS 1 does not exist in B16.9 — 0, not 25', () {
      expect(isoStandardElbowCteMm(15, 'sr90'), 0);
      expect(isoStandardElbowCteMm(20, 'sr90'), 0);
      expect(isoStandardElbowCteMm(25, 'sr90'), 25);
    });
  });

  group('isoManualDeductAliases — no double-billed take-outs', () {
    /// Lower-cased names the ASME catalog picker writes into a deduct row.
    Set<String> pickerLabels(int dn) => TakeoutCatalog.entriesForDn(dn)
        .map((e) => e.name.trim().toLowerCase())
        .toSet();

    test('the tee alias is exactly what the catalog picker inserts', () {
      final aliases = isoManualDeductAliases('tee');
      expect(aliases, isNotEmpty);
      expect(pickerLabels(100), containsAll(aliases),
          reason: 'catalog label renamed without updating the alias table — '
              'the automatic pass would stop standing down and the tee '
              'take-out would be subtracted twice');
    });

    test('elbow aliases match the catalog picker labels', () {
      final labels = pickerLabels(100);
      expect(labels, containsAll(isoManualDeductAliases('elbow90')));
      expect(labels, containsAll(isoManualDeductAliases('elbow45')));
    });

    test('aliases are stored lower-cased so matching is case-insensitive', () {
      for (final tool in const ['elbow90', 'elbow45', 'tee']) {
        for (final a in isoManualDeductAliases(tool)) {
          expect(a, a.toLowerCase(), reason: '$tool alias "$a"');
        }
      }
    });

    test('kinds with no catalog entry claim nothing', () {
      // An olet has no B16.9 take-out row, so no hand-entered label may be
      // treated as covering it — suppressing on a wrong match would drop a
      // real deduct.
      expect(isoManualDeductAliases('olet'), isEmpty);
      expect(isoManualDeductAliases('gateValve'), isEmpty);
      expect(isoManualDeductAliases('flange'), isEmpty);
    });
  });
}
