/// Data export for the weld journal — CSV (spreadsheet) and PDF (paper).
///
/// The weld journal is the document a welder puts on the table at a quality
/// audit (ISO 3834-2 §14–15, ASME B31.3 §341/§344, EN 13480-5): which joint,
/// who welded root and cap, with what procedure and filler, how it was
/// examined, repaired, heat treated and accepted.
///
/// The file is deliberately split in two halves:
///   * the top half is PURE Dart — the [WeldJournalRecord] model, CSV
///     serialisation and the small summary helpers. No I/O, no plugins, no
///     locale globals, so it is fully covered by
///     `test/services/weld_journal_export_test.dart`;
///   * the bottom half ([WeldJournalExport]) renders the PDF — with the fonts
///     passed in, so `test/services/weld_journal_pdf_render_test.dart` lays
///     out real pages — and does the platform work: temp file, share sheet.
///
/// Nothing here converts values. Lengths stay in millimetres exactly as the
/// welder typed them (the app's internal base unit) — an export that quietly
/// rewrites cell content cannot be reconciled against the app screen during
/// an audit.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/weld_journal/weld_entry.dart';
import '../domain/weld_journal/weld_filter.dart';
import '../domain/weld_journal/weld_history.dart';
import '../domain/weld_journal/weld_journal_settings.dart';
import '../domain/weld_journal/weld_ndt.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURE HALF — model, CSV, summaries. Keep free of I/O so tests stay honest.
// ═══════════════════════════════════════════════════════════════════════════

/// One immutable journal row, decoupled from the domain `WeldEntry`.
///
/// The mapping ([weldJournalRecordOf]) is an explicit constructor call, not
/// a `Map` round-trip, so the compiler — not a runtime string lookup —
/// catches a field that is added to the journal and forgotten in the export.
///
/// The internal ids (uuid, project id, coupon id) are intentionally NOT part
/// of the export: they mean nothing to an inspector and only widen the sheet.
class WeldJournalRecord {
  final String weldNo;
  final String projectName;
  final String pipeName;
  final String material;

  /// Outside diameter in millimetres, as typed ("60.3" or "60,3").
  final String od;

  /// Wall thickness in millimetres, as typed.
  final String t;

  final String method;
  final String welder;

  /// ISO date `YYYY-MM-DD` as stored by the editor.
  final String date;

  final String notes;

  /// `OK` / `NOK` / `PENDING`.
  final String status;

  /// `ORBITAL` / `AUTO` / `MANUAL`.
  final String weldType;

  final String fitter;
  final String heatNo1;
  final String heatNo2;
  final String couponRef;
  final String exam;
  final String wpsRef;

  // ---- v20
  final String isoDrawing;
  final String isoRev;
  final String spool;
  final String testPackage;
  final String jointType;
  final String shopField;
  final String position;
  final String rootWelder;
  final String capWelder;
  final String fillerClass;
  final String fillerBatch;
  final String preheatC;
  final String interpassC;
  final String heatInput;

  // ---- v28 — ograniczenia z próby ISO 9606-1, surowe kody jak w bazie
  // (pusty = nie podano). Czytelną postać robią CSV ([weldRootBackingLabel],
  // kolumny na końcu) i PDF ([weldJournalIsoDetails]).

  /// [WeldRootBacking] code (`nb`, `mb`, `bs`, `gb`, `ci`, `fb`).
  final String rootBacking;

  /// [WeldMetalTransfer] code (`dip` / `other`), MIG/MAG only.
  final String metalTransfer;

  /// [WeldProductKind] code (`T` pipe / `P` plate).
  final String productForm;

  final Map<NdtMethod, WeldNdt> ndt;

  /// One summary line per repair, R1 first (`WeldRepair.summary()`).
  final List<String> repairs;
  final bool? pwhtRequired;
  final String pwhtChart;
  final String hardness;
  final String inspector;
  final String inspectedAt;

  /// Soft-deleted entry (only exported from the "deleted" view).
  final bool deleted;

  /// QC remarks (v25): current WPS / qualification / document-consistency
  /// warnings and every "saved despite warnings" decision from the history.
  /// An inspector reading the data book must see that a weld was saved
  /// outside the WPS.
  final List<String> qcRemarks;

  /// Change history lines, oldest first (PDF appendix), e.g.
  /// `2026-09-24 14:05 · JK-12 · Edycja · Status: PENDING → OK`.
  final List<String> history;

  const WeldJournalRecord({
    required this.weldNo,
    this.projectName = '',
    this.pipeName = '',
    this.material = '',
    this.od = '',
    this.t = '',
    this.method = '',
    this.welder = '',
    this.date = '',
    this.notes = '',
    this.status = '',
    this.weldType = '',
    this.fitter = '',
    this.heatNo1 = '',
    this.heatNo2 = '',
    this.couponRef = '',
    this.exam = '',
    this.wpsRef = '',
    this.isoDrawing = '',
    this.isoRev = '',
    this.spool = '',
    this.testPackage = '',
    this.jointType = '',
    this.shopField = '',
    this.position = '',
    this.rootWelder = '',
    this.capWelder = '',
    this.fillerClass = '',
    this.fillerBatch = '',
    this.preheatC = '',
    this.interpassC = '',
    this.heatInput = '',
    this.rootBacking = '',
    this.metalTransfer = '',
    this.productForm = '',
    this.ndt = const {},
    this.repairs = const [],
    this.pwhtRequired,
    this.pwhtChart = '',
    this.hardness = '',
    this.inspector = '',
    this.inspectedAt = '',
    this.deleted = false,
    this.qcRemarks = const [],
    this.history = const [],
  });

  WeldNdt ndtOf(NdtMethod m) => ndt[m] ?? const WeldNdt();
}

