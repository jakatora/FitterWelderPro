/// Ocena stanowiska: materiał i proces, odciąg u źródła (z kalkulatorem),
/// ŚOI i lista kontrolna → jedna ocena z listą powodów.
///
/// Zasady zapisane w kodzie (i w testach):
/// * brak danych to NIE „ok” — każda brakująca odpowiedź to powód
///   [FumeLevel.incomplete];
/// * brak odciągu u źródła → nigdy zielone (co najmniej „ostrożnie”;
///   HSE 2019: każde spawanie wymaga środków technicznych);
/// * odciąg „jest”, ale kalkulator go nie potwierdził → do ŚOI liczy się
///   jak brak odciągu (minimum P3/TH3), a ocena nie jest zielona;
/// * ŚOI poniżej minimum dla materiału → „stop”;
/// * otwarte punkty listy kontrolnej → nie zielone.
///
/// Czysty Dart.
library;

import 'fume_capture.dart';
import 'fume_checklist.dart';
import 'fume_hazards.dart';

/// Odpowiedź „czy jest odciąg u źródła”.
enum FumeLevStatus {
  present,
  absent;

  static FumeLevStatus? byName(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

enum FumeReasonCode {
  materialMissing,
  processMissing,
  levUnknown,

  /// Brak odciągu u źródła — nigdy zielone.
  levAbsent,

  /// Odciąg jest, ale kalkulator nie ma danych do potwierdzenia zasięgu.
  captureUnverified,

  /// Wydajność za mała (na wpisaną odległość albo w ogóle).
  captureInsufficient,

  /// Wynik poza zakresem ważności równania (X > 1,5·D albo szczelina).
  captureOutOfRange,

  rpeMissing,

  /// ŚOI poniżej minimum dla materiału.
  rpeTooWeak,

  /// Otwarte punkty listy kontrolnej.
  checklistOpen,
}

class FumeReason {
  const FumeReason(this.code, this.level);
  final FumeReasonCode code;
  final FumeLevel level;
}

class FumeAssessment {
  const FumeAssessment({
    required this.reasons,
    required this.levEffective,
    this.requirement,
    this.openChecks = const [],
  });

  final List<FumeReason> reasons;

  /// Odciąg jest i kalkulator potwierdził zasięg.
  final bool levEffective;

  /// Minimalna ŚOI (null — brak materiału).
  final FumeRpeRequirement? requirement;

  /// Otwarte punkty listy.
  final List<FumeCheck> openChecks;

  /// Najgorsza ocena z powodów; bez powodów — „ok”.
  FumeLevel get level =>
      reasons.fold(FumeLevel.ok, (acc, r) => acc.worse(r.level));

  bool has(FumeReasonCode c) => reasons.any((r) => r.code == c);
}

FumeAssessment assessFume({
  required FumeMaterial? material,
  required FumeProcess? process,
  required FumeLevStatus? lev,
  required FumeCaptureResult? capture,
  required FumeRpe? rpe,
  required Map<String, FumeCheckState> checks,
}) {
  final reasons = <FumeReason>[];
  void add(FumeReasonCode c, FumeLevel l) => reasons.add(FumeReason(c, l));

  if (material == null) {
    add(FumeReasonCode.materialMissing, FumeLevel.incomplete);
  }
  if (process == null) {
    add(FumeReasonCode.processMissing, FumeLevel.incomplete);
  }

  var levEffective = false;
  switch (lev) {
    case null:
      add(FumeReasonCode.levUnknown, FumeLevel.incomplete);
    case FumeLevStatus.absent:
      add(FumeReasonCode.levAbsent, FumeLevel.caution);
    case FumeLevStatus.present:
      final level = capture?.level ?? FumeLevel.incomplete;
      switch (level) {
        case FumeLevel.ok:
          levEffective = true;
        case FumeLevel.incomplete:
          add(FumeReasonCode.captureUnverified, FumeLevel.incomplete);
        case FumeLevel.caution:
          add(FumeReasonCode.captureOutOfRange, FumeLevel.caution);
        case FumeLevel.stop:
          add(FumeReasonCode.captureInsufficient, FumeLevel.stop);
      }
  }

  final requirement = material == null
      ? null
      : fumeRpeRequirement(material, levEffective: levEffective);
  if (rpe == null) {
    add(FumeReasonCode.rpeMissing, FumeLevel.incomplete);
  } else if (requirement != null && !fumeRpeMeets(rpe, requirement)) {
    add(FumeReasonCode.rpeTooWeak, FumeLevel.stop);
  }

  final open = fumeOpenChecks(checks);
  if (open.isNotEmpty) add(FumeReasonCode.checklistOpen, FumeLevel.incomplete);

  return FumeAssessment(
    reasons: List.unmodifiable(reasons),
    levEffective: levEffective,
    requirement: requirement,
    openChecks: List.unmodifiable(open),
  );
}
