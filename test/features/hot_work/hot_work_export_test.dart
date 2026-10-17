// PDF protokołu prac pożarowo niebezpiecznych renderuje się z Roboto
// (polskie znaki) — wypełniony i pusty, PL i EN; nazwa pliku z datą.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/services/hot_work_export.dart';

pw.Font _font(String f) => pw.Font.ttf(
    ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));

Future<List<int>> _render(HotWorkPermit p, {required bool english}) async {
  final doc = await HotWorkExport.buildPdfDocument(
    permit: p,
    english: english,
    font: _font('Roboto-Regular.ttf'),
    boldFont: _font('Roboto-Bold.ttf'),
    generatedAt: DateTime(2026, 10, 17, 9, 30),
  );
  return doc.save();
}

const _filled = HotWorkPermit(
  id: 'p',
  permitNo: 'ZPP/7/2026',
  location: 'Rafineria — instalacja HDS, kołnierz F-12 (żółta strefa)',
  description: 'Spawanie króćca DN50, szlifowanie spoin',
  workTypes: {HotWorkType.welding, HotWorkType.grinding},
  date: '2026-10-17',
  validFrom: '07:00',
  validTo: '15:00',
  contractor: 'Jan Kowalski',
  securedBy: 'Adam Nowak',
  fireWatch: 'Piotr Wiśniewski',
  issuer: 'Ewa Zając',
  dgwLimitPct: 5,
  measurements: [
    HotWorkMeasurement(time: '06:50', dgwPct: 0, note: 'studzienka K-3'),
    HotWorkMeasurement(time: '10:00', dgwPct: 7),
  ],
  fireWatchAfterMin: 60,
  checked: {'perm-written', 'comb-remove', 'ext-ready'},
  na: {'cyl-flashback'},
  notes: 'Koc gaśniczy pod rurociągiem; łączność radiowa z dyspozytornią.',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  test('wypełniony protokół — PL i EN', () async {
    for (final en in [false, true]) {
      final bytes = await _render(_filled, english: en);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('pusty protokół (bez pomiaru i progu) też się renderuje', () async {
    final blank = HotWorkPermit.blank(id: 'b', now: DateTime(2026, 10, 17))
        .copyWith(dgwLimitPct: null);
    final bytes = await _render(blank, english: false);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('nazwa pliku z datą pracy', () {
    expect(hotWorkFileName(_filled, english: false),
        'Prace_pozarowe_protokol_2026-10-17.pdf');
    expect(hotWorkFileName(_filled, english: true),
        'Hot_work_record_2026-10-17.pdf');
    expect(
        hotWorkFileName(_filled.copyWith(date: 'zła data'), english: false),
        'Prace_pozarowe_protokol.pdf');
  });
}
