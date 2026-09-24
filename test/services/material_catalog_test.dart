// Katalog gatunków: grupy P-No wg ASME IX QW/QB-422 i rozdzielenie P22/P91.
//
//  • P91 (9Cr-1Mo-V) to P-No 15E (grupa stali CSEF wydzielona z P-No 5B) —
//    nie „P-No 5” (weldfabworld.com „ASME P-Number Table”, clause5.io
//    „ASME IX P-Numbers”).
//  • P22 (2¼Cr-1Mo) to P-No 5A.
//  • Duplex 2205/2507 to P-No 10H.
//  • PWHT z katalogu: P22 690–720 °C, P91 750–770 °C — nie wolno ich łączyć.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/material_catalog.dart';

void main() {
  const expected = <String, String>{
    'A106 B': '1',
    'A53 B': '1',
    'A516 70': '1',
    'A335 P1': '3',
    'P11 / T11': '4',
    'P22 / T22': '5A',
    'P91 / T91': '15E',
    '410 SS': '6',
    '304 / 304L': '8',
    '316 / 316L': '8',
    '321': '8',
    '347': '8',
    '2205 Duplex': '10H',
    '2507 SuperDuplex': '10H',
    'Inconel 625': '43',
    'Monel 400': '42',
  };

  for (final e in expected.entries) {
    test('${e.key} → P-No ${e.value}', () {
      expect(MaterialCatalog.findByKey(e.key)!.pNo, e.value);
    });
  }

  test('katalog ma dokładnie te gatunki', () {
    expect(MaterialCatalog.all.map((m) => m.key).toSet(), expected.keys.toSet());
  });

  test('P22 i P91 mają różne PWHT', () {
    final p22 = MaterialCatalog.findByKey('P22 / T22')!;
    final p91 = MaterialCatalog.findByKey('P91 / T91')!;
    expect(p22.notesPl, contains('690–720 °C'));
    expect(p22.notesPl, isNot(contains('750')));
    expect(p91.notesPl, contains('750–770 °C'));
  });

  test('numer bazowy P-No do porównań (15E → 15, 5A → 5, 10H → 10)', () {
    expect(MaterialCatalog.findByKey('P91 / T91')!.pNoBase, 15);
    expect(MaterialCatalog.findByKey('P22 / T22')!.pNoBase, 5);
    expect(MaterialCatalog.findByKey('2205 Duplex')!.pNoBase, 10);
    expect(MaterialCatalog.findByKey('A106 B')!.pNoBase, 1);
  });

  test('stale P-No 1 nie udają minimum kodowego w notce „praktyka WPS”', () {
    for (final key in ['A106 B', 'A53 B']) {
      final m = MaterialCatalog.findByKey(key)!;
      expect(m.practicePl, isNot(contains('10 °C (>25 mm: 50 °C)')));
      expect(m.practiceEn, isNot(contains('10 °C (>25 mm: 50 °C)')));
    }
  });

  test('każdy gatunek ma notki PL i EN', () {
    for (final m in MaterialCatalog.all) {
      expect(m.practicePl, isNotEmpty, reason: m.key);
      expect(m.practiceEn, isNotEmpty, reason: m.key);
      expect(m.notesEn.isEmpty, m.notesPl.isEmpty, reason: m.key);
    }
  });
}
