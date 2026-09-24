/// A test coupon ("kupon próbny"): a sacrificial weld made — on food and
/// pharma work usually at the start of every shift and on every orbital
/// machine — and accepted before touching production (ASME BPE MJ-7.3,
/// AWS D18.1/D18.2). The coupon log is that record.
///
/// v20 adds what an auditor asks next to "was it OK?": the weld program
/// number and its parameters, the O₂ reading of the purge gas and the heat
/// tint level on the AWS D18.2 scale 1–10 (see `lib/data/heat_tint.dart`).
///
/// Pure Dart: no Flutter, no I/O.
library;

class CouponEntry {
  final String id;
  final String date;
  final String welder;

  /// Orbital machine / weld-head identifier.
  final String machine;

  /// Tube OD × wall.
  final String size;

  /// OK / NOK.
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
  });

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
      };

  static CouponEntry fromRow(Map<String, Object?> r) => CouponEntry(
        id: r['id'] as String,
        date: (r['date'] as String?) ?? '',
        welder: (r['welder'] as String?) ?? '',
        machine: (r['machine'] as String?) ?? '',
        size: (r['size'] as String?) ?? '',
        result: (r['result'] as String?) ?? 'OK',
        notes: (r['notes'] as String?) ?? '',
        programNo: (r['program_no'] as String?) ?? '',
        programParams: (r['program_params'] as String?) ?? '',
        o2Ppm: (r['o2_ppm'] as num?)?.toDouble(),
        heatTint: (r['heat_tint'] as num?)?.toInt(),
      );

  /// Reference written into a weld's coupon field when the coupon is picked
  /// from the log, e.g. `2026-09-20 · M-3 · 2"×1.65 · P12 · OK`.
  String get reference => [
        date.trim(),
        machine.trim(),
        size.trim(),
        if (programNo.trim().isNotEmpty) 'P${programNo.trim()}',
        result.trim(),
      ].where((s) => s.isNotEmpty).join(' · ');

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
      );
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
