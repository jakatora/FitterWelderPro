// Katalog take-outów (services/takeout_catalog.dart) wobec norm.
//
// Wartości oczekiwane przepisane z norm, NIE z kodu aplikacji:
//   ASME B16.9-2018
//     Tab. 6.1-1  kolana LR: A (90°), B (45°)
//     Tab. 6.1-4  kolana SR 90°: A = 1,0 × NPS, tylko od NPS 1
//     Tab. 6.1-6  kolana 3D: A, B
//     Tab. 6.1-7  trójniki równe: C
//     Tab. 6.1-10 dennice (zaślepki): E (ścianka ≤ granicznej), E1 (grubsza)
//     Tab. 6.1-11 redukcje: H
//     §6.2.4      segment kolana 90°: Bs = A × tan(θ/2)
//   ASME B16.10, Class 150 (kolumna „globe / lift check / swing check”,
//     przypis: swing check NPS 5 = 330, NPS 6 = 356)
//
// Liczby w mm wg kolumn metrycznych norm (w nawiasie cale).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/services/takeout_catalog.dart';

void main() {
  group('TakeoutCatalog — wartości ASME B16.9-2018', () {
    test('trójnik równy DN100 (NPS 4): C = 4.12 in = 105 mm, nie 102', () {
      expect(TakeoutCatalog.tee[100], 105);
    });

    test('cała kolumna C trójników równych', () {
      const expected = <int, int>{
        15: 25, 20: 29, 25: 38, 32: 48, 40: 57, 50: 64, 65: 76, 80: 86,
        100: 105, 150: 143, 200: 178, 250: 216, 300: 254,
      };
      expect(TakeoutCatalog.tee, expected);
    });

    test('zaślepki: wymiar E (ścianka standardowa), nie E1', () {
      // Tab. 6.1-10: E / E1
      //   NPS 3/4: 25 (1.00) / 25      NPS 2 1/2: 38 (1.50) / 51 (2.00)
      //   NPS 3:   51 (2.00) / 64      NPS 4:     64 (2.50) / 76 (3.00)
      //   NPS 6:   89 (3.50) / 102     NPS 8:    102 (4.00) / 127
      //   NPS 10: 127 (5.00) / 152     NPS 12:   152 (6.00) / 178
      const expected = <int, int>{
        15: 25, 20: 25, 25: 38, 32: 38, 40: 38, 50: 38, 65: 38, 80: 51,
        100: 64, 150: 89, 200: 102, 250: 127, 300: 152,
      };
      expect(TakeoutCatalog.cap, expected);
    });

    test('kolano SR 90° istnieje od NPS 1 (DN25), nie ma DN15/DN20', () {
      const expected = <int, int>{
        25: 25, 32: 32, 40: 38, 50: 51, 65: 64, 80: 76, 100: 102, 150: 152,
        200: 203, 250: 254, 300: 305,
      };
      expect(TakeoutCatalog.elbow90SR, expected);
    });

    test('kolana LR 90°/45° — NPS 1/2, 3/4, 1 mają A = 38 (1.50 in)', () {
      const lr90 = <int, int>{
        15: 38, 20: 38, 25: 38, 32: 48, 40: 57, 50: 76, 65: 95, 80: 114,
        100: 152, 150: 229, 200: 305, 250: 381, 300: 457,
      };
      const lr45 = <int, int>{
        15: 16, 20: 19, 25: 22, 32: 25, 40: 29, 50: 35, 65: 44, 80: 51,
        100: 64, 150: 95, 200: 127, 250: 159, 300: 190,
      };
      expect(TakeoutCatalog.elbow90LR, lr90);
      expect(TakeoutCatalog.elbow45LR, lr45);
    });

    test('redukcje: H wg Tab. 6.1-11 (od NPS 3/4 × 1/2 = 38)', () {
      const expected = <int, int>{
        20: 38, 25: 51, 32: 51, 40: 64, 50: 76, 65: 89, 80: 89, 100: 102,
        150: 140, 200: 152, 250: 178, 300: 203,
      };
      expect(TakeoutCatalog.reducer, expected);
    });

    test('mapy katalogu i tabela kolan kElbowTakeouts się nie rozjeżdżają',
        () {
      for (final e in TakeoutCatalog.elbow90LR.entries) {
        expect(elbowTakeoutForDn(e.key)!.lr90, e.value, reason: 'LR90 DN${e.key}');
      }
      for (final e in TakeoutCatalog.elbow45LR.entries) {
        expect(elbowTakeoutForDn(e.key)!.lr45, e.value, reason: 'LR45 DN${e.key}');
      }
      for (final e in TakeoutCatalog.elbow90SR.entries) {
        expect(elbowTakeoutForDn(e.key)!.sr90, e.value, reason: 'SR90 DN${e.key}');
      }
    });
  });

  group('TakeoutCatalog — kołnierze ASME B16.5 Class 150 RF', () {
    // B16.5 Class 150 (wymiary z przylgą 1,6 mm): C = grubość talerza,
    // Y = długość przez szyjkę kołnierza WN. NPS 4: C = 0.94 in → 24 mm,
    // Y = 3.00 in = 76,2 → 76 mm. NPS 8 i NPS 10: Y = 4.00 in = 101,6.
    test('kolumna C (talerz) i Y (WN, przez szyjkę) są rozdzielone', () {
      expect(TakeoutCatalog.flangeThickness150C[100], 24);
      expect(TakeoutCatalog.flangeWN150Y[100], 76);
      expect(TakeoutCatalog.flangeWN150Y[250], 102);
      for (final dn in TakeoutCatalog.flangeWN150Y.keys) {
        expect(TakeoutCatalog.flangeWN150Y[dn]!,
            greaterThan(TakeoutCatalog.flangeThickness150C[dn]!),
            reason: 'DN$dn: Y musi być dłuższe od grubości talerza C');
      }
    });

    test('stara nazwa flangeWN150 to nadal kolumna C (alias dla skanera)', () {
      expect(TakeoutCatalog.flangeWN150, TakeoutCatalog.flangeThickness150C);
    });

    test('picker: WN liczy Y, SO liczy C', () {
      final byName = {
        for (final e in TakeoutCatalog.entriesForDn(100)) e.name: e.mm,
      };
      expect(byName['Kołnierz WN cl.150 (Y, przez szyjkę)'], 76);
      expect(byName['Kołnierz SO cl.150 (tarcza C)'], 24);
    });
  });

  group('TakeoutCatalog — zawory ASME B16.10 Class 150', () {
    test('zwrotny klapowy (swing check): DN150 356, DN200 495, DN250 622, '
        'DN300 698', () {
      // B16.10 Class 150, kolumna globe/lift check/swing check:
      //   NPS 8 = 19.50 in = 495, NPS 10 = 24.50 = 622, NPS 12 = 27.50 = 698;
      //   przypis: swing check NPS 6 = 356 (14.00 in).
      const expected = <int, int>{
        50: 203, 65: 216, 80: 241, 100: 292, 150: 356, 200: 495, 250: 622,
        300: 698,
      };
      expect(TakeoutCatalog.checkValve150, expected);
    });

    test('grzybkowy (globe): DN150 = 406 (16.00 in), reszta jak zwrotny', () {
      const expected = <int, int>{
        50: 203, 65: 216, 80: 241, 100: 292, 150: 406, 200: 495, 250: 622,
        300: 698,
      };
      expect(TakeoutCatalog.globeValve150, expected);
    });
  });

  group('b169ElbowTakeout — take-out kolana pod dowolnym kątem', () {
    test('LR 90° DN50 = tablicowe A = 76 mm', () {
      final r = b169ElbowTakeout(
          dn: 50, type: ElbowRadiusType.long15D, angleDeg: 90)!;
      expect(r.mm, 76);
      expect(r.basis, TakeoutBasis.tableA90);
      expect(r.a90Mm, 76);
    });

    test('LR 45° DN50 = tablicowe B = 35 mm (nie R·tan22,5° = 31,5)', () {
      final r = b169ElbowTakeout(
          dn: 50, type: ElbowRadiusType.long15D, angleDeg: 45)!;
      expect(r.mm, 35);
      expect(r.basis, TakeoutBasis.tableB45);
    });

    test('LR 30° DN100 = segment §6.2.4: 152 × tan 15° = 40,73 mm', () {
      final r = b169ElbowTakeout(
          dn: 100, type: ElbowRadiusType.long15D, angleDeg: 30)!;
      expect(r.mm, closeTo(152 * math.tan(15 * math.pi / 180), 1e-9));
      expect(r.mm, closeTo(40.73, 0.01));
      expect(r.basis, TakeoutBasis.segment);
    });

    test('SR 45° nie istnieje w B16.9 — liczony jako segment SR 90°', () {
      // DN50 SR: A = 51 → 51 × tan 22,5° = 21,125 mm
      final r = b169ElbowTakeout(
          dn: 50, type: ElbowRadiusType.short1D, angleDeg: 45)!;
      expect(r.mm, closeTo(21.125, 0.001));
      expect(r.basis, TakeoutBasis.segment);
    });

    test('3D 45° DN50 = tablicowe B = 63 mm', () {
      final r = b169ElbowTakeout(
          dn: 50, type: ElbowRadiusType.long3D, angleDeg: 45)!;
      expect(r.mm, 63);
      expect(r.basis, TakeoutBasis.tableB45);
    });

    test('brak wartości zamiast zgadywania', () {
      // SR poniżej NPS 1 nie istnieje.
      expect(
          b169ElbowTakeout(
              dn: 15, type: ElbowRadiusType.short1D, angleDeg: 90),
          isNull);
      // DN spoza tabeli — bez „najbliższego” wiersza.
      expect(
          b169ElbowTakeout(
              dn: 110, type: ElbowRadiusType.long15D, angleDeg: 90),
          isNull);
      // Kolano B16.9 ma najwyżej 90°.
      expect(
          b169ElbowTakeout(
              dn: 100, type: ElbowRadiusType.long15D, angleDeg: 120),
          isNull);
      expect(
          b169ElbowTakeout(dn: 100, type: ElbowRadiusType.long15D, angleDeg: 0),
          isNull);
    });
  });
}
