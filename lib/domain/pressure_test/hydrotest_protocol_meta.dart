/// Metadane protokołu próby ciśnieniowej, których nie ma w `HydrotestRecord`.
///
/// Protokół odbiorowy (ASME B31.3 §345.2.7 wymaga m.in. identyfikacji
/// badanego systemu, medium, ciśnienia próby i daty) potrzebuje też pól, bez
/// których inspektor go nie przyjmie: firma, projekt/klient, nr pakietu
/// testowego, odniesienia P&ID/ISO, medium, rodzaj próby i norma, ST/S,
/// temperatura metalu, zakres i ważność kalibracji manometru, nastawa zaworu
/// bezpieczeństwa, nr protokołu i rewizja.
///
/// PRZECHOWYWANIE — tymczasowe:
/// tabela `hydrotest_records` nie ma na te pola kolumn, a jej DDL
/// (`hydrotest_dao.dart` / `db.dart`) należy do innej zmiany. Do czasu
/// migracji metadane są doklejane jako JSON na końcu istniejącej kolumny TEXT
/// `notes`, za znacznikiem [kHydrotestMetaMarker]. [splitHydrotestNotes]
/// oddziela je z powrotem, więc ani ekran, ani PDF nie pokazują JSON-a
/// użytkownikowi, a stare rekordy (bez znacznika) czytają się bez zmian.
///
/// Docelowe kolumny opisuje [HydrotestProtocolMeta.columns]; [toRow] /
/// [fromRow] już ich używają, żeby po migracji wystarczyło je podpiąć.
library;

import 'dart:convert';

import 'test_pressure.dart';

/// Znacznik początku bloku metadanych w kolumnie `notes`. Nie zmieniać —
/// zapisane rekordy go zawierają.
const String kHydrotestMetaMarker = '[[fwp-protocol-meta:v1]]';

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

  /// Proponowane kolumny tabeli `hydrotest_records` (nazwa → typ SQLite).
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

  /// Wiersz pod docelowe kolumny ([columns]).
  Map<String, Object?> toRow() => {
        'company': company,
        'project': project,
        'test_package': testPackage,
        'drawing_refs': drawingRefs,
        'test_medium': testMedium,
        'test_preset': presetId,
        'stress_ratio': stressRatio,
        'metal_temp_c': metalTempC,
        'gauge_range': gaugeRange,
        'gauge_cal_due': gaugeCalibrationDue,
        'relief_set_bar': reliefSetBar,
        'protocol_no': protocolNo,
        'protocol_rev': revision,
      };

  /// Odczyt z wiersza (docelowe kolumny) albo z JSON-a — te same klucze.
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

  /// JSON bez pustych pól — krócej w kolumnie `notes`.
  Map<String, Object?> toJson() {
    final out = <String, Object?>{};
    toRow().forEach((k, v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      out[k] = v;
    });
    return out;
  }

  static HydrotestProtocolMeta fromJson(Map<String, Object?> j) => fromRow(j);

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

/// Uwagi użytkownika i metadane rozdzielone z kolumny `notes`.
class HydrotestNotesSplit {
  final String notes;
  final HydrotestProtocolMeta? meta;
  const HydrotestNotesSplit(this.notes, this.meta);
}

/// Rozdziela zawartość kolumny `notes` na tekst użytkownika i metadane.
///
/// Brak znacznika albo uszkodzony JSON → cały tekst to uwagi, `meta == null`
/// (nic z tego, co wpisał człowiek, nie może zniknąć).
HydrotestNotesSplit splitHydrotestNotes(String raw) {
  final i = raw.lastIndexOf(kHydrotestMetaMarker);
  if (i < 0) return HydrotestNotesSplit(raw, null);
  try {
    final decoded = jsonDecode(raw.substring(i + kHydrotestMetaMarker.length));
    if (decoded is Map<String, dynamic>) {
      return HydrotestNotesSplit(
        raw.substring(0, i).trimRight(),
        HydrotestProtocolMeta.fromJson(decoded),
      );
    }
  } on FormatException {
    // Poniżej: traktuj całość jako uwagi.
  }
  return HydrotestNotesSplit(raw, null);
}

/// Dokleja [meta] jako JSON do [notes] (usuwając ewentualny stary blok).
String embedHydrotestMeta(String notes, HydrotestProtocolMeta meta) {
  final clean = splitHydrotestNotes(notes).notes.trimRight();
  if (meta.isEmpty) return clean;
  final json = jsonEncode(meta.toJson());
  return clean.isEmpty
      ? '$kHydrotestMetaMarker$json'
      : '$clean\n\n$kHydrotestMetaMarker$json';
}
