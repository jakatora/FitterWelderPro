// PDF dziennika spoin powstaje w osobnym izolacie (Isolate.run), nie na
// wątku UI. 400 spoin to ok. 3 s pracy na desktopowym JIT — na słabym
// Androidzie ekran zamarzał bez animacji postępu. Test mierzy, że pętla
// zdarzeń głównego izolatu żyje, gdy PDF się renderuje.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/services/weld_journal_export.dart';

Uint8List _fontBytes(String file) =>
    File('assets/fonts/$file').readAsBytesSync();

WeldJournalRecord _rec(int i) => WeldJournalRecord(
      weldNo: 'SP-${i ~/ 10 + 1}-W${i % 10 + 1}',
      projectName: 'Rozbudowa WFI',
      pipeName: '2"-WFI-101-316L',
      material: '316L',
      od: '60,3',
      t: '2,0',
      method: 'TIG',
      welder: 'JK-12',
      fitter: 'Łukasz Żółć',
      date: '2026-09-${(i % 28 + 1).toString().padLeft(2, '0')}',
      status: i % 7 == 0 ? 'NOK' : 'OK',
      notes: i % 3 == 0 ? 'Grań OK, lico do przeszlifowania; ' * 3 : '',
      ndt: {
        NdtMethod.vt: const WeldNdt(
            scope: NdtScope.required,
            result: NdtResult.ok,
            reportNo: 'VT-2026-0042',
            date: '2026-09-21'),
      },
      repairs: i % 9 == 0 ? const ['R1 · 2026-09-22 · pęknięcie grani'] : const [],
    );

void main() {
  test('renderPdfBytes: prawidłowy PDF z polskimi znakami i nagłówkiem',
      () async {
    final bytes = await WeldJournalExport.renderPdfBytes(
      records: [for (var i = 0; i < 12; i++) _rec(i)],
      fontBytes: _fontBytes('Roboto-Regular.ttf'),
      boldFontBytes: _fontBytes('Roboto-Bold.ttf'),
      header: const WeldJournalPdfHeader(
          company: 'ZUT Żerań', documentNo: 'WJ-01', revision: 'B'),
      filterDescription: 'Projekt: Rozbudowa WFI',
      welderFallback: 'JK-12',
      generatedAt: DateTime(2026, 9, 24, 14, 30),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10 * 1024));
  });

  test('400 spoin: główny izolat nie jest blokowany podczas renderowania',
      () async {
    final records = [for (var i = 0; i < 400; i++) _rec(i)];
    final font = _fontBytes('Roboto-Regular.ttf');
    final bold = _fontBytes('Roboto-Bold.ttf');

    var ticks = 0;
    var longestGapMs = 0;
    final sw = Stopwatch()..start();
    var last = sw.elapsedMilliseconds;
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      ticks++;
      final now = sw.elapsedMilliseconds;
      if (now - last > longestGapMs) longestGapMs = now - last;
      last = now;
    });
    final Uint8List bytes;
    try {
      bytes = await WeldJournalExport.renderPdfBytes(
        records: records,
        fontBytes: font,
        boldFontBytes: bold,
        generatedAt: DateTime(2026, 9, 24),
      );
    } finally {
      timer.cancel();
    }
    final totalMs = sw.elapsedMilliseconds;

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Na wątku głównym render trwa jednym kawałkiem (sekundy bez ticka).
    // W izolacie timer tyka przez cały czas; próg z zapasem na wolne CI.
    expect(longestGapMs, lessThan(1000),
        reason: 'najdłuższa przerwa pętli zdarzeń: $longestGapMs ms '
            'przy renderze $totalMs ms ($ticks ticków)');
    expect(ticks, greaterThan(totalMs ~/ 100),
        reason: 'pętla zdarzeń powinna tykać w trakcie renderu');
  });
}