/// Immutable export snapshot of [e], written out field by field.
/// [qcRemarks] and [history] come from the screen (compliance check and the
/// history table) — see [weldQcRemarks] and [weldHistoryLines].
WeldJournalRecord weldJournalRecordOf(
  WeldEntry e, {
  List<String> qcRemarks = const [],
  List<String> history = const [],
}) =>
    WeldJournalRecord(
      weldNo: e.weldNo,
      projectName: e.projectName,
      pipeName: e.pipeName,
      material: e.material,
      od: e.od,
      t: e.t,
      method: e.method,
      welder: e.welder,
      date: e.date,
      notes: e.notes,
      status: e.status,
      weldType: e.weldType,
      fitter: e.fitter,
      heatNo1: e.heatNo1,
      heatNo2: e.heatNo2,
      couponRef: e.couponRef,
      exam: e.exam,
      wpsRef: e.wpsRef,
      isoDrawing: e.isoDrawing,
      isoRev: e.isoRev,
      spool: e.spool,
      testPackage: e.testPackage,
      jointType: e.jointType,
      shopField: e.shopField,
      position: e.position,
      rootWelder: e.rootWelder,
      capWelder: e.capWelder,
      fillerClass: e.fillerClass,
      fillerBatch: e.fillerBatch,
      preheatC: e.preheatC,
      interpassC: e.interpassC,
      heatInput: e.heatInput,
      rootBacking: e.rootBacking,
      metalTransfer: e.metalTransfer,
      productForm: e.productForm,
      ndt: compactNdt(e.ndt),
      repairs: [for (final r in e.repairs) r.summary()],
      pwhtRequired: e.pwhtRequired,
      pwhtChart: e.pwhtChart,
      hardness: e.hardness,
      inspector: e.inspector,
      inspectedAt: e.inspectedAt,
      deleted: e.isDeleted,
      qcRemarks: qcRemarks,
      history: history,
    );

/// History of one weld as export lines, oldest first.
List<String> weldHistoryLines(Iterable<WeldHistoryEntry> entries,
    {required bool en}) {
  final sorted = [...entries]..sort((a, b) => a.at.compareTo(b.at));
  return [
    for (final h in sorted)
      [
        formatHistoryTime(h.at),
        if (h.byStamp.isNotEmpty) h.byStamp,
        weldHistoryActionLabel(h.action, en: en),
        if (h.field.isNotEmpty && h.field != 'repair')
          '${weldFieldLabel(h.field, en: en)}: '
              '${weldFieldDisplayValue(h.field, h.oldValue, en: en)} → '
              '${weldFieldDisplayValue(h.field, h.newValue, en: en)}'
        else if (h.newValue.isNotEmpty || h.oldValue.isNotEmpty)
          (h.newValue.isNotEmpty ? h.newValue : h.oldValue)
              .replaceAll('\n', ' '),
      ].join(' · '),
  ];
}

/// QC remarks of a weld: [current] warnings (compliance / consistency, as
/// shown on the card) plus every `CHECK` ("saved despite warnings") entry of
/// its history, deduplicated, in that order.
List<String> weldQcRemarks({
  Iterable<String> current = const [],
  Iterable<WeldHistoryEntry> history = const [],
}) {
  final out = <String>[];
  final seen = <String>{};
  void add(String s) {
    final t = s.trim();
    if (t.isNotEmpty && seen.add(t)) out.add(t);
  }

  for (final c in current) {
    add(c);
  }
  final checks = history
      .where((h) => h.action == WeldHistoryAction.check)
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  for (final h in checks) {
    add('${formatHistoryTime(h.at)}'
        '${h.byStamp.isEmpty ? '' : ' ${h.byStamp}'}: '
        '${h.newValue.replaceAll('\n', ' ')}');
  }
  return out;
}

extension WeldEntryExport on WeldEntry {
  WeldJournalRecord toExportRecord() => weldJournalRecordOf(this);
}

/// Rows handed to the exporter for [filter] — exactly `filterWeldEntries`,
/// mapped to export records, order preserved.
List<WeldJournalRecord> weldJournalExportRecords(
  List<WeldEntry> entries,
  WeldJournalFilter filter, {
  Map<String, List<String>> qcRemarks = const {},
  Map<String, List<String>> history = const {},
}) =>
    filterWeldEntries(entries, filter)
        .map((e) => weldJournalRecordOf(e,
            qcRemarks: qcRemarks[e.id] ?? const [],
            history: history[e.id] ?? const []))
        .toList();

/// Field separator. Semicolon, not comma: Polish Windows Excel opens a
/// comma-separated file as one squashed column, and this file is printed and
/// mailed by Polish welders far more often than it is parsed by a script.
const String kWeldJournalCsvSeparator = ';';

/// RFC 4180 record terminator. Excel and LibreOffice both accept bare `\n`,
/// but Notepad on older Windows does not, and the journal gets opened there.
const String kWeldJournalCsvEol = '\r\n';

/// UTF-8 byte-order mark. Without it Excel decodes the file as the system
/// code page and every Polish diacritic in a welder stamp or a note turns
/// into mojibake ("Å»Ã³Å‚Ä‡") — which makes the document useless as evidence.
const String kUtf8Bom = '\u{FEFF}';

class _CsvColumn {
  /// Bilingual header. PL first (the shop floor), EN after the slash, so the
  /// same file works when the spool travels to a foreign site inspector.
  final String header;
  final String Function(WeldJournalRecord r) read;
  const _CsvColumn(this.header, this.read);
}

String _yesNo(bool? v) => v == null ? '' : (v ? 'TAK / YES' : 'NIE / NO');

/// v28: prowadzenie grani tak, jak na certyfikacie i w edytorze (`ss nb`,
/// `ss mb`, `bs`, `ss gb`, `ci`, `ss fb`). Kod spoza listy (ręczna edycja
/// bazy) wychodzi dokładnie tak, jak jest zapisany — eksport nie przepisuje
/// danych po cichu. `''` = nie podano.
String weldRootBackingLabel(String code) {
  final c = code.trim();
  return WeldRootBacking.values.contains(c) ? WeldRootBacking.label(c) : c;
}

/// CSV value of the metal transfer, bilingual like `TAK / YES`.
String _csvMetalTransfer(String code) => switch (code.trim()) {
      WeldMetalTransfer.dip => 'zwarciowe / dip',
      WeldMetalTransfer.other => 'inne / other',
      final c => c,
    };

