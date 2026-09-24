/// Metadane protokołu próby ciśnieniowej (`HydrotestRecord.meta`).
///
/// Protokół odbiorowy (ASME B31.3 §345.2.7 wymaga m.in. identyfikacji
/// badanego systemu, medium, ciśnienia próby i daty) potrzebuje też pól, bez
/// których inspektor go nie przyjmie: firma, projekt/klient, nr pakietu
/// testowego, odniesienia P&ID/ISO, medium, rodzaj próby i norma, ST/S,
/// temperatura metalu, zakres i ważność kalibracji manometru, nastawa zaworu
/// bezpieczeństwa, nr protokołu i rewizja.
///
/// PRZECHOWYWANIE: kolumny tabeli `hydrotest_records` dodane w schemacie v19
/// (`lib/database/db.dart`), opisane w [HydrotestProtocolMeta.columns].
/// Test `test/database/hydrotest_protocol_columns_test.dart` pilnuje, żeby
/// ta lista i schemat bazy się nie rozjechały. Próby zapisane przed v19 mają
/// te kolumny puste (NULL) — protokół drukuje wtedy „—”.
library;

import 'test_pressure.dart';

class HydrotestProtocolMeta {
  /// Firma wykonująca próbę.
  final String company;

  /// Projekt / klient.
  final String project;

  /// Numer pakietu testowego (test package).
  final String testPackage;

  /// Odniesienia do rysunków: P&ID, izometrie.
  final String drawingRefs;

  /// Medium próby (woda, woda zdemi, azot, powietrze…).
  final String testMedium;

  /// [PressureTestPreset.id] — rodzaj próby i norma.
  final String presetId;

  /// Stosunek naprężeń wpisany do kalkulatora (ST/S, f_test/f, LSR).
  final double? stressRatio;

  /// Temperatura metalu podczas próby [°C] (pomiar).
  final double? metalTempC;

  /// Zakres manometru, np. `0–25 bar`.
  final String gaugeRange;

  /// Data ważności kalibracji manometru, `YYYY-MM-DD`.
  final String gaugeCalibrationDue;

  /// Nastawa zaworu bezpieczeństwa [bar].
  final double? reliefSetBar;

  /// Numer protokołu.
  final String protocolNo;

  /// Rewizja protokołu.
  final String revision;

  const HydrotestProtocolMeta({
    this.company = '',
    this.project = '',
    this.testPackage = '',
    this.drawingRefs = '',
    this.testMedium = '',
    this.presetId = '',
    this.stressRatio,
    this.metalTempC,
    this.gaugeRange = '',
    this.gaugeCalibrationDue = '',
    this.reliefSetBar,
    this.protocolNo = '',
    this.revision = '',
  });

  /// Kolumny tabeli `hydrotest_records` (nazwa → typ SQLite), schemat v19.
  static const Map<String, String> columns = {
    'company': 'TEXT',
    'project': 'TEXT',
    'test_package': 'TEXT',
    'drawing_refs': 'TEXT',
    'test_medium': 'TEXT',
    'test_preset': 'TEXT',
    'stress_ratio': 'REAL',
    'metal_temp_c': 'REAL',
    'gauge_range': 'TEXT',
    'gauge_cal_due': 'TEXT',
    'relief_set_bar': 'REAL',
    'protocol_no': 'TEXT',
    'protocol_rev': 'TEXT',
  };

  PressureTestPreset? get preset => PressureTestPreset.fromId(presetId);

  bool get isEmpty =>
      company.trim().isEmpty &&
      project.trim().isEmpty &&
      testPackage.trim().isEmpty &&
      drawingRefs.trim().isEmpty &&
      testMedium.trim().isEmpty &&
      presetId.trim().isEmpty &&
      stressRatio == null &&
      metalTempC == null &&
      gaugeRange.trim().isEmpty &&
      gaugeCalibrationDue.trim().isEmpty &&
      reliefSetBar == null &&
      protocolNo.trim().isEmpty &&
      revision.trim().isEmpty;

  /// Wartości kolumn [columns]. Niewpisany tekst zapisuje się jako NULL —
  /// tak samo jak w próbach sprzed v19 — a nie jako pusty napis.
  Map<String, Object?> toRow() => {
        'company': _n(company),
        'project': _n(project),
        'test_package': _n(testPackage),
        'drawing_refs': _n(drawingRefs),
        'test_medium': _n(testMedium),
        'test_preset': _n(presetId),
        'stress_ratio': stressRatio,
        'metal_temp_c': metalTempC,
        'gauge_range': _n(gaugeRange),
        'gauge_cal_due': _n(gaugeCalibrationDue),
        'relief_set_bar': reliefSetBar,
        'protocol_no': _n(protocolNo),
        'protocol_rev': _n(revision),
      };

  static String? _n(String v) => v.trim().isEmpty ? null : v;

  /// Odczyt z wiersza bazy; brakujące kolumny / NULL → puste pola.
  static HydrotestProtocolMeta fromRow(Map<String, Object?> r) =>
      HydrotestProtocolMeta(
        company: _s(r['company']),
        project: _s(r['project']),
        testPackage: _s(r['test_package']),
        drawingRefs: _s(r['drawing_refs']),
        testMedium: _s(r['test_medium']),
        presetId: _s(r['test_preset']),
        stressRatio: _d(r['stress_ratio']),
        metalTempC: _d(r['metal_temp_c']),
        gaugeRange: _s(r['gauge_range']),
        gaugeCalibrationDue: _s(r['gauge_cal_due']),
        reliefSetBar: _d(r['relief_set_bar']),
        protocolNo: _s(r['protocol_no']),
        revision: _s(r['protocol_rev']),
      );

  static String _s(Object? v) => v is String ? v : '';
  static double? _d(Object? v) => v is num ? v.toDouble() : null;

  @override
  bool operator ==(Object other) =>
      other is HydrotestProtocolMeta &&
      other.company == company &&
      other.project == project &&
      other.testPackage == testPackage &&
      other.drawingRefs == drawingRefs &&
      other.testMedium == testMedium &&
      other.presetId == presetId &&
      other.stressRatio == stressRatio &&
      other.metalTempC == metalTempC &&
      other.gaugeRange == gaugeRange &&
      other.gaugeCalibrationDue == gaugeCalibrationDue &&
      other.reliefSetBar == reliefSetBar &&
      other.protocolNo == protocolNo &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(
        company,
        project,
        testPackage,
        drawingRefs,
        testMedium,
        presetId,
        stressRatio,
        metalTempC,
        gaugeRange,
        gaugeCalibrationDue,
        reliefSetBar,
        protocolNo,
        revision,
      );
}
