/// Rejestr trawienia / pasywacji (v25, tabela `passivation_records`) —
/// zapis do data booka: gdzie (linia, pakiet testowy, obszar), czym (środek
/// i partia), jak długo i w jakiej temperaturze, płukanie (konduktywność
/// wody), test i jego wynik, kto i kiedy.
///
/// Parametry wiążące podaje karta produktu i specyfikacja (ASTM A380 /
/// A967, ASME BPE, EN 2516) — rejestr tylko zapisuje, co zrobiono.
///
/// Czysty Dart: bez Fluttera i bez bazy.
library;

import '../../utils/decimal_parse.dart';

/// Rodzaj zabiegu.
abstract final class PassivationTreatment {
  static const String pickling = 'PICKLING';
  static const String passivation = 'PASSIVATION';
  static const String both = 'BOTH';
  static const List<String> values = [pickling, passivation, both];

  static String label(String code, {required bool en}) => switch (code) {
        pickling => en ? 'Pickling' : 'Trawienie',
        passivation => en ? 'Passivation' : 'Pasywacja',
        both => en ? 'Pickling + passivation' : 'Trawienie + pasywacja',
        _ => code,
      };
}

/// Wynik testu pasywacji.
abstract final class PassivationResult {
  static const String ok = 'OK';
  static const String nok = 'NOK';
  static const String none = '';
}

class PassivationRecord {
  final String id;

  /// `YYYY-MM-DD`.
  final String date;
  final String treatment;
  final String line;
  final String testPackage;

  /// Obszar / zakres (np. „spoiny W-001…W-040, strona wewnętrzna”).
  final String area;
  final String agent;
  final String agentBatch;

  /// Czas oddziaływania (min), temperatura (°C), konduktywność wody
  /// płuczącej (µS/cm).
  final double? dwellMin;
  final double? tempC;
  final double? rinseUsCm;

  /// Test (np. ferroxyl, test wilgotnościowy) i jego wynik.
  final String testMethod;
  final String testResult;

  final String byStamp;
  final String notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  const PassivationRecord({
    required this.id,
    required this.date,
    this.treatment = PassivationTreatment.passivation,
    this.line = '',
    this.testPackage = '',
    this.area = '',
    this.agent = '',
    this.agentBatch = '',
    this.dwellMin,
    this.tempC,
    this.rinseUsCm,
    this.testMethod = '',
    this.testResult = PassivationResult.none,
    this.byStamp = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toRow() => {
        'id': id,
        'date': date,
        'treatment': treatment,
        'line': line,
        'test_package': testPackage,
        'area': area,
        'agent': agent,
        'agent_batch': agentBatch,
        'dwell_min': dwellMin,
        'temp_c': tempC,
        'rinse_us_cm': rinseUsCm,
        'test_method': testMethod,
        'test_result': testResult,
        'by_stamp': byStamp,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static String _s(Object? v) => v is String ? v : '';
  static double? _d(Object? v) => v is num ? v.toDouble() : null;

  static PassivationRecord fromRow(Map<String, Object?> r) => PassivationRecord(
        id: r['id'] as String,
        date: _s(r['date']),
        treatment: _s(r['treatment']).isEmpty
            ? PassivationTreatment.passivation
            : _s(r['treatment']),
        line: _s(r['line']),
        testPackage: _s(r['test_package']),
        area: _s(r['area']),
        agent: _s(r['agent']),
        agentBatch: _s(r['agent_batch']),
        dwellMin: _d(r['dwell_min']),
        tempC: _d(r['temp_c']),
        rinseUsCm: _d(r['rinse_us_cm']),
        testMethod: _s(r['test_method']),
        testResult: _s(r['test_result']),
        byStamp: _s(r['by_stamp']),
        notes: _s(r['notes']),
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
        deletedAt: (r['deleted_at'] as num?)?.toInt(),
      );
}

/// Liczba z pola formularza („1,5”) albo `null` dla pustego / błędnego.
double? parsePassivationNumber(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final v = parseDecimal(t);
  return v == null || v < 0 ? null : v;
}

/// `1.5` → „1,5” (przecinek dla polskiego arkusza), `null` → pusty.
String formatPassivationNumber(double? v) {
  if (v == null) return '';
  final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}