/// CSV value of the product form, bilingual like `TAK / YES`.
String _csvProductForm(String code) => switch (code.trim()) {
      WeldProductKind.pipe => 'rura (T) / pipe (T)',
      WeldProductKind.plate => 'blacha (P) / plate (P)',
      final c => c,
    };

/// v28 line of the PDF "Złącze / Joint" cell: product form, root / backing
/// and — MIG/MAG only — metal transfer, as the compact ISO 9606-1 tokens an
/// inspector knows from the welder's certificate, e.g. `T · ss nb · dip`.
///
/// Only what was given is printed; `''` when none of the three is set, so a
/// weld from before v28 prints exactly as it did.
String weldJournalIsoDetails(WeldJournalRecord r) => [
      r.productForm.trim(),
      weldRootBackingLabel(r.rootBacking),
      switch (r.metalTransfer.trim()) {
        WeldMetalTransfer.other => 'inne/other',
        final c => c,
      },
    ].where((s) => s.isNotEmpty).join(' · ');

/// Column definition. The first 18 columns are the pre-v20 export in its
/// original order — spreadsheets built on an older export read them by
/// position, so they never move. Everything added later is appended at the
/// end (v20, v25, v28) — never inserted in between.
final List<_CsvColumn> _csvColumns = <_CsvColumn>[
  _CsvColumn('Nr spoiny / Weld no.', (r) => r.weldNo),
  _CsvColumn('Projekt / Project', (r) => r.projectName),
  _CsvColumn('Rura / Pipe', (r) => r.pipeName),
  _CsvColumn('Materiał / Material', (r) => r.material),
  _CsvColumn('OD (mm)', (r) => r.od),
  _CsvColumn('t (mm)', (r) => r.t),
  _CsvColumn('Metoda / Method', (r) => r.method),
  _CsvColumn('Spawacz / Welder', (r) => r.welder),
  _CsvColumn('Data / Date', (r) => r.date),
  _CsvColumn('Uwagi / Notes', (r) => r.notes),
  _CsvColumn('Status', (r) => r.status),
  _CsvColumn('Typ spoiny / Weld type', (r) => r.weldType),
  _CsvColumn('Monter / Fitter', (r) => r.fitter),
  _CsvColumn('Nr wytopu 1 / Heat no. 1', (r) => r.heatNo1),
  _CsvColumn('Nr wytopu 2 / Heat no. 2', (r) => r.heatNo2),
  _CsvColumn('Kupon próbny / Test coupon', (r) => r.couponRef),
  _CsvColumn('Wynik badania / Examination', (r) => r.exam),
  _CsvColumn('Nr WPS / WPS no.', (r) => r.wpsRef),
  // ---- v20
  _CsvColumn('Nr ISO / ISO no.', (r) => r.isoDrawing),
  _CsvColumn('Rewizja / Rev.', (r) => r.isoRev),
  _CsvColumn('Spool', (r) => r.spool),
  _CsvColumn('Pakiet testowy / Test package', (r) => r.testPackage),
  _CsvColumn('Typ złącza / Joint type', (r) => r.jointType),
  _CsvColumn('Warsztat/montaż / Shop/field', (r) => r.shopField),
  _CsvColumn('Pozycja / Position', (r) => r.position),
  _CsvColumn('Stempel graniówki / Root stamp', (r) => r.rootWelder),
  _CsvColumn('Stempel lica / Cap stamp', (r) => r.capWelder),
  _CsvColumn('Spoiwo klasyfikacja / Filler class.', (r) => r.fillerClass),
  _CsvColumn('Spoiwo partia / Filler batch', (r) => r.fillerBatch),
  _CsvColumn('Podgrzanie °C / Preheat °C', (r) => r.preheatC),
  _CsvColumn('Międzyściegowa °C / Interpass °C', (r) => r.interpassC),
  _CsvColumn('Energia liniowa kJ/mm / Heat input kJ/mm', (r) => r.heatInput),
  for (final m in NdtMethod.values) ...[
    _CsvColumn(
        '${m.code} zakres / scope', (r) => NdtScope.tag(r.ndtOf(m).scope)),
    _CsvColumn('${m.code} wynik / result', (r) => r.ndtOf(m).result),
    _CsvColumn('${m.code} raport / report', (r) => r.ndtOf(m).reportNo),
    _CsvColumn('${m.code} data / date', (r) => r.ndtOf(m).date),
  ],
  _CsvColumn('Naprawy / Repairs',
      (r) => r.repairs.isEmpty ? '' : '${r.repairs.length}'),
  _CsvColumn('Historia napraw / Repair log', (r) => r.repairs.join(' | ')),
  _CsvColumn('PWHT wymagane / required', (r) => _yesNo(r.pwhtRequired)),
  _CsvColumn('PWHT wykres / chart', (r) => r.pwhtChart),
  _CsvColumn('Twardość / Hardness', (r) => r.hardness),
  _CsvColumn('Odbiór — inspektor / Accepted by', (r) => r.inspector),
  _CsvColumn('Odbiór — data / Acceptance date', (r) => r.inspectedAt),
  _CsvColumn('Usunięta / Deleted', (r) => r.deleted ? 'TAK / YES' : ''),
  // ---- v25
  _CsvColumn('Uwagi QC / QC remarks', (r) => r.qcRemarks.join(' | ')),
  // ---- v28 — ograniczenia z próby ISO 9606-1; puste = nie podano.
  _CsvColumn('Prowadzenie grani / Root backing',
      (r) => weldRootBackingLabel(r.rootBacking)),
  _CsvColumn('Przenoszenie metalu / Metal transfer',
      (r) => _csvMetalTransfer(r.metalTransfer)),
  _CsvColumn('Wyrób / Product form', (r) => _csvProductForm(r.productForm)),
];

/// Header labels in export order. Exposed so a test can pin the order down —
/// silently reordering columns would break every spreadsheet the QA
/// department already built on top of an earlier export.
List<String> get weldJournalCsvHeaders =>
    _csvColumns.map((c) => c.header).toList(growable: false);

