/// Weld repairs R1, R2, … and what a weld looked like before each of them.
///
/// A rejected weld is ground out and re-welded; the repaired weld then goes
/// back to examination by the same methods (ASME B31.3 §341.3.3, EN 13480-5
/// §8). Its new result replaces the old one on the weld — so the OLD result,
/// the NOK an inspector will ask about, has to live somewhere else. That is
/// this record: the status and the full NDT state as they were before the
/// repair ([WeldRepair.prevStatus], [WeldRepair.prevNdt]).
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'dart:convert';

import 'weld_entry.dart';
import 'weld_ndt.dart';

/// Odbiór, PWHT i twardość spoiny sprzed naprawy (kolumna
/// `weld_repairs.prev_acceptance`, v25, JSON).
///
/// Naprawiona spoina czeka na ponowne badanie — dawny odbiór inspektora,
/// wykres PWHT i pomiar twardości dotyczą spoiny, której już nie ma
/// (ASME B31.3 §341.3.3: naprawa jest badana ponownie; wymagane PWHT
/// powtarza się po naprawie). Dlatego naprawa je kasuje, a stare wartości
/// trafiają tutaj i do historii spoiny.
class WeldAcceptanceSnapshot {
  final String inspector;
  final String inspectedAt;
  final String pwhtChart;
  final String hardness;

  const WeldAcceptanceSnapshot({
    this.inspector = '',
    this.inspectedAt = '',
    this.pwhtChart = '',
    this.hardness = '',
  });

  factory WeldAcceptanceSnapshot.of(WeldEntry w) => WeldAcceptanceSnapshot(
        inspector: w.inspector.trim(),
        inspectedAt: w.inspectedAt.trim(),
        pwhtChart: w.pwhtChart.trim(),
        hardness: w.hardness.trim(),
      );

  bool get isEmpty =>
      inspector.isEmpty &&
      inspectedAt.isEmpty &&
      pwhtChart.isEmpty &&
      hardness.isEmpty;

  /// JSON albo `null` dla pustego (stary wiersz naprawy też ma NULL).
  String? encode() => isEmpty
      ? null
      : jsonEncode(<String, String>{
          if (inspector.isNotEmpty) 'inspector': inspector,
          if (inspectedAt.isNotEmpty) 'inspected_at': inspectedAt,
          if (pwhtChart.isNotEmpty) 'pwht_chart': pwhtChart,
          if (hardness.isNotEmpty) 'hardness': hardness,
        });

  /// Uszkodzony tekst daje pusty zapis — nie wywraca odczytu dziennika.
  static WeldAcceptanceSnapshot decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const WeldAcceptanceSnapshot();
    }
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const WeldAcceptanceSnapshot();
      String f(String k) => m[k] is String ? m[k] as String : '';
      return WeldAcceptanceSnapshot(
        inspector: f('inspector'),
        inspectedAt: f('inspected_at'),
        pwhtChart: f('pwht_chart'),
        hardness: f('hardness'),
      );
    } catch (_) {
      return const WeldAcceptanceSnapshot();
    }
  }

  /// „odbiór/accepted J. Inspektor 2025-10-03, PWHT PWHT-17, HB/HV 210 HV10".
  String describe() {
    final who = [inspector, inspectedAt].where((s) => s.isNotEmpty).join(' ');
    return [
      if (who.isNotEmpty) 'odbiór/accepted $who',
      if (pwhtChart.isNotEmpty) 'PWHT $pwhtChart',
      if (hardness.isNotEmpty) 'HB/HV $hardness',
    ].join(', ');
  }
}

class WeldRepair {
  final String id;
  final String weldId;

  /// 1 for R1, 2 for R2, …
  final int seq;

  /// `YYYY-MM-DD` of the repair.
  final String date;

  /// Defect / cause, e.g. "porowatość w graniu", "brak przetopu".
  final String reason;

  /// Weld status before the repair.
  final String prevStatus;

  /// NDT state before the repair — results, report numbers, dates.
  final Map<NdtMethod, WeldNdt> prevNdt;

  /// Acceptance, PWHT chart and hardness before the repair (v25).
  final WeldAcceptanceSnapshot prevAcceptance;

  /// Stamp of whoever recorded the repair (welder identity on the phone).
  final String byStamp;

  /// Epoch milliseconds when the repair was recorded.
  final int createdAt;

  const WeldRepair({
    required this.id,
    required this.weldId,
    required this.seq,
    required this.date,
    required this.reason,
    required this.prevStatus,
    required this.prevNdt,
    this.prevAcceptance = const WeldAcceptanceSnapshot(),
    required this.byStamp,
    required this.createdAt,
  });

