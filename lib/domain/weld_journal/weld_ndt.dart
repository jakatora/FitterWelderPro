/// Non-destructive examination (NDT) of one weld: VT / PT / MT / RT / UT.
///
/// Every method carries the same four facts an inspector reads off a weld
/// map: why the weld is examined at all ([WeldNdt.scope]), the result, the
/// report number and the date. Stored flat on the `weld_journal` row
/// (`ndt_<method>_<field>`, see [ndtColumn]) so a journal row stays one row —
/// the list, the filter, the CSV and the backup all read it without a join.
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'dart:convert';

/// The five examination methods of ISO 17635 / ASME B31.3 §344.
enum NdtMethod { vt, pt, mt, rt, ut }

extension NdtMethodX on NdtMethod {
  /// `VT`, `PT`, `MT`, `RT`, `UT` — the code printed on every report.
  String get code => name.toUpperCase();

  /// Radiography and ultrasonics examine the weld volume; they are the
  /// methods a "% of welds examined" requirement (e.g. B31.3 §341.4.1 random
  /// examination) is written against.
  bool get isVolumetric => this == NdtMethod.rt || this == NdtMethod.ut;
}

/// Why a weld is examined by a method.
///
/// One field rather than two flags ("required" + "selected") because they
/// exclude each other in practice: a weld under 100 % RT is not "picked" for
/// RT, and a randomly picked one is not "required". The third selection kind
/// exists for ASME B31.3 §341.3.4 progressive examination — the two extra
/// welds per reject have to be told apart from the ordinary random sample,
/// or the "still to examine" counter could never go down.
abstract final class NdtScope {
  /// Not examined by this method.
  static const String none = '';

  /// Required on this weld by the specification (e.g. 100 % RT).
  static const String required = 'REQ';

  /// Picked for a random / spot sample.
  static const String selected = 'SEL';

  /// Additional (progressive) sample after a reject, B31.3 §341.3.4.
  static const String progressive = 'ADD';

  static const List<String> values = [none, required, selected, progressive];

  /// Short bilingual tag for the PDF/CSV cell; explained in the PDF legend.
  static String tag(String scope) => switch (scope) {
        required => 'wym./req.',
        selected => 'wyb./sel.',
        progressive => 'dod./add.',
        _ => '',
      };
}

abstract final class NdtResult {
  static const String none = '';
  static const String ok = 'OK';
  static const String nok = 'NOK';
}

/// One method's examination state on one weld.
class WeldNdt {
  /// [NdtScope] value.
  final String scope;

  /// [NdtResult] value.
  final String result;

  final String reportNo;

  /// `YYYY-MM-DD` or empty.
  final String date;

  const WeldNdt({
    this.scope = NdtScope.none,
    this.result = NdtResult.none,
    this.reportNo = '',
    this.date = '',
  });

  bool get hasResult => result == NdtResult.ok || result == NdtResult.nok;
  bool get isRejected => result == NdtResult.nok;

  /// Examination is due (required or selected) but no result is recorded.
  bool get isAwaiting => scope.isNotEmpty && !hasResult;

  bool get isEmpty =>
      scope.isEmpty && result.isEmpty && reportNo.isEmpty && date.isEmpty;

  WeldNdt copyWith({
    String? scope,
    String? result,
    String? reportNo,
    String? date,
  }) =>
      WeldNdt(
        scope: scope ?? this.scope,
        result: result ?? this.result,
        reportNo: reportNo ?? this.reportNo,
        date: date ?? this.date,
      );

  Map<String, String> toJson() => {
        if (scope.isNotEmpty) 'scope': scope,
        if (result.isNotEmpty) 'result': result,
        if (reportNo.isNotEmpty) 'report': reportNo,
        if (date.isNotEmpty) 'date': date,
      };

  static WeldNdt fromJson(Map<Object?, Object?> json) => WeldNdt(
        scope: _str(json['scope']),
        result: _str(json['result']),
        reportNo: _str(json['report']),
        date: _str(json['date']),
      );

