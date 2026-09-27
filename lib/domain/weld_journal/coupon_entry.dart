/// A test coupon ("kupon próbny"): a sacrificial weld made — on food and
/// pharma work usually at the start of every shift and on every orbital
/// machine — and accepted before touching production (ASME BPE MJ-7.3,
/// AWS D18.1/D18.2). The coupon log is that record.
///
/// v20 adds what an auditor asks next to "was it OK?": the weld program
/// number and its parameters, the O₂ reading of the purge gas and the heat
/// tint level on the AWS D18.2 scale 1–10 (see `lib/data/heat_tint.dart`).
///
/// v25 makes it a quality record: a coupon starts "to be assessed" (never a
/// default OK), who accepted it and when is recorded, every change goes to
/// `weld_coupon_history`, and deleting is soft — welds linked to a coupon
/// keep pointing at it and see it as deleted.
///
/// Pure Dart: no Flutter, no I/O.
library;

/// Coupon results. Legacy rows hold OK / NOK; an empty or NULL result is
/// read as [pending] — never as an acceptance nobody gave.
abstract final class CouponResult {
  static const String ok = 'OK';
  static const String nok = 'NOK';
  static const String pending = 'PENDING';
  static const List<String> values = [pending, ok, nok];

  static String normalize(String? raw) {
    final v = raw?.trim().toUpperCase() ?? '';
    return v.isEmpty ? pending : v;
  }
}

/// Marker added to a coupon reference once the coupon is deleted from the
/// log — bilingual because the reference text goes to CSV / PDF as is.
const String kCouponDeletedMarker = 'USUNIĘTY/DELETED';

class CouponEntry {
  final String id;
  final String date;
  final String welder;

  /// Orbital machine / weld-head identifier.
  final String machine;

  /// Tube OD × wall.
  final String size;

  /// [CouponResult] value.
  final String result;
  final String notes;

  /// Weld program number on the power source (v20).
  final String programNo;

  /// Program parameters as typed (amps, speed, pulses, gas flow…) (v20).
  final String programParams;

  /// Residual O₂ of the purge gas, ppm (v20).
  final double? o2Ppm;

  /// Heat tint level, AWS D18.2 sample 1–10 (v20).
  final int? heatTint;

  /// Who accepted the coupon (on BPE work usually the owner's inspector)
  /// and when (`YYYY-MM-DD`) — v25.
  final String acceptedBy;
  final String acceptedAt;

  /// Epoch ms of the soft delete, or null (v25).
  final int? deletedAt;