  /// `R1`, `R2`, …
  String get label => 'R$seq';

  Map<String, Object?> toRow() => {
        'id': id,
        'weld_id': weldId,
        'seq': seq,
        'date': date,
        'reason': reason,
        'prev_status': prevStatus,
        'prev_ndt': encodeNdtSnapshot(prevNdt),
        'by_stamp': byStamp,
        'created_at': createdAt,
        'prev_acceptance': prevAcceptance.encode(),
      };

  static WeldRepair fromRow(Map<String, Object?> r) => WeldRepair(
        id: r['id'] as String,
        weldId: (r['weld_id'] as String?) ?? '',
        seq: (r['seq'] as num?)?.toInt() ?? 0,
        date: (r['date'] as String?) ?? '',
        reason: (r['reason'] as String?) ?? '',
        prevStatus: (r['prev_status'] as String?) ?? '',
        prevNdt: decodeNdtSnapshot(r['prev_ndt'] as String?),
        prevAcceptance:
            WeldAcceptanceSnapshot.decode(r['prev_acceptance'] as String?),
        byStamp: (r['by_stamp'] as String?) ?? '',
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      );

  /// One-line summary for the PDF / CSV, e.g.
  /// `R1 2026-09-21: porowatość (NOK, RT NOK)` — the reason, then the
  /// status and the rejecting methods the weld had before the repair.
  String summary() {
    final prevNok = [
      for (final m in NdtMethod.values)
        if (prevNdt[m]?.isRejected ?? false) '${m.code} NOK',
    ];
    // Comma, not semicolon: the summary lands in a CSV cell, and although
    // the CSV writer quotes it correctly, a comma keeps the cell readable.
    final acceptance = prevAcceptance.describe();
    final was = [
      if (prevStatus.isNotEmpty) prevStatus,
      ...prevNok,
      if (acceptance.isNotEmpty) acceptance,
    ].join(', ');
    final head = [label, if (date.isNotEmpty) date].join(' ');
    final body = reason.trim().isEmpty ? '' : ': ${reason.trim()}';
    final tail = was.isEmpty ? '' : ' ($was)';
    return '$head$body$tail';
  }
}

/// What recording a repair does: the new repair record plus the weld as it
/// is after the repair.
class WeldRepairPlan {
  final WeldRepair repair;
  final WeldEntry weld;
  const WeldRepairPlan(this.repair, this.weld);
}

/// Records a repair on [weld].
///
/// The weld goes back to `PENDING` and every NDT result, report number and
/// date is cleared — the repaired weld has not been examined yet. The
/// inspector's acceptance (who, when), the PWHT chart number and the
/// hardness are cleared too: they belong to the weld that was cut out, and a
/// PDF showing an accepted weld that awaits re-examination is a false record.
/// Their old values are kept in [WeldRepair.prevAcceptance] (and the DAO logs
/// every cleared field to the weld history). "PWHT required" stays. The scope
/// stays: a weld selected for RT is re-radiographed. A method that had a
/// result but no scope becomes [NdtScope.required], because re-examination
/// by the same method is not optional after a repair.
WeldRepairPlan planWeldRepair(
  WeldEntry weld, {
  required String id,
  required String date,
  required String reason,
  required String byStamp,
  required int createdAt,
}) {
  final seq = weld.repairs.fold<int>(0, (m, r) => r.seq > m ? r.seq : m) + 1;
  final repair = WeldRepair(
    id: id,
    weldId: weld.id,
    seq: seq,
    date: date.trim(),
    reason: reason.trim(),
    prevStatus: weld.status,
    prevNdt: compactNdt(weld.ndt),
    prevAcceptance: WeldAcceptanceSnapshot.of(weld),
    byStamp: byStamp,
    createdAt: createdAt,
  );
  final reset = <NdtMethod, WeldNdt>{};
  for (final e in weld.ndt.entries) {
    final n = e.value;
    final scope = n.scope.isEmpty && n.hasResult ? NdtScope.required : n.scope;
    if (scope.isEmpty) continue;
    reset[e.key] = WeldNdt(scope: scope);
  }
  return WeldRepairPlan(
    repair,
    weld.copyWith(
      status: 'PENDING',
      ndt: reset,
      inspector: '',
      inspectedAt: '',
      pwhtChart: '',
      hardness: '',
      repairs: [...weld.repairs, repair],
    ),
  );
}
