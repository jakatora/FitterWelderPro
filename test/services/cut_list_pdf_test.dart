// PDF listy cięć: polskie znaki, wydruk czarno-biały, etykiety segmentów
// i ostrzeżenie o cięciu dłuższym od sztangi.
//
// Wcześniej PDF powstawał na domyślnej Helvetice (tylko Latin-1): nazwa
// projektu „Łącznik żółć” kończyła się wyjątkiem albo pustymi kratkami, a
// lista odcinków była drukowana jasnoszarym tekstem (#E8ECF0) na białym
// papierze i ciemnymi wypełnieniami, które zjadają toner.
//
// Treść PDF czytamy z powrotem: strumienie są rozpakowywane (FlateDecode),
// a identyfikatory glifów zamieniane na znaki przez mapę ToUnicode osadzonej
// czcionki.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/heat_traceability.dart';
import 'package:cut_list_app/services/pdf_export_service.dart';

Project _project(String name, {double stock = 6000, double kerf = 3}) => Project(
      id: 'p1',
      name: name,
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      currentDiameterMm: 114.3,
      stockLengthMm: stock,
      sawKerfMm: kerf,
      gapMm: 0,
      createdAt: 0,
      updatedAt: 0,
    );

Segment _seg(int seqNo, double cutMm, {String isoExpr = ''}) => Segment(
      id: 'seg-$seqNo',
      projectId: 'p1',
      seqNo: seqNo,
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'FACE',
      isoExpr: isoExpr,
      isoMm: cutMm,
      cutMm: cutMm,
      createdAt: 0,
      updatedAt: 0,
    );

/// Regular Roboto for every weight. The text reader below decodes glyph ids
/// through one ToUnicode map, and a second (bold) subset numbers its glyphs
/// on its own — so content checks run on a one-font theme, while the test
/// 'produkcyjny motyw ma osobny krój pogrubiony' pins the real theme.
Future<pw.ThemeData> _oneFontTheme() async {
  final font = pw.Font.ttf(ByteData.sublistView(
      File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync()));
  return pw.ThemeData.withFont(
      base: font, bold: font, italic: font, boldItalic: font);
}

/// Every stream of the PDF, inflated when it is FlateDecode-compressed.
List<List<int>> _streams(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final result = <List<int>>[];
  final start = RegExp(r'(?<!end)stream\r?\n');
  var from = 0;
  while (true) {
    final m = start.firstMatch(raw.substring(from));
    if (m == null) break;
    final dataStart = from + m.end;
    final end = raw.indexOf('endstream', dataStart);
    if (end < 0) break;
    var data = bytes.sublist(dataStart, end);
    try {
      data = Uint8List.fromList(zlib.decode(data));
    } catch (_) {
      // Not compressed — keep as is.
    }
    result.add(data);
    from = end + 'endstream'.length;
  }
  return result;
}

/// Text drawn on the pages, glyph ids decoded through the ToUnicode maps.
String _pdfText(Uint8List bytes) {
  final streams = [for (final s in _streams(bytes)) latin1.decode(s)];
  final cmap = <int, String>{};
  for (final s in streams.where((s) => s.contains('beginbfchar'))) {
    for (final m in RegExp(r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4,})>')
        .allMatches(s)) {
      cmap[int.parse(m.group(1)!, radix: 16)] =
          String.fromCharCode(int.parse(m.group(2)!, radix: 16));
    }
  }
  final words = <String>[];
  // The pdf package writes every word as `[<glyph ids>]TJ` (or `<…> Tj`).
  final show = RegExp(r'\[[^\]]*\]\s*TJ|<[0-9A-Fa-f]*>\s*Tj');
  for (final s in streams.where((s) => s.contains('BT'))) {
    for (final m in show.allMatches(s)) {
      final buf = StringBuffer();
      for (final h in RegExp(r'<([0-9A-Fa-f]*)>').allMatches(m.group(0)!)) {
        final hex = h.group(1)!;
        for (var i = 0; i + 4 <= hex.length; i += 4) {
          buf.write(
              cmap[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '?');
        }
      }
      words.add(buf.toString());
    }
  }
  return words.join(' ').replaceAll(RegExp(r'\s+'), ' ');
}

/// Page content streams (the ones that draw text).
List<String> _contentStreams(Uint8List bytes) => [
      for (final s in _streams(bytes))
        if (latin1.decode(s).contains(' Tf')) latin1.decode(s),
    ];

