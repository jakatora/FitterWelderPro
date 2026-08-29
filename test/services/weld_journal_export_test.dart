import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/weld_journal_export.dart';

/// Builds a record with only the fields a test cares about; everything else
/// defaults to an empty string, which is what an unfilled editor produces.
WeldJournalRecord _rec({
  String weldNo = 'W-001',
  String projectName = '',
  String pipeName = '',
  String material = '',
  String od = '',
  String t = '',
  String method = '',
  String welder = '',
  String date = '',
  String notes = '',
  String status = 'PENDING',
  String weldType = '',
  String fitter = '',
  String heatNo1 = '',
  String heatNo2 = '',
  String couponRef = '',
  String exam = '',
  String wpsRef = '',
}) =>
    WeldJournalRecord(
      weldNo: weldNo,
      projectName: projectName,
      pipeName: pipeName,
      material: material,
      od: od,
      t: t,
      method: method,
      welder: welder,
      date: date,
      notes: notes,
      status: status,
      weldType: weldType,
      fitter: fitter,
      heatNo1: heatNo1,
      heatNo2: heatNo2,
      couponRef: couponRef,
      exam: exam,
      wpsRef: wpsRef,
    );

/// Splits the CSV into logical rows: BOM stripped, trailing empty element
/// dropped. Rows here never span multiple lines except in the embedded
/// newline test, which parses by hand.
List<String> _rows(String csv) {
  final body = csv.startsWith(kUtf8Bom) ? csv.substring(1) : csv;
  final rows = body.split(kWeldJournalCsvEol);
  if (rows.isNotEmpty && rows.last.isEmpty) rows.removeLast();
  return rows;
}

