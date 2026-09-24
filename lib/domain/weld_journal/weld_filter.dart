/// The journal's filter — and therefore also the export's selection.
///
/// The list on screen and the CSV/PDF export both go through
/// [filterWeldEntries], so "what I see" and "what the inspector gets" cannot
/// drift apart. The filter used to be status-only; an inspector asks for
/// "line L-12 from May, welder JK-12" or "everything still waiting for RT".
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'weld_dates.dart';
import 'weld_entry.dart';

/// NDT-based narrowing.
enum WeldNdtFilter {
  /// No NDT condition.
  all,

  /// Any method has a result.
  examined,

  /// RT or UT has a result.
  volumetric,

  /// A method is required/selected but has no result yet.
  awaiting,

  /// Any method rejected the weld (NOK).
  rejected,

  /// The weld has at least one repair (R1, R2, …).
  repaired,

  /// No method has a result.
  notExamined,
}

class WeldJournalFilter {
  /// `ALL` / `OK` / `NOK` / `PENDING` (or a legacy status string).
  final String status;

  /// Project name, matched trimmed and case-insensitively; empty = any.
  final String project;

  /// Substring of the line or the ISO/drawing number; empty = any.
  final String line;

  /// Welder stamp (welder, root or cap), exact and case-insensitive.
  final String welder;

  /// Inclusive `YYYY-MM-DD` bounds; empty = open. When a bound is set, an
  /// entry without a valid ISO date cannot be shown to be inside the range
  /// and is left out.
  final String dateFrom;
  final String dateTo;

  final WeldNdtFilter ndt;

  /// false: live entries only (default). true: soft-deleted entries only.
  final bool deleted;

  const WeldJournalFilter({
    this.status = 'ALL',
    this.project = '',
    this.line = '',
    this.welder = '',
    this.dateFrom = '',
    this.dateTo = '',
    this.ndt = WeldNdtFilter.all,
    this.deleted = false,
  });

  bool matches(WeldEntry e) {
    if (e.isDeleted != deleted) return false;
    if (status != 'ALL' && e.status != status) return false;
    final p = project.trim().toLowerCase();
    if (p.isNotEmpty && e.projectName.trim().toLowerCase() != p) return false;
    final l = line.trim().toLowerCase();
    if (l.isNotEmpty &&
        !e.pipeName.toLowerCase().contains(l) &&
        !e.isoDrawing.toLowerCase().contains(l)) {
      return false;
    }
    final w = welder.trim().toUpperCase();
    if (w.isNotEmpty && !e.stamps.any((s) => s.toUpperCase() == w)) {
      return false;
    }
    final from = dateFrom.trim();
    final to = dateTo.trim();
    if (from.isNotEmpty || to.isNotEmpty) {
      final d = e.date.trim();
      if (!isIsoWeldDate(d)) return false;
      if (from.isNotEmpty && d.compareTo(from) < 0) return false;
      if (to.isNotEmpty && d.compareTo(to) > 0) return false;
    }
    switch (ndt) {
      case WeldNdtFilter.all:
        break;
      case WeldNdtFilter.examined:
        if (!e.isExamined) return false;
      case WeldNdtFilter.volumetric:
        if (!e.isVolumetricExamined) return false;
      case WeldNdtFilter.awaiting:
        if (!e.ndt.values.any((n) => n.isAwaiting)) return false;
      case WeldNdtFilter.rejected:
        if (!e.ndt.values.any((n) => n.isRejected)) return false;
      case WeldNdtFilter.repaired:
        if (e.repairs.isEmpty) return false;
      case WeldNdtFilter.notExamined:
        if (e.isExamined) return false;
    }
    return true;
  }

  /// Filters beyond the status chips (a date range counts once).
  int get extraFilterCount => [
        project.trim().isNotEmpty,
        line.trim().isNotEmpty,
        welder.trim().isNotEmpty,
        dateFrom.trim().isNotEmpty || dateTo.trim().isNotEmpty,
        ndt != WeldNdtFilter.all,
        deleted,
      ].where((x) => x).length;

  bool get isDefault => status == 'ALL' && extraFilterCount == 0;

  /// One-line description for the screen and the PDF header; empty for the
  /// default filter.
  String describe({required bool en}) {
    final parts = <String>[
      if (status != 'ALL') '${en ? 'Status' : 'Status'}: $status',
      if (project.trim().isNotEmpty)
        '${en ? 'Project' : 'Projekt'}: ${project.trim()}',
      if (line.trim().isNotEmpty)
        '${en ? 'Line/ISO' : 'Linia/ISO'}: ${line.trim()}',
      if (welder.trim().isNotEmpty)
        '${en ? 'Welder' : 'Spawacz'}: ${welder.trim()}',
      if (dateFrom.trim().isNotEmpty || dateTo.trim().isNotEmpty)
        '${en ? 'Dates' : 'Daty'}: '
            '${dateFrom.trim().isEmpty ? '…' : dateFrom.trim()} – '
            '${dateTo.trim().isEmpty ? '…' : dateTo.trim()}',
      if (ndt != WeldNdtFilter.all) 'NDT: ${weldNdtFilterLabel(ndt, en: en)}',
      if (deleted) en ? 'deleted entries' : 'wpisy usunięte',
    ];
    return parts.join(' · ');
  }

  /// Short, file-name-safe tag: project and status, plus `FILTR` when any
  /// other narrowing is active (the full description is in the PDF header).
  String get fileTag {
    String safe(String s) => s
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final other = line.trim().isNotEmpty ||
        welder.trim().isNotEmpty ||
        dateFrom.trim().isNotEmpty ||
        dateTo.trim().isNotEmpty ||
        ndt != WeldNdtFilter.all;
    final parts = <String>[
      if (safe(project).isNotEmpty) safe(project),
      if (status != 'ALL') safe(status),
      if (deleted) 'USUNIETE',
      if (other) 'FILTR',
    ];
    return parts.join('_');
  }

  static const Object _keep = Object();

  WeldJournalFilter copyWith({
    String? status,
    String? project,
    String? line,
    String? welder,
    String? dateFrom,
    String? dateTo,
    WeldNdtFilter? ndt,
    Object? deleted = _keep,
  }) =>
      WeldJournalFilter(
        status: status ?? this.status,
        project: project ?? this.project,
        line: line ?? this.line,
        welder: welder ?? this.welder,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
        ndt: ndt ?? this.ndt,
        deleted: identical(deleted, _keep) ? this.deleted : deleted as bool,
      );
}

/// The entries [filter] shows, in the order given. Always a new list.
List<WeldEntry> filterWeldEntries(
        List<WeldEntry> entries, WeldJournalFilter filter) =>
    entries.where(filter.matches).toList();

String weldNdtFilterLabel(WeldNdtFilter f, {required bool en}) => switch (f) {
      WeldNdtFilter.all => en ? 'all' : 'wszystkie',
      WeldNdtFilter.examined => en ? 'examined (any)' : 'zbadane (dowolne)',
      WeldNdtFilter.volumetric => en ? 'RT/UT examined' : 'zbadane RT/UT',
      WeldNdtFilter.awaiting =>
        en ? 'awaiting NDT result' : 'czeka na wynik NDT',
      WeldNdtFilter.rejected => en ? 'NDT rejected (NOK)' : 'NDT odrzucone (NOK)',
      WeldNdtFilter.repaired => en ? 'repaired (R1/R2)' : 'naprawiane (R1/R2)',
      WeldNdtFilter.notExamined => en ? 'not examined' : 'niezbadane',
    };