  /// Compact cell text, e.g. `wyb./sel. · OK · RT-001 · 2026-09-01`.
  String cellText() => [
        NdtScope.tag(scope),
        result,
        reportNo.trim(),
        date.trim(),
      ].where((s) => s.isNotEmpty).join(' · ');

  @override
  bool operator ==(Object other) =>
      other is WeldNdt &&
      other.scope == scope &&
      other.result == result &&
      other.reportNo == reportNo &&
      other.date == date;

  @override
  int get hashCode => Object.hash(scope, result, reportNo, date);

  @override
  String toString() => 'WeldNdt(${cellText()})';
}

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

/// The four stored fields of each method, in column order.
const List<String> kWeldNdtFields = ['scope', 'result', 'report', 'date'];

/// `weld_journal` column holding [field] of [method], e.g. `ndt_rt_result`.
String ndtColumn(NdtMethod method, String field) => 'ndt_${method.name}_$field';

/// Every NDT column of `weld_journal`, method by method.
final List<String> kWeldNdtColumns = List.unmodifiable([
  for (final m in NdtMethod.values)
    for (final f in kWeldNdtFields) ndtColumn(m, f),
]);

/// Flat row values for [ndt]. Methods without data are written as NULLs so a
/// weld that was never examined does not carry twenty empty strings.
Map<String, Object?> ndtToRow(Map<NdtMethod, WeldNdt> ndt) {
  final row = <String, Object?>{};
  for (final m in NdtMethod.values) {
    final n = ndt[m] ?? const WeldNdt();
    row[ndtColumn(m, 'scope')] = _nullIfEmpty(n.scope);
    row[ndtColumn(m, 'result')] = _nullIfEmpty(n.result);
    row[ndtColumn(m, 'report')] = _nullIfEmpty(n.reportNo);
    row[ndtColumn(m, 'date')] = _nullIfEmpty(n.date);
  }
  return row;
}

String? _nullIfEmpty(String s) => s.isEmpty ? null : s;

/// Reads the NDT columns of a `weld_journal` row. Methods whose columns are
/// all empty are left out of the map.
Map<NdtMethod, WeldNdt> ndtFromRow(Map<String, Object?> row) {
  final out = <NdtMethod, WeldNdt>{};
  for (final m in NdtMethod.values) {
    final n = WeldNdt(
      scope: _str(row[ndtColumn(m, 'scope')]),
      result: _str(row[ndtColumn(m, 'result')]),
      reportNo: _str(row[ndtColumn(m, 'report')]),
      date: _str(row[ndtColumn(m, 'date')]),
    );
    if (!n.isEmpty) out[m] = n;
  }
  return out;
}

/// Drops methods with no data, so two maps that mean the same compare equal.
Map<NdtMethod, WeldNdt> compactNdt(Map<NdtMethod, WeldNdt> ndt) => {
      for (final e in ndt.entries)
        if (!e.value.isEmpty) e.key: e.value,
    };

/// JSON snapshot of an NDT state, used by repairs to keep the result the
/// weld had before it was cut out and re-welded.
String encodeNdtSnapshot(Map<NdtMethod, WeldNdt> ndt) => jsonEncode({
      for (final m in NdtMethod.values)
        if (ndt[m] != null && !ndt[m]!.isEmpty) m.code: ndt[m]!.toJson(),
    });

/// Inverse of [encodeNdtSnapshot]. A damaged string yields an empty map: an
/// unreadable snapshot must not make the whole journal unreadable.
Map<NdtMethod, WeldNdt> decodeNdtSnapshot(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    final out = <NdtMethod, WeldNdt>{};
    for (final m in NdtMethod.values) {
      final v = decoded[m.code];
      if (v is Map) {
        final n = WeldNdt.fromJson(v);
        if (!n.isEmpty) out[m] = n;
      }
    }
    return out;
  } catch (_) {
    return const {};
  }
}