void main() {
  group('CSV envelope', () {
    test('starts with a UTF-8 BOM so Excel does not mangle diacritics', () {
      final csv = buildWeldJournalCsv([_rec()]);
      expect(csv.codeUnitAt(0), 0xFEFF);
      final bytes = utf8.encode(csv);
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    });

    test('uses a semicolon separator, not a comma', () {
      final csv = buildWeldJournalCsv([_rec(weldNo: 'W-001', material: '316L')]);
      final header = _rows(csv).first;
      expect(header.split(';').length, weldJournalCsvHeaders.length);
      // A stray comma separator would make this a single-column file.
      expect(header.contains(';'), isTrue);
    });

    test('every row is terminated with CRLF', () {
      final csv = buildWeldJournalCsv([_rec(weldNo: 'W-001'), _rec(weldNo: 'W-002')]);
      // header + 2 data rows, each closed by CRLF
      expect('\r\n'.allMatches(csv).length, 3);
      expect(csv.endsWith('\r\n'), isTrue);
      // No bare LF sneaking in from a hand-written string somewhere.
      expect(csv.replaceAll('\r\n', '').contains('\n'), isFalse);
    });

    test('empty list still yields BOM + header only', () {
      final csv = buildWeldJournalCsv(const []);
      final rows = _rows(csv);
      expect(rows.length, 1);
      expect(rows.first, weldJournalCsvHeaders.join(';'));
      expect(csv.codeUnitAt(0), 0xFEFF);
    });
  });

  group('column order', () {
    test('headers follow the WeldEntry field order', () {
      expect(weldJournalCsvHeaders, [
        'Nr spoiny / Weld no.',
        'Projekt / Project',
        'Rura / Pipe',
        'Materiał / Material',
        'OD (mm)',
        't (mm)',
        'Metoda / Method',
        'Spawacz / Welder',
        'Data / Date',
        'Uwagi / Notes',
        'Status',
        'Typ spoiny / Weld type',
        'Monter / Fitter',
        'Nr wytopu 1 / Heat no. 1',
        'Nr wytopu 2 / Heat no. 2',
        'Kupon próbny / Test coupon',
        'Wynik badania / Examination',
        'Nr WPS / WPS no.',
      ]);
    });

    test('values land in the same columns as their headers', () {
      final csv = buildWeldJournalCsv([
        _rec(
          weldNo: 'SP-001-W005',
          projectName: 'Browar',
          pipeName: 'L-12',
          material: '316L',
          od: '60.3',
          t: '2.0',
          method: 'TIG',
          welder: 'JK-12',
          date: '2026-05-17',
          notes: 'gran OK',
          status: 'OK',
          weldType: 'ORBITAL',
          fitter: 'MN-03',
          heatNo1: 'H-778',
          heatNo2: 'H-902',
          couponRef: 'C-2026-05-17-A',
          exam: 'VT OK',
          wpsRef: 'WPS-316L-TIG-01',
        ),
      ]);
      expect(_rows(csv)[1].split(';'), [
        'SP-001-W005',
        'Browar',
        'L-12',
        '316L',
        '60.3',
        '2.0',
        'TIG',
        'JK-12',
        '2026-05-17',
        'gran OK',
        'OK',
        'ORBITAL',
        'MN-03',
        'H-778',
        'H-902',
        'C-2026-05-17-A',
        'VT OK',
        'WPS-316L-TIG-01',
      ]);
    });

    test('rows keep the order they were given', () {
      final csv = buildWeldJournalCsv([
        _rec(weldNo: 'W-003'),
        _rec(weldNo: 'W-001'),
        _rec(weldNo: 'W-002'),
      ]);
      final rows = _rows(csv);
      expect(rows[1].split(';').first, 'W-003');
      expect(rows[2].split(';').first, 'W-001');
      expect(rows[3].split(';').first, 'W-002');
    });
  });

  group('RFC 4180 escaping', () {
    test('a semicolon inside a note does not shift the later columns', () {
      final csv = buildWeldJournalCsv([
        _rec(notes: 'gran OK; lico do szlifowania', status: 'OK'),
      ]);
      final row = _rows(csv)[1];
      expect(row.contains('"gran OK; lico do szlifowania"'), isTrue);
      // The quoted field must not split the row into an extra column.
      expect(row.split('"')[2].startsWith(';OK;'), isTrue);
    });

    test('a double quote is doubled and the field wrapped', () {
      final csv = buildWeldJournalCsv([_rec(notes: 'spoina "na zimno"')]);
      expect(_rows(csv)[1].contains('"spoina ""na zimno"""'), isTrue);
    });

    test('escapeCsvField leaves plain values untouched', () {
      expect(escapeCsvField('W-001'), 'W-001');
      expect(escapeCsvField(''), '');
      expect(escapeCsvField('60,3'), '60,3'); // comma is NOT the separator
    });

    test('escapeCsvField quotes embedded newlines', () {
      expect(escapeCsvField('linia 1\nlinia 2'), '"linia 1\nlinia 2"');
      expect(escapeCsvField('linia 1\r\nlinia 2'), '"linia 1\r\nlinia 2"');
    });

    test('a multi-line note stays inside one quoted field', () {
      final csv = buildWeldJournalCsv([_rec(notes: 'grań OK\ndo przeszlifowania')]);
      final body = csv.substring(1);
      // Quotes come in pairs -> the embedded newline is inside a quoted field.
      expect('"'.allMatches(body).length.isEven, isTrue);
      expect(body.contains('"grań OK\ndo przeszlifowania"'), isTrue);
    });
  });

  group('Polish characters', () {
    test('diacritics survive verbatim and round-trip through UTF-8', () {
      final csv = buildWeldJournalCsv([
        _rec(
          welder: 'Łukasz Żółć',
          projectName: 'Ścieżka gorąca',
          notes: 'grań OK, lico do przeszlifowania',
          exam: 'boroskop poz. 2 — zaliczony',
        ),
      ]);
      expect(csv.contains('Łukasz Żółć'), isTrue);
      expect(csv.contains('Ścieżka gorąca'), isTrue);
      expect(csv.contains('grań OK'), isTrue);
      // utf8.decode ZDEJMUJE wiodacy BOM (tak dziala Utf8Decoder w Darcie), wiec
      // round-trip porownujemy z trescia bez BOM. Sam BOM jest sprawdzany bajtowo
      // w tescie 'starts with a UTF-8 BOM'.
      expect(utf8.decode(utf8.encode(csv)), csv.substring(1));
    });

    test('header keeps its Polish labels', () {
      final header = _rows(buildWeldJournalCsv(const [])).first;
      expect(header.contains('Materiał'), isTrue);
      expect(header.contains('Kupon próbny'), isTrue);
    });
  });

  group('summaries for the PDF header', () {
    test('date range spans the first and last ISO date', () {
      final range = weldJournalDateRange([
        _rec(date: '2026-05-17'),
        _rec(date: '2026-03-02'),
        _rec(date: '2026-08-29'),
      ]);
      expect(range, '2026-03-02 - 2026-08-29');
    });

    test('single day reports one date, not a range', () {
      expect(weldJournalDateRange([_rec(date: '2026-05-17'), _rec(date: '2026-05-17')]),
          '2026-05-17');
    });

    test('malformed and empty dates are ignored', () {
      expect(weldJournalDateRange([_rec(date: ''), _rec(date: '2026-0')]), '');
      expect(
        weldJournalDateRange([_rec(date: '17.05.2026'), _rec(date: '2026-05-17')]),
        '2026-05-17',
      );
    });

    test('welders are distinct, in first-seen order', () {
      expect(
        weldJournalWelders([
          _rec(welder: 'JK-12'),
          _rec(welder: 'MN-03'),
          _rec(welder: 'JK-12'),
          _rec(welder: '  '),
        ]),
        'JK-12, MN-03',
      );
    });

    test('tally counts every row exactly once', () {
      final t = weldJournalTally([
        _rec(status: 'OK'),
        _rec(status: 'OK'),
        _rec(status: 'NOK'),
        _rec(status: 'PENDING'),
        _rec(status: 'legacy-value'),
      ]);
      expect(t.total, 5);
      expect(t.ok, 2);
      expect(t.nok, 1);
      expect(t.pending, 1);
      expect(t.other, 1);
      expect(t.ok + t.nok + t.pending + t.other, t.total);
    });
  });

  group('file name', () {
    test('plain export is named by date', () {
      expect(
        weldJournalFileName(extension: 'csv', generatedAt: DateTime(2026, 8, 29)),
        'Dziennik_spoin_2026-08-29.csv',
      );
    });

    test('ALL filter is not written into the name', () {
      expect(
        weldJournalFileName(
            extension: 'pdf', generatedAt: DateTime(2026, 1, 5), filterLabel: 'ALL'),
        'Dziennik_spoin_2026-01-05.pdf',
      );
    });

    test('an active filter is part of the name and sanitised', () {
      expect(
        weldJournalFileName(
            extension: 'pdf', generatedAt: DateTime(2026, 1, 5), filterLabel: 'NOK'),
        'Dziennik_spoin_NOK_2026-01-05.pdf',
      );
      expect(
        weldJournalFileName(
            extension: 'csv', generatedAt: DateTime(2026, 1, 5), filterLabel: 'a/b c'),
        'Dziennik_spoin_a_b_c_2026-01-05.csv',
      );
    });
  });
}