double _luminance(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF retains fractional stock, kerf and actual wall thickness', () async {
    for (final english in [false, true]) {
      final bytes = await PdfExportService.buildCutListPdf(
        theme: await _oneFontTheme(),
        project: _project('QA', stock: 6000.25, kerf: 1.25),
        segments: [_seg(1, 1234.5)],
        english: english,
      );
      final text = _pdfText(bytes);
      expect(text, contains('6000.25 mm'));
      expect(text, contains('1.25 mm'));
      expect(text, contains('6.02'));
      expect(text, contains('4764.5 mm'));
    }
  });


  test('nazwa projektu „Łącznik żółć”: PDF powstaje z osadzoną czcionką',
      () async {
    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: _project('Łącznik żółć'),
      segments: [_seg(1, 3293), _seg(2, 2500), _seg(3, 1200)],
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final raw = latin1.decode(bytes);
    expect(raw, startsWith('%PDF-'));
    // Osadzona czcionka TrueType (Roboto), nie wbudowana Helvetica.
    expect(raw, contains('/FontFile2'));
    expect(raw, isNot(contains('/Helvetica')));

    final text = _pdfText(bytes);
    expect(text, contains('Łącznik żółć'));
    expect(text, contains('LISTA SEGMENTÓW'));
    expect(text, contains('Materiał'));
  });

  test('sztangi i tabela segmentów pokazują etykiety S01…', () async {
    // 6000 mm, rzaz 3: sztanga 1 = S01 3293 + S02 2500 (zostaje 201 mm),
    // sztanga 2 = S03 1200 (zostaje 4797 mm).
    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: _project('Linia DN100'),
      segments: [
        _seg(1, 3293, isoExpr: '3000+525-80'),
        _seg(2, 2500),
        _seg(3, 1200),
      ],
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final text = _pdfText(bytes);
    expect(text, contains('S01: 3293 + S02: 2500'));
    expect(text, contains('S03: 1200'));
    expect(text, contains('201 mm'));
    expect(text, contains('4797 mm'));
    // Tabela segmentów: etykieta, wyrażenie ISO i numer sztangi.
    expect(text, contains('S01 114.3×6.02 3000+525-80'));
    expect(text, isNot(contains('UWAGA')));
  });

  test('v22: nagłówek z linią / ISO / rewizją / klientem, oznaczenia obok S01',
      () async {
    final project = Project(
      id: 'p1',
      name: 'Linia DN100',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 3,
      gapMm: 0,
      createdAt: 0,
      updatedAt: 0,
      lineNo: 'DN100-CWS-1234',
      isoNo: 'ISO-7',
      isoRev: 'B',
      client: 'Orlen',
      spec: 'A1B',
    );
    Segment marked(int seq, double cut, String? label) {
      final s = _seg(seq, cut);
      return Segment(
        id: s.id,
        projectId: s.projectId,
        seqNo: s.seqNo,
        diameterMm: s.diameterMm,
        wallThicknessMm: s.wallThicknessMm,
        startKind: s.startKind,
        startLibraryId: s.startLibraryId,
        startValueMm: s.startValueMm,
        endKind: s.endKind,
        endLibraryId: s.endLibraryId,
        endValueMm: s.endValueMm,
        isoRef: s.isoRef,
        isoExpr: s.isoExpr,
        isoMm: s.isoMm,
        cutMm: s.cutMm,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        label: label,
      );
    }

    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: project,
      segments: [
        marked(1, 3293, 'SP02-03'),
        marked(2, 2500, null),
        marked(3, 1200, 'SP02-05'),
      ],
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final text = _pdfText(bytes);
    expect(text,
        contains('Linia: DN100-CWS-1234 · ISO: ISO-7 rew. B · Klient: Orlen · '
            'Klasa: A1B'));
    expect(text, contains('S01 SP02-03: 3293 + S02: 2500'));
    expect(text, contains('S03 SP02-05: 1200'));
    // Segment table: mark next to S01, then the size.
    expect(text, contains('S01 SP02-03 114.3×6.02'));
  });

  test('cięcie dłuższe od sztangi: części (1/2), (2/2) i ostrzeżenie', () async {
    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: _project('Linia DN100'),
      segments: [_seg(1, 7000), _seg(2, 4000)],
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final text = _pdfText(bytes);
    expect(text, contains('S01 (1/2): 6000'));
    expect(text, contains('S02: 4000 + S01 (2/2): 1000'));
    expect(
      text,
      contains('UWAGA: S01: odcinek 7000 mm dłuższy niż sztanga 6000 mm — '
          'dzielony na 2 części: 6000 + 1000 mm; dodatkowa spoina łącząca '
          '(gap projektu 0 mm — nic nie odjęto).'),
    );
  });

  test('gap projektu odjęty od podzielonego odcinka; tabela wytopów', () async {
    final p = _project('Linia DN100');
    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: Project(
        id: p.id,
        name: p.name,
        materialGroup: p.materialGroup,
        diameterMm: p.diameterMm,
        wallThicknessMm: p.wallThicknessMm,
        currentDiameterMm: p.currentDiameterMm,
        stockLengthMm: 6000,
        sawKerfMm: 3,
        gapMm: 3,
        createdAt: 0,
        updatedAt: 0,
      ),
      segments: [_seg(1, 7000), _seg(2, 1234.5)],
      heatRows: const [
        HeatReportRow(
            segments: 'S01', place: 'Rura Ø114.3 × 6.02', heats: 'A12345'),
      ],
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final text = _pdfText(bytes);
    expect(text, contains('S01 (2/2): 997'));
    expect(text, contains('6000 + 997 mm (odjęto gap 3 mm'));
    // Jedna reguła zaokrąglenia: 1234.5 na sztandze i w tabeli segmentów.
    expect(text, contains('S02: 1234.5'));
    expect(text, contains('1234.5 1234.5'));
    expect(text, contains('NUMERY WYTOPÓW'));
    expect(text, contains('S01 Rura Ø114.3 × 6.02 A12345'));
  });

  test('wersja EN', () async {
    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: _project('Line 7'),
      segments: [_seg(1, 7000)],
      english: true,
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final text = _pdfText(bytes);
    expect(text, contains('SEGMENT LIST'));
    expect(text, contains('WARNING: S01: piece 7000 mm is longer'));
    expect(text, isNot(contains('Sztanga')));
  });

  test('wydruk czarno-biały: ciemny tekst, cienkie ramki, bez wypełnień',
      () async {
    final bytes = await PdfExportService.buildCutListPdf(
      theme: await _oneFontTheme(),
      project: _project('Łącznik żółć'),
      segments: [_seg(1, 7000), _seg(2, 4000), _seg(3, 1200)],
      generatedAt: DateTime(2026, 9, 24, 13, 5),
    );
    final contents = _contentStreams(bytes);
    expect(contents, isNotEmpty);
    final number = r'(-?\d*\.?\d+)';
    for (final c in contents) {
      // Hex/literal strings could contain letters that look like operators.
      final ops = c
          .replaceAll(RegExp(r'<[0-9A-Fa-f\s]*>'), ' ')
          .replaceAll(RegExp(r'\([^)]*\)'), ' ');

      // Kolor wypełnienia (tekst) — wyłącznie ciemny tusz.
      for (final m
          in RegExp('$number\\s+$number\\s+$number\\s+rg\\b').allMatches(ops)) {
        final l = _luminance(double.parse(m.group(1)!),
            double.parse(m.group(2)!), double.parse(m.group(3)!));
        expect(l, lessThanOrEqualTo(0.35),
            reason: 'jasny kolor tekstu/wypełnienia: ${m.group(0)}');
      }
      // Kolor linii — widoczny na laserówce mono.
      for (final m
          in RegExp('$number\\s+$number\\s+$number\\s+RG\\b').allMatches(ops)) {
        final l = _luminance(double.parse(m.group(1)!),
            double.parse(m.group(2)!), double.parse(m.group(3)!));
        expect(l, lessThanOrEqualTo(0.6),
            reason: 'za jasna ramka: ${m.group(0)}');
      }
      // Żadnych wypełnionych prostokątów/ścieżek (toner).
      expect(RegExp(r'(^|\s)(f\*?|B\*?|b\*?)(?=\s|$)').hasMatch(ops), isFalse,
          reason: 'wypełnienie tła w treści strony');
    }
  });

  test('produkcyjny motyw ma osobny krój pogrubiony (Roboto-Bold)', () async {
    final theme = await PdfExportService.loadTheme();
    final style = theme.defaultTextStyle;
    expect(style.fontBold, isNotNull);
    expect(identical(style.fontBold, style.fontNormal), isFalse,
        reason: 'pogrubienie nie może być tym samym plikiem co zwykły krój');
    expect(style.fontBold!.fontName, contains('Bold'));
  });
}
