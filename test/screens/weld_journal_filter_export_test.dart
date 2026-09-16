import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/screens/weld_journal_screen.dart';
import 'package:cut_list_app/services/weld_journal_export.dart';

/// The journal exports what it shows. These tests pin the selection shared by
/// the on-screen list (filterWeldEntries) and the CSV/PDF export
/// (weldJournalExportRecords), so an audit printout filtered to NOK can never
/// carry an OK joint, and an unfiltered one never silently drops a row.

WeldEntry _entry(
  String id,
  String weldNo,
  String status, {
  String welder = '',
  String date = '',
}) =>
    WeldEntry(
      id: id,
      weldNo: weldNo,
      projectName: 'Browar',
      pipeName: 'L-12',
      material: '316L',
      od: '60.3',
      t: '2.0',
      method: 'TIG',
      welder: welder,
      date: date,
      notes: '',
      status: status,
    );

/// Journal in display order (the DAO sorts by weld_no).
List<WeldEntry> _journal() => [
      _entry('a', 'W-001', 'OK', welder: 'JK-12', date: '2026-05-10'),
      _entry('b', 'W-002', 'NOK', welder: 'MN-03', date: '2026-05-12'),
      _entry('c', 'W-003', 'PENDING', welder: 'JK-12', date: '2026-05-20'),
      _entry('d', 'W-004', 'OK', welder: 'PR-07', date: '2026-05-01'),
      _entry('e', 'W-005', 'NOK', welder: 'JK-12', date: '2026-05-15'),
      _entry('f', 'W-006', 'REPAIR', welder: 'ZZ-99', date: '2026-04-30'),
    ];

/// CSV data rows (header dropped, BOM stripped), split into cells. None of the
/// test values contains a separator or quote, so a plain split is exact.
List<List<String>> _csvRows(List<WeldJournalRecord> records) {
  var csv = buildWeldJournalCsv(records);
  if (csv.startsWith(kUtf8Bom)) csv = csv.substring(1);
  final lines = csv.split(kWeldJournalCsvEol);
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines.skip(1).map((l) => l.split(kWeldJournalCsvSeparator)).toList();
}

final int _statusCol = weldJournalCsvHeaders.indexOf('Status');

void main() {
  test('NOK filter: CSV holds exactly the NOK welds shown, in screen order',
      () {
    final journal = _journal();
    final shown = filterWeldEntries(journal, 'NOK').map((e) => e.weldNo);
    expect(shown, ['W-002', 'W-005']);

    final rows = _csvRows(weldJournalExportRecords(journal, 'NOK'));
    expect(rows.map((r) => r.first).toList(), ['W-002', 'W-005']);
    expect(rows.map((r) => r[_statusCol]).toSet(), {'NOK'});
  });

  test('OK filter matches exactly and does not pick up NOK', () {
    final journal = _journal();
    final rows = _csvRows(weldJournalExportRecords(journal, 'OK'));
    expect(rows.map((r) => r.first).toList(), ['W-001', 'W-004']);
    expect(rows.map((r) => r[_statusCol]).toSet(), {'OK'});
  });

  test('PENDING filter exports the single pending weld', () {
    final rows = _csvRows(weldJournalExportRecords(_journal(), 'PENDING'));
    expect(rows.map((r) => r.first).toList(), ['W-003']);
  });

  test('ALL exports every weld, legacy status included, order kept', () {
    final journal = _journal();
    final rows = _csvRows(weldJournalExportRecords(journal, 'ALL'));
    expect(rows.map((r) => r.first).toList(),
        ['W-001', 'W-002', 'W-003', 'W-004', 'W-005', 'W-006']);
    expect(rows.length, filterWeldEntries(journal, 'ALL').length);
  });

  test('ALL returns a copy, not the screen list itself', () {
    final journal = _journal();
    final shown = filterWeldEntries(journal, 'ALL');
    shown.removeLast();
    expect(journal.length, 6);
  });

  test('export records mirror the shown entries field for field', () {
    final journal = _journal();
    final shown = filterWeldEntries(journal, 'NOK');
    final records = weldJournalExportRecords(journal, 'NOK');
    expect(records.length, shown.length);
    for (var i = 0; i < shown.length; i++) {
      expect(records[i].weldNo, shown[i].weldNo);
      expect(records[i].status, shown[i].status);
      expect(records[i].welder, shown[i].welder);
      expect(records[i].date, shown[i].date);
    }
  });

  test('PDF summary counts only the filtered welds', () {
    final records = weldJournalExportRecords(_journal(), 'NOK');
    final t = weldJournalTally(records);
    expect(t.total, 2);
    expect(t.nok, 2);
    expect(t.ok, 0);
    expect(t.pending, 0);
    expect(t.other, 0);
    // W-002 (MN-03, 2026-05-12) and W-005 (JK-12, 2026-05-15) only —
    // PR-07 / ZZ-99 and the 2026-04-30 date belong to hidden rows.
    expect(weldJournalWelders(records), 'MN-03, JK-12');
    expect(weldJournalDateRange(records), '2026-05-12 - 2026-05-15');
  });

  test('PDF summary for ALL counts the legacy row as other', () {
    final t = weldJournalTally(weldJournalExportRecords(_journal(), 'ALL'));
    expect(t.total, 6);
    expect(t.ok, 2);
    expect(t.nok, 2);
    expect(t.pending, 1);
    expect(t.other, 1);
  });

  test('active filter is written into the export file name', () {
    expect(
      weldJournalFileName(
          extension: 'csv',
          generatedAt: DateTime(2026, 9, 16),
          filterLabel: 'NOK'),
      'Dziennik_spoin_NOK_2026-09-16.csv',
    );
  });
}