/// Escapes one field per RFC 4180 §2.6–2.7.
///
/// A field is quoted only when it has to be (separator, double quote, CR or
/// LF inside), and an embedded double quote is doubled. Welders paste real
/// text into "Uwagi" — `grań OK; lico do szlifowania` or `spoina "na zimno"`
/// — and an unescaped semicolon there would shift every later column of that
/// row by one, silently attributing the wrong WPS to the wrong weld.
String escapeCsvField(String raw) {
  final needsQuotes = raw.contains(kWeldJournalCsvSeparator) ||
      raw.contains('"') ||
      raw.contains('\n') ||
      raw.contains('\r');
  if (!needsQuotes) return raw;
  return '"${raw.replaceAll('"', '""')}"';
}

/// Builds the whole CSV document: BOM, header row, then one row per record
/// in the order given (the caller decides the order — the screen passes the
/// list exactly as it is displayed, filter included).
///
/// An empty [records] list still yields BOM + header, so the file opens as a
/// valid — merely empty — table instead of a zero-byte attachment that looks
/// like a failed export.
String buildWeldJournalCsv(List<WeldJournalRecord> records) {
  final buf = StringBuffer()..write(kUtf8Bom);
  buf.write(_csvColumns
      .map((c) => escapeCsvField(c.header))
      .join(kWeldJournalCsvSeparator));
  buf.write(kWeldJournalCsvEol);
  for (final r in records) {
    buf.write(_csvColumns
        .map((c) => escapeCsvField(c.read(r)))
        .join(kWeldJournalCsvSeparator));
    buf.write(kWeldJournalCsvEol);
  }
  return buf.toString();
}

final RegExp _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Date span covered by [records], for the PDF header ("this document covers
/// welds from … to …" is the first thing an inspector looks for).
///
/// Only well-formed `YYYY-MM-DD` values count — rows written before the
/// editor validated dates may hold a half-typed "2026-0", which must not
/// become the reported range start. ISO dates sort lexicographically.
/// Returns `''` when no entry carries a usable date, and a single date when
/// every weld was made the same day.
String weldJournalDateRange(List<WeldJournalRecord> records) {
  final dates = records
      .map((r) => r.date.trim())
      .where(_isoDatePattern.hasMatch)
      .toList()
    ..sort();
  if (dates.isEmpty) return '';
  if (dates.first == dates.last) return dates.first;
  return '${dates.first} - ${dates.last}';
}

/// Distinct welder stamps in the export (welder, root, cap), in first-seen
/// order.
///
/// A shift journal usually carries one stamp, but a foreman exporting a whole
/// project gets several — the PDF header must name all of them rather than
/// implying a single welder made every joint.
String weldJournalWelders(List<WeldJournalRecord> records) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in records) {
    for (final raw in [r.welder, r.rootWelder, r.capWelder]) {
      final w = raw.trim();
      if (w.isEmpty || !seen.add(w)) continue;
      out.add(w);
    }
  }
  return out.join(', ');
}

/// Status tally for the PDF summary block. Single pass; `other` catches rows
/// with a status the app no longer writes (legacy DB values) so the numbers
/// always add up to `total` and nothing disappears from the report.
({int total, int ok, int nok, int pending, int other}) weldJournalTally(
    List<WeldJournalRecord> records) {
  var ok = 0, nok = 0, pending = 0, other = 0;
  for (final r in records) {
    switch (r.status) {
      case 'OK':
        ok++;
        break;
      case 'NOK':
        nok++;
        break;
      case 'PENDING':
        pending++;
        break;
      default:
        other++;
    }
  }
  return (
    total: records.length,
    ok: ok,
    nok: nok,
    pending: pending,
    other: other,
  );
}

/// NDT figures for the PDF summary block: welds with an RT or UT result,
/// and welds with at least one repair.
({int total, int volumetric, int repaired}) weldJournalNdtSummary(
    List<WeldJournalRecord> records) {
  var volumetric = 0, repaired = 0;
  for (final r in records) {
    if (r.ndtOf(NdtMethod.rt).hasResult || r.ndtOf(NdtMethod.ut).hasResult) {
      volumetric++;
    }
    if (r.repairs.isNotEmpty) repaired++;
  }
  return (total: records.length, volumetric: volumetric, repaired: repaired);
}

/// Human-readable, collision-safe file name, e.g.
/// `Dziennik_spoin_NOK_2026-08-29.csv`.
///
/// Named by date (not by epoch millis like the cut-list export) because the
/// recipient sees this string in the mail attachment list — `Dziennik_spoin_
/// 1756412345678.csv` tells an inspector nothing. Re-exporting the same day
/// overwrites the temp file, which is what we want.
String weldJournalFileName({
  required String extension,
  required DateTime generatedAt,
  String? filterLabel,
}) {
  final y = generatedAt.year.toString().padLeft(4, '0');
  final m = generatedAt.month.toString().padLeft(2, '0');
  final d = generatedAt.day.toString().padLeft(2, '0');
  final raw = (filterLabel ?? '').trim();
  final filter = (raw.isEmpty || raw == 'ALL')
      ? ''
      : '_${raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
  return 'Dziennik_spoin${filter}_$y-$m-$d.$extension';
}

/// Project block of the PDF header, from the journal settings of the one
/// project the export covers.
class WeldJournalPdfHeader {
  final String company;
  final String client;
  final String projectTitle;
  final String documentNo;
  final String revision;

  const WeldJournalPdfHeader({
    this.company = '',
    this.client = '',
    this.projectTitle = '',
    this.documentNo = '',
    this.revision = '',
  });

  factory WeldJournalPdfHeader.fromSettings(WeldJournalProjectSettings? s) =>
      s == null
          ? const WeldJournalPdfHeader()
          : WeldJournalPdfHeader(
              company: s.company.trim(),
              client: s.client.trim(),
              projectTitle: s.projectTitle.trim().isEmpty
                  ? s.projectName.trim()
                  : s.projectTitle.trim(),
              documentNo: s.documentNo.trim(),
              revision: s.revision.trim(),
            );