  const CouponEntry({
    required this.id,
    required this.date,
    required this.welder,
    required this.machine,
    required this.size,
    required this.result,
    required this.notes,
    this.programNo = '',
    this.programParams = '',
    this.o2Ppm,
    this.heatTint,
    this.acceptedBy = '',
    this.acceptedAt = '',
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get isOk => result == CouponResult.ok;
  bool get isRejected => result == CouponResult.nok;
  bool get isPending => result == CouponResult.pending;

  Map<String, Object?> toRow() => {
        'id': id,
        'date': date,
        'welder': welder,
        'machine': machine,
        'size': size,
        'result': result,
        'notes': notes,
        'program_no': programNo,
        'program_params': programParams,
        'o2_ppm': o2Ppm,
        'heat_tint': heatTint,
        'accepted_by': acceptedBy.isEmpty ? null : acceptedBy,
        'accepted_at': acceptedAt.isEmpty ? null : acceptedAt,
        'deleted_at': deletedAt,
      };

  static CouponEntry fromRow(Map<String, Object?> r) => CouponEntry(
        id: r['id'] as String,
        date: (r['date'] as String?) ?? '',
        welder: (r['welder'] as String?) ?? '',
        machine: (r['machine'] as String?) ?? '',
        size: (r['size'] as String?) ?? '',
        result: CouponResult.normalize(r['result'] as String?),
        notes: (r['notes'] as String?) ?? '',
        programNo: (r['program_no'] as String?) ?? '',
        programParams: (r['program_params'] as String?) ?? '',
        o2Ppm: (r['o2_ppm'] as num?)?.toDouble(),
        heatTint: (r['heat_tint'] as num?)?.toInt(),
        acceptedBy: (r['accepted_by'] as String?) ?? '',
        acceptedAt: (r['accepted_at'] as String?) ?? '',
        deletedAt: (r['deleted_at'] as num?)?.toInt(),
      );

  /// Reference written into a weld's coupon field when the coupon is picked
  /// from the log, e.g. `2026-09-20 · M-3 · 2"×1.65 · P12 · OK`. A deleted
  /// coupon carries [kCouponDeletedMarker], so every linked weld shows it.
  String get reference => [
        date.trim(),
        machine.trim(),
        size.trim(),
        if (programNo.trim().isNotEmpty) 'P${programNo.trim()}',
        result.trim(),
        if (isDeleted) kCouponDeletedMarker,
      ].where((s) => s.isNotEmpty).join(' · ');

  /// Every field the coupon history tracks, as strings, in display order.
  Map<String, String> auditFields() => {
        'date': date,
        'welder': welder,
        'machine': machine,
        'size': size,
        'program_no': programNo,
        'program_params': programParams,
        'o2_ppm': formatO2Ppm(o2Ppm),
        'heat_tint': heatTint?.toString() ?? '',
        'result': result,
        'accepted_by': acceptedBy,
        'accepted_at': acceptedAt,
        'notes': notes,
      };

  static const Object _keep = Object();

  CouponEntry copyWith({
    String? date,
    String? welder,
    String? machine,
    String? size,
    String? result,
    String? notes,
    String? programNo,
    String? programParams,
    Object? o2Ppm = _keep,
    Object? heatTint = _keep,
    String? acceptedBy,
    String? acceptedAt,
    Object? deletedAt = _keep,
  }) =>
      CouponEntry(
        id: id,
        date: date ?? this.date,
        welder: welder ?? this.welder,
        machine: machine ?? this.machine,
        size: size ?? this.size,
        result: result ?? this.result,
        notes: notes ?? this.notes,
        programNo: programNo ?? this.programNo,
        programParams: programParams ?? this.programParams,
        o2Ppm: identical(o2Ppm, _keep)
            ? this.o2Ppm
            : (o2Ppm as num?)?.toDouble(),
        heatTint: identical(heatTint, _keep) ? this.heatTint : heatTint as int?,
        acceptedBy: acceptedBy ?? this.acceptedBy,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        deletedAt:
            identical(deletedAt, _keep) ? this.deletedAt : deletedAt as int?,
      );
}

/// Fields of [after] that differ from [before] (history of the coupon log).
List<(String field, String oldValue, String newValue)> diffCoupons(
    CouponEntry before, CouponEntry after) {
  final a = before.auditFields();
  final b = after.auditFields();
  return [
    for (final k in a.keys)
      if ((a[k] ?? '') != (b[k] ?? '')) (k, a[k] ?? '', b[k] ?? ''),
  ];
}

/// Label of a coupon history field.
String couponFieldLabel(String field, {required bool en}) =>
    switch (field) {
      'date' => en ? 'Date' : 'Data',
      'welder' => en ? 'Welder' : 'Spawacz',
      'machine' => en ? 'Machine / head' : 'Maszyna / głowica',
      'size' => en ? 'Size' : 'Wymiar',
      'program_no' => en ? 'Program no.' : 'Nr programu',
      'program_params' => en ? 'Program parameters' : 'Parametry programu',
      'o2_ppm' => 'O₂ (ppm)',
      'heat_tint' => en ? 'Heat tint' : 'Przebarwienie',
      'result' => en ? 'Result' : 'Wynik',
      'accepted_by' => en ? 'Accepted by' : 'Przyjął',
      'accepted_at' => en ? 'Accepted on' : 'Data przyjęcia',
      'notes' => en ? 'Notes' : 'Uwagi',
      _ => field,
    };

/// Warnings for a coupon about to be saved: a result that contradicts the
/// heat tint, or an OK nobody signed. [tintLimit] — highest acceptable AWS
/// D18.2 level of the project (see `HeatTintLimit`).
List<String> couponWarnings(CouponEntry c,
    {required int tintLimit, required bool en}) {
  final out = <String>[];
  final tint = c.heatTint;
  if (c.isOk && tint != null && tint > tintLimit) {
    out.add(en
        ? 'Heat tint level $tint is above the acceptance limit '
            '(≤ $tintLimit) — result OK?'
        : 'Przebarwienie poziom $tint przekracza limit akceptacji '
            '(≤ $tintLimit) — wynik OK?');
  }
  if (c.isOk && c.acceptedBy.trim().isEmpty) {
    out.add(en
        ? 'Result OK without "accepted by".'
        : 'Wynik OK bez wpisu „przyjął”.');
  }
  return out;
}

/// Parses an O₂ reading typed as "12", "12,5" or "12 ppm". Null for empty
/// or impossible input (negative, or above 1 000 000 ppm = 100 %).
double? parseO2Ppm(String raw) {
  final s = raw.toLowerCase().replaceAll('ppm', '').replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v < 0 || v > 1000000) return null;
  return v;
}

/// `12`, `12.5` — no trailing ".0" in a field the welder reads back.
String formatO2Ppm(double? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toString();
}
