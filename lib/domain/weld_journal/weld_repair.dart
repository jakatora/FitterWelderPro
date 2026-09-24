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

import 'weld_entry.dart';
import 'weld_ndt.dart';

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
      };

  static WeldRepair fromRow(Map<String, Object?> r) => WeldRepair(
        id: r['id'] as String,
        weldId: (r['weld_id'] as String?) ?? '',
        seq: (r['seq'] as num?)?.toInt() ?? 0,
        date: (r['date'] as String?) ?? '',
        reason: (r['reason'] as String?) ?? '',
        prevStatus: (r['prev_status'] as String?) ?? '',
        prevNdt: decodeNdtSnapshot(r['prev_ndt'] as String?),
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
    final was = [
      if (prevStatus.isNotEmpty) prevStatus,
      ...prevNok,
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
/// date is cleared — the repaired weld has not been examined yet. The scope
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
      repairs: [...weld.repairs, repair],
    ),
  );
}