  bool get isEmpty =>
      company.isEmpty &&
      client.isEmpty &&
      projectTitle.isEmpty &&
      documentNo.isEmpty &&
      revision.isEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM HALF — PDF rendering + share sheet.
// ═══════════════════════════════════════════════════════════════════════════

// Print-safe ink. Lesson already paid for in pdf_export_service.dart: the
// screen palette (#E8ECF0 text on a dark card) is invisible on white paper,
// and the journal is a document that gets PRINTED and signed. Everything
// here is dark enough to survive a worn mono laser in a workshop.
final PdfColor _kAccent = PdfColor.fromHex('#F5A623');
final PdfColor _kInk = PdfColor.fromHex('#1A1D26');
final PdfColor _kInkMuted = PdfColor.fromHex('#5A6478');
final PdfColor _kRule = PdfColor.fromHex('#B9C0CC');
final PdfColor _kHeadFill = PdfColor.fromHex('#EDEFF3');
final PdfColor _kOkInk = PdfColor.fromHex('#1E7A3C');
final PdfColor _kNokInk = PdfColor.fromHex('#B3261E');
final PdfColor _kPendingInk = PdfColor.fromHex('#8A4A00');

class WeldJournalExport {
  const WeldJournalExport._();

  /// Writes the CSV to a temp file and opens the OS share sheet.
  ///
  /// Bytes are written explicitly through [utf8] rather than
  /// `writeAsString` so the encoding of the file is decided here, next to the
  /// BOM that promises it, and cannot be changed by a platform default.
  static Future<void> shareCsv({
    required List<WeldJournalRecord> records,
    String? filterLabel,
    DateTime? generatedAt,
    void Function()? validateOwner,
  }) async {
    validateOwner?.call();
    final now = generatedAt ?? DateTime.now();
    final csv = buildWeldJournalCsv(records);
    final name = weldJournalFileName(
      extension: 'csv',
      generatedAt: now,
      filterLabel: filterLabel,
    );
    final dir = await getTemporaryDirectory();
    validateOwner?.call();
    final exportDir = await Directory(dir.path).createTemp('fwp_journal_');
    validateOwner?.call();
    final file = File('${exportDir.path}/$name');
    await file.writeAsBytes(utf8.encode(csv), flush: true);
    validateOwner?.call();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: _subject(records, filterLabel),
    );
  }

  /// Renders the journal and opens the share sheet.
  ///
  /// [filterLabel] goes into the file name, [filterDescription] (the full
  /// human-readable filter) into the page header. [welderFallback] is the
  /// identity stamp of the phone owner, only used when no entry carries a
  /// welder.
  static Future<void> sharePdf({
    required List<WeldJournalRecord> records,
    String? filterLabel,
    String filterDescription = '',
    WeldJournalPdfHeader header = const WeldJournalPdfHeader(),
    String welderFallback = '',
    DateTime? generatedAt,
    void Function()? validateOwner,
  }) async {
    validateOwner?.call();
    final now = generatedAt ?? DateTime.now();

    // Bundled Roboto covers Latin-2, so Polish text (ą/ć/ę/ł/ń/ó/ś/ź/ż) in
    // notes, welder names and project names renders. The `pdf` package's
    // built-in Helvetica is Latin-1 only and drops those glyphs — same fix
    // iso_pdf_export.dart already carries.
    final baseFont = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldFont = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final bytes = await renderPdfBytes(
      records: records,
      fontBytes: Uint8List.sublistView(baseFont),
      boldFontBytes: Uint8List.sublistView(boldFont),
      header: header,
      filterDescription: filterDescription,
      welderFallback: welderFallback,
      generatedAt: now,
    );
    final name = weldJournalFileName(
      extension: 'pdf',
      generatedAt: now,
      filterLabel: filterLabel,
    );
    final dir = await getTemporaryDirectory();
    validateOwner?.call();
    final exportDir = await Directory(dir.path).createTemp('fwp_journal_');
    validateOwner?.call();
    final file = File('${exportDir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    // Same guard as iso_pdf_export: a truncated write (full disk) would
    // otherwise be shared as a corrupt attachment and only discovered by the
    // inspector who cannot open it.
    if (!await file.exists() || (await file.length()) < 100) {
      throw StateError(
        'PDF zapisany niepoprawnie — sprawdź miejsce na dysku (${dir.path}).',
      );
    }
    validateOwner?.call();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: _subject(records, filterLabel),
    );
  }

  /// Renders the journal PDF to bytes in a background isolate
  /// (`Isolate.run`), not on the UI thread.
  ///
  /// Layout and `doc.save()` for a 400-weld journal take ~3 s on desktop JIT
  /// and 1–3 s of frozen screen on a weak Android phone — no spinner, no
  /// back gesture. Everything handed to the isolate is plain data: the
  /// immutable [WeldJournalRecord]s, the header, the date and the raw TTF
  /// bytes (a `pw.Font` is built on the other side). Only the finished
  /// `Uint8List` comes back.
  static Future<Uint8List> renderPdfBytes({
    required List<WeldJournalRecord> records,
    required Uint8List fontBytes,
    Uint8List? boldFontBytes,
    WeldJournalPdfHeader header = const WeldJournalPdfHeader(),
    String filterDescription = '',
    String welderFallback = '',
    required DateTime generatedAt,
  }) {
    final rows = List<WeldJournalRecord>.unmodifiable(records);
    return Isolate.run(() async {
      final doc = await buildPdfDocument(
        records: rows,
        font: pw.Font.ttf(ByteData.sublistView(fontBytes)),
        boldFont: boldFontBytes == null
            ? null
            : pw.Font.ttf(ByteData.sublistView(boldFontBytes)),
        header: header,
        filterDescription: filterDescription,
        welderFallback: welderFallback,
        generatedAt: generatedAt,
      );
      return doc.save();
    }, debugName: 'weld-journal-pdf');
  }

  /// Lays the journal out as landscape A4 pages. No platform calls — the
  /// fonts are passed in — so a test can render real pages.
  ///
  /// Two tables instead of one 60-column monster: identification and
  /// execution first, then — from a new page — NDT per method, repairs,
  /// PWHT and acceptance, keyed by the same weld number. Then the legend and
  /// the signature block (welder / QC / inspector / TPI, with dates).
  static Future<pw.Document> buildPdfDocument({
    required List<WeldJournalRecord> records,
    required pw.Font font,
    pw.Font? boldFont,
    WeldJournalPdfHeader header = const WeldJournalPdfHeader(),
    String filterDescription = '',
    String welderFallback = '',
    required DateTime generatedAt,
  }) async {
    final bold = boldFont ?? font;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: bold,
        italic: font,
        boldItalic: bold,
      ),
    );

    final now = generatedAt;
    final welders = weldJournalWelders(records);
    final range = weldJournalDateRange(records);
    final tally = weldJournalTally(records);
    final ndt = weldJournalNdtSummary(records);
    final stamp = '${_isoDate(now)} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    doc.addPage(pw.MultiPage(
      // Landscape: the traceability fields do not fit across a portrait page
      // at a font size a welder can read in a workshop.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      // A project journal runs to hundreds of welds; the package default of
      // 20 pages would throw TooManyPagesException half way through.
      maxPages: 2000,
      header: (ctx) => _pageHeader(
        header: header,
        welders: welders.isEmpty ? welderFallback : welders,
        range: range,
        filter: filterDescription,
        stamp: stamp,
        page: ctx.pageNumber,
        pages: ctx.pagesCount,
      ),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Fitter Welder Pro  ·  $stamp'
              '${header.documentNo.isEmpty ? '' : '  ·  ${header.documentNo}'}'
              '${header.revision.isEmpty ? '' : ' rev. ${header.revision}'}',
              style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
            ),
            pw.Text(
              'Strona / Page ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 7, color: _kInkMuted),
            ),
          ],
        ),
      ),
      build: (_) => [
        _summaryBlock(tally, ndt),
        pw.SizedBox(height: 8),
        if (records.isEmpty)
          pw.Text(
            'Brak spoin w tym zakresie. / No welds in this selection.',
            style: pw.TextStyle(fontSize: 9, color: _kInkMuted),
          )
        else ...[
          _sectionTitle('1. Identyfikacja i wykonanie / '
              'Identification and execution'),
          _executionTable(records),
          pw.NewPage(),
          _sectionTitle('2. Badania NDT, naprawy, PWHT i odbiór / '
              'NDT, repairs, PWHT and acceptance'),
          _ndtTable(records),
          if (records.any((r) => r.qcRemarks.isNotEmpty)) ...[
            pw.SizedBox(height: 10),
            _sectionTitle('3. Uwagi QC — ostrzeżenia i „zapisano mimo '
                'ostrzeżeń” / QC remarks — warnings and "saved despite '
                'warnings"'),
            _remarksTable(records),
          ],
          if (records.any((r) => r.history.isNotEmpty)) ...[
            pw.NewPage(),
            _sectionTitle('4. Historia zmian (dodatek) / Change history '
                '(appendix)'),
            _historyTable(records),
          ],
        ],
        pw.SizedBox(height: 10),
        _legend(
            isoDetails:
                records.any((r) => weldJournalIsoDetails(r).isNotEmpty)),
        pw.SizedBox(height: 10),
        _signatures(),
      ],
    ));
    return doc;
  }

  static String _subject(List<WeldJournalRecord> records, String? filterLabel) {
    final range = weldJournalDateRange(records);
    final filter =
        (filterLabel == null || filterLabel.isEmpty || filterLabel == 'ALL')
            ? ''
            : ' [$filterLabel]';
    final span = range.isEmpty ? '' : ' — $range';
    return 'Dziennik spoin / Weld journal$filter$span';
  }

  static String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Running page header ───────────────────────────────────────────────────
  static pw.Widget _pageHeader({
    required WeldJournalPdfHeader header,
    required String welders,
    required String range,
    required String filter,
    required String stamp,
    required int page,
    required int pages,
  }) {
    pw.Widget line(String text, {bool strong = false, PdfColor? color}) =>
        pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8.5,
            color: color ?? _kInk,
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        );
    final project = [
      if (header.company.isNotEmpty) 'Firma / Company: ${header.company}',
      if (header.client.isNotEmpty) 'Klient / Client: ${header.client}',
      if (header.projectTitle.isNotEmpty)
        'Projekt / Project: ${header.projectTitle}',
    ].join('     ');
    final doc = [
      if (header.documentNo.isNotEmpty)
        'Nr dok. / Doc. no.: ${header.documentNo}',
      if (header.revision.isNotEmpty) 'Rew. / Rev.: ${header.revision}',
    ].join('   ');
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DZIENNIK SPOIN / WELD JOURNAL',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _kInk,
                  ),
                ),
                pw.SizedBox(height: 2),
                if (project.isNotEmpty) line(project),
                line('Spawacze / Welders: ${welders.isEmpty ? '—' : welders}'
                    '     Zakres dat / Date range: '
                    '${range.isEmpty ? '—' : range}'),
                if (filter.isNotEmpty)
                  // The screen exports what it shows. A filtered printout
                  // must say so — otherwise "NOK only" reads as a complete
                  // journal with a catastrophic reject rate.
                  line('Filtr / Filter: $filter',
                      strong: true, color: _kPendingInk),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            if (doc.isNotEmpty) line(doc, strong: true),
            pw.Text('Strona / Page $page / $pages',
                style: pw.TextStyle(fontSize: 8.5, color: _kInkMuted)),
            pw.Text('Wygenerowano / Generated: $stamp',
                style: pw.TextStyle(fontSize: 7.5, color: _kInkMuted)),
          ]),
        ],
      ),
    );
  }

  // ── Tally block ───────────────────────────────────────────────────────────
  static pw.Widget _summaryBlock(
    ({int total, int ok, int nok, int pending, int other}) t,
    ({int total, int volumetric, int repaired}) n,
  ) {
    final volPct = n.total == 0 ? 0 : (n.volumetric * 100 / n.total);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: _kHeadFill,
        border: pw.Border.all(color: _kRule, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(children: [
        _summaryCell('Spoiny / Welds', '${t.total}', _kInk),
        _summaryCell('OK', '${t.ok}', _kOkInk),
        _summaryCell('NOK', '${t.nok}', _kNokInk),
        _summaryCell('Oczekuje / Pending', '${t.pending}', _kPendingInk),
        if (t.other > 0) _summaryCell('Inne / Other', '${t.other}', _kInkMuted),
        _summaryCell('Zbadane RT/UT / RT/UT examined',
            '${n.volumetric} (${volPct.toStringAsFixed(1)} %)', _kInk),
        _summaryCell('Naprawiane / Repaired', '${n.repaired}', _kInk),
      ]),
    );
  }

  static pw.Widget _summaryCell(String label, String value, PdfColor color) =>
      pw.Expanded(
        child: pw.Column(children: [
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text(label,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 6.5, color: _kInkMuted)),
        ]),
      );

  static pw.Widget _sectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold, color: _kInk)),
      );

  // ── Table 1: identification and execution ─────────────────────────────────
  static pw.Widget _executionTable(List<WeldJournalRecord> records) {
    const headers = <String>[
      'Nr / No.',
      'Data / Date',
      'ISO / rev.',
      'Linia · spool / Line',
      'Złącze / Joint',
      'Materiał · OD×t',
      'Wytop / Heat',
      'Proces · WPS',
      'Spoiwo / Filler',
      'Spawacz: grań / lico\nWelder: root / cap',
      'Monter / Fitter',
      'Podgrz. / Międzyśc. / HI',
      'Kupon / Coupon',
      'Uwagi / Notes',
      'Status',
    ];
    return _table(
      headers: headers,
      widths: const {
        0: pw.FixedColumnWidth(46),
        1: pw.FixedColumnWidth(42),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FixedColumnWidth(44),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(0.9),
        7: pw.FlexColumnWidth(1.2),
        8: pw.FlexColumnWidth(1.0),
        9: pw.FlexColumnWidth(1.0),
        10: pw.FixedColumnWidth(40),
        11: pw.FixedColumnWidth(46),
        12: pw.FlexColumnWidth(0.9),
        13: pw.FlexColumnWidth(1.4),
        14: pw.FixedColumnWidth(38),
      },
      rows: records.map((r) => [
            _cell(r.weldNo, bold: true),
            _cell(r.date),
            _cell(_join(r.isoDrawing, r.isoRev, ' rev. ')),
            _cell(_join(r.pipeName, r.spool, ' · ')),
            _cell([
              [
                r.jointType,
                switch (r.shopField) {
                  'SHOP' => 'W/S',
                  'FIELD' => 'M/F',
                  _ => '',
                },
                r.position,
              ].where((s) => s.isNotEmpty).join(' · '),
              // v28: wyrób · grań · przenoszenie — tylko gdy podane.
              weldJournalIsoDetails(r),
            ].where((s) => s.isNotEmpty).join('\n')),
            _cell(_join(r.material, _join(r.od, r.t, ' x '), ' · ')),
            _cell(_join(r.heatNo1, r.heatNo2, ' / ')),
            _cell([
              _join(r.method, r.weldType, ' · '),
              r.wpsRef,
            ].where((s) => s.isNotEmpty).join('\n')),
            _cell(_join(r.fillerClass, r.fillerBatch, '\n')),
            _cell(_welderCell(r)),
            _cell(r.fitter),
            _cell([r.preheatC, r.interpassC, r.heatInput]
                    .every((s) => s.trim().isEmpty)
                ? ''
                : '${_dash(r.preheatC)} / ${_dash(r.interpassC)} / '
                    '${_dash(r.heatInput)}'),
            _cell(r.couponRef),
            _cell(r.notes),
            _statusCell(r),
          ]),
    );
  }

  // ── Table 2: NDT, repairs, PWHT, acceptance ───────────────────────────────
  static pw.Widget _ndtTable(List<WeldJournalRecord> records) {
    final headers = <String>[
      'Nr / No.',
      for (final m in NdtMethod.values) m.code,
      'Naprawy / Repairs',
      'PWHT · wykres · twardość\nPWHT · chart · hardness',
      'Odbiór / Accepted',
      'Pakiet / Package',
      'Uwagi z badań / Exam remarks',
      'Status',
    ];
    return _table(
      headers: headers,
      widths: const {
        0: pw.FixedColumnWidth(46),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.0),
        4: pw.FlexColumnWidth(1.0),
        5: pw.FlexColumnWidth(1.0),
        6: pw.FlexColumnWidth(1.5),
        7: pw.FlexColumnWidth(0.9),
        8: pw.FlexColumnWidth(0.9),
        9: pw.FlexColumnWidth(0.7),
        10: pw.FlexColumnWidth(1.1),
        11: pw.FixedColumnWidth(38),
      },
      rows: records.map((r) => [
            _cell(r.weldNo, bold: true),
            for (final m in NdtMethod.values) _ndtCell(r.ndtOf(m)),
            _cell(r.repairs.join('\n')),
            _cell([
              _yesNo(r.pwhtRequired),
              r.pwhtChart,
              r.hardness,
            ].where((s) => s.isNotEmpty).join(' · ')),
            _cell(_join(r.inspector, r.inspectedAt, '\n')),
            _cell(r.testPackage),
            _cell(r.exam),
            _statusCell(r),
          ]),
    );
  }

  // ── Table 3: QC remarks ───────────────────────────────────────────────────
  static pw.Widget _remarksTable(List<WeldJournalRecord> records) => _table(
        headers: const ['Nr / No.', 'Uwagi QC / QC remarks', 'Status'],
        widths: const {
          0: pw.FixedColumnWidth(46),
          1: pw.FlexColumnWidth(8),
          2: pw.FixedColumnWidth(38),
        },
        rows: [
          for (final r in records)
            if (r.qcRemarks.isNotEmpty)
              [
                _cell(r.weldNo, bold: true),
                _cell(r.qcRemarks.map((l) => '• $l').join('\n'),
                    color: _kNokInk),
                _statusCell(r),
              ],
        ],
      );

  // ── Appendix: change history ──────────────────────────────────────────────
  static pw.Widget _historyTable(List<WeldJournalRecord> records) => _table(
        headers: const [
          'Nr / No.',
          'Kiedy · kto · co · było → jest / When · who · what · was → is',
        ],
        widths: const {
          0: pw.FixedColumnWidth(46),
          1: pw.FlexColumnWidth(10),
        },
        rows: [
          for (final r in records)
            for (final l in r.history) [_cell(r.weldNo, bold: true), _cell(l)],
        ],
      );

  static pw.Widget _table({
    required List<String> headers,
    required Map<int, pw.TableColumnWidth> widths,
    required Iterable<List<pw.Widget>> rows,
  }) =>
      pw.Table(
        border: pw.TableBorder.all(color: _kRule, width: 0.5),
        columnWidths: widths,
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _kHeadFill),
            repeat: true, // header repeats on every page of a long journal
            children: headers
                .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 2.5, vertical: 3),
                      child: pw.Text(h,
                          style: pw.TextStyle(
                              fontSize: 6,
                              fontWeight: pw.FontWeight.bold,
                              color: _kInk)),
                    ))
                .toList(),
          ),
          ...rows.map((cells) => pw.TableRow(children: cells)),
        ],
      );

  static String _welderCell(WeldJournalRecord r) {
    final root = r.rootWelder.trim();
    final cap = r.capWelder.trim();
    final main = r.welder.trim();
    if (root.isEmpty && cap.isEmpty) return main;
    final pair = '${_dash(root)} / ${_dash(cap)}';
    return main.isEmpty || main == root || main == cap ? pair : '$main\n$pair';
  }

  static String _dash(String s) => s.trim().isEmpty ? '—' : s.trim();

  /// Joins two optional fields, dropping the glue when either side is empty
  /// so the cell never reads " / " or "60.3 x ".
  static String _join(String a, String b, String glue) {
    final l = a.trim();
    final r = b.trim();
    if (l.isEmpty) return r;
    if (r.isEmpty) return l;
    return '$l$glue$r';
  }

  static PdfColor _statusInk(String status) => switch (status) {
        'OK' => _kOkInk,
        'NOK' => _kNokInk,
        'PENDING' => _kPendingInk,
        _ => _kInk,
      };

  static pw.Widget _statusCell(WeldJournalRecord r) => _cell(
        r.deleted ? '${r.status}\nUSUN./DEL.' : r.status,
        color: _statusInk(r.status),
        bold: true,
      );

  /// Two lines: why and what (`wyb./sel. NOK`), then report and date.
  static pw.Widget _ndtCell(WeldNdt n) => _cell(
        [
          [NdtScope.tag(n.scope), n.result]
              .where((s) => s.isNotEmpty)
              .join(' '),
          [n.reportNo.trim(), n.date.trim()]
              .where((s) => s.isNotEmpty)
              .join(' '),
        ].where((s) => s.isNotEmpty).join('\n'),
        color: n.isRejected ? _kNokInk : null,
        bold: n.isRejected,
      );

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 6.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? _kInk,
          ),
        ),
      );

  // ── Legend ────────────────────────────────────────────────────────────────
  /// [isoDetails]: some weld prints the v28 line in the joint cell — only
  /// then is its key added, so an older journal keeps its legend unchanged.
  static pw.Widget _legend({bool isoDetails = false}) {
    pw.Widget item(String code, String text, PdfColor color) => pw.Padding(
          padding: const pw.EdgeInsets.only(right: 12, bottom: 2),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                  text: '$code ',
                  style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: color)),
              pw.TextSpan(
                  text: text, style: pw.TextStyle(fontSize: 7, color: _kInk)),
            ]),
          ),
        );
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _kRule, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Legenda / Legend',
              style: pw.TextStyle(
                  fontSize: 8, fontWeight: pw.FontWeight.bold, color: _kInk)),
          pw.SizedBox(height: 3),
          pw.Wrap(children: [
            item('OK', 'spoina przyjęta / weld accepted', _kOkInk),
            item('NOK', 'spoina odrzucona / weld rejected', _kNokInk),
            item(
                'PENDING',
                'czeka na badanie lub odbiór / awaiting '
                    'examination or acceptance',
                _kPendingInk),
            item(
                'USUN./DEL.',
                'wpis usunięty (zachowany w historii) / '
                    'deleted entry (kept in history)',
                _kInkMuted),
          ]),
          pw.Wrap(children: [
            item('wym./req.', 'badanie wymagane (100 %) / required', _kInk),
            item(
                'wyb./sel.',
                'wybrana do badania wyrywkowego / '
                    'selected for random examination',
                _kInk),
            item(
                'dod./add.',
                'badanie dodatkowe ASME B31.3 §341.3.4 / '
                    'progressive examination',
                _kInk),
            item(
                'R1, R2',
                'naprawa: data, przyczyna, stan przed naprawą / '
                    'repair: date, cause, state before repair',
                _kInk),
            item('W/S · M/F', 'warsztat / montaż — shop / field', _kInk),
            item('HI', 'energia liniowa kJ/mm / heat input kJ/mm', _kInk),
            if (isoDetails)
              item(
                  'T/P · ss nb · dip',
                  'ISO 9606-1: wyrób rura/blacha, prowadzenie grani, '
                      'przenoszenie metalu zwarciowe/inne / product pipe/plate, '
                      'root backing, dip/other metal transfer',
                  _kInk),
          ]),
        ],
      ),
    );
  }

  // ── Signatures ────────────────────────────────────────────────────────────
  static pw.Widget _signatures() {
    pw.Widget box(String role) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.all(6),
            height: 70,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kRule, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(role,
                    style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _kInk)),
                pw.Spacer(),
                _signLine('Imię i nazwisko / Name'),
                pw.SizedBox(height: 8),
                pw.Row(children: [
                  pw.Expanded(child: _signLine('Data / Date')),
                  pw.SizedBox(width: 6),
                  pw.Expanded(child: _signLine('Podpis / Signature')),
                ]),
              ],
            ),
          ),
        );
    return pw.Row(children: [
      box('Spawacz / Welder'),
      box('Kontrola jakości / QC'),
      box('Inspektor / Inspector'),
      box('Strona trzecia / TPI'),
    ]);
  }

  static pw.Widget _signLine(String label) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            height: 0.6,
            color: _kInkMuted,
          ),
          pw.Text(label, style: pw.TextStyle(fontSize: 6, color: _kInkMuted)),
        ],
      );
}
