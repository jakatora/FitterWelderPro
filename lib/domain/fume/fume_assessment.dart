/// Ocena stanowiska: materiał i proces, odciąg u źródła (z kalkulatorem),
/// ŚOI i lista kontrolna → jedna ocena z listą powodów.
///
/// Zasady zapisane w kodzie (i w testach):
/// * brak danych to NIE „ok” — każda brakująca odpowiedź to powód
///   [FumeLevel.incomplete];
/// * brak odciągu u źródła → nigdy zielone (co najmniej „ostrożnie”;
///   HSE 2019: każde spawanie wymaga środków technicznych);
/// * odciąg jest „sprawdzony” tylko wtedy, gdy podano RZECZYWISTĄ odległość
///   ssawki od łuku, wydajność na nią wystarcza i odległość mieści się
///   w zakresie równania; sam zasięg z wydajności, błędna lub pusta
///   odległość → do ŚOI liczy się jak brak odciągu (minimum P3/TH3), a ocena
///   nie jest zielona;
/// * ŚOI poniżej minimum dla materiału → „stop”;
/// * gazy (ozon, NOx, CO, opary z powłok) — filtr P ich nie zatrzymuje:
///   zielone tylko po zaznaczeniu punktu listy o gazach (bez „nie dotyczy”);
/// * maska przylegająca (FFP / półmaska) — bez odpowiedzi o czasie noszenia
///   nie ma zieleni, a ponad godzinę bez przerwy → „ostrożnie” (HSE: FFP3/P3
///   do ok. godziny, dłużej — nawiew TH2/TH3);
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

  /// Odciąg jest, ale kalkulator nie ma danych do potwierdzenia (otwór,
  /// wydajność).
  captureUnverified,

  /// Brak rzeczywistej odległości ssawki od łuku — sam zasięg to nie
  /// potwierdzenie.
  captureDistanceMissing,

  /// Pole odległości wpisane, ale nieczytelne albo ≤ 0.
  captureDistanceInvalid,

  /// Odległość ponad limit pola — ssawka tak daleko nie łapie dymu.
  captureDistanceTooFar,

  /// Wydajność za mała (na wpisaną odległość albo w ogóle).
  captureInsufficient,

  /// Wynik poza zakresem ważności równania (X > 1,5·D albo szczelina).
  captureOutOfRange,

  rpeMissing,

  /// ŚOI poniżej minimum dla materiału.
  rpeTooWeak,

  /// Gazy, których filtry P nie zatrzymują — punkt listy o gazach
  /// niepotwierdzony.
  gasHazard,

  /// Maska przylegająca bez odpowiedzi o czasie noszenia.
  wearTimeUnknown,

  /// Maska przylegająca ponad godzinę bez przerwy.
  wearTooLong,

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
    required this.gasHazard,
    this.requirement,
    this.openChecks = const [],
  });

  final List<FumeReason> reasons;

  /// Odciąg jest, a kalkulator potwierdził go dla rzeczywistej odległości.
  final bool levEffective;

  /// Para materiał–proces daje gazy (ozon, NOx, CO, opary z powłok).
  final bool gasHazard;

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

  /// Maska noszona bez przerwy dłużej niż godzinę (null — brak odpowiedzi).
  bool? longWear,
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
      _captureReasons(capture, add);
      levEffective = capture?.level == FumeLevel.ok;
  }

  final requirement = material == null
      ? null
      : fumeRpeRequirement(material, levEffective: levEffective);
  if (rpe == null) {
    add(FumeReasonCode.rpeMissing, FumeLevel.incomplete);
  } else {
    if (requirement != null && !fumeRpeMeets(rpe, requirement)) {
      add(FumeReasonCode.rpeTooWeak, FumeLevel.stop);
    }
    if (rpe.tightFitting) {
      if (longWear == null) {
        add(FumeReasonCode.wearTimeUnknown, FumeLevel.incomplete);
      } else if (longWear) {
        add(FumeReasonCode.wearTooLong, FumeLevel.caution);
      }
    }
  }

  final ctx = FumeCheckContext(material: material, process: process, rpe: rpe);
  final gas = ctx.gasHazard;
  if (gas) {
    final gasCheck = fumeCheckById(kFumeCheckGasId)!;
    if (fumeCheckState(gasCheck, checks, ctx) != FumeCheckState.done) {
      add(FumeReasonCode.gasHazard, FumeLevel.caution);
    }
  }

  final open = fumeOpenChecks(checks, ctx);
  if (open.isNotEmpty) add(FumeReasonCode.checklistOpen, FumeLevel.incomplete);

  return FumeAssessment(
    reasons: List.unmodifiable(reasons),
    levEffective: levEffective,
    gasHazard: gas,
    requirement: requirement,
    openChecks: List.unmodifiable(open),
  );
}

/// Powody z kalkulatora odciągu (odciąg zaznaczony jako obecny).
void _captureReasons(
    FumeCaptureResult? r, void Function(FumeReasonCode, FumeLevel) add) {
  if (r == null) {
    add(FumeReasonCode.captureUnverified, FumeLevel.incomplete);
    return;
  }
  switch (r.distanceProblem) {
    case FumeCaptureProblem.distanceTooFar:
      add(FumeReasonCode.captureDistanceTooFar, FumeLevel.stop);
    case FumeCaptureProblem.distanceInvalid:
      add(FumeReasonCode.captureDistanceInvalid, FumeLevel.incomplete);
    default:
      break;
  }
  if (r.isSlot) {
    add(FumeReasonCode.captureOutOfRange, FumeLevel.caution);
    return;
  }
  final tooLow = r.reachState == FumeReachState.tooLowFlow;
  if (tooLow || r.flowSufficient == false) {
    add(FumeReasonCode.captureInsufficient, FumeLevel.stop);
    return;
  }
  if (r.flowM3s == null) {
    // Jest odległość (albo błędna), brak wydajności.
    add(FumeReasonCode.captureUnverified, FumeLevel.incomplete);
    return;
  }
  if (r.distanceMissing) {
    add(FumeReasonCode.captureDistanceMissing, FumeLevel.incomplete);
    return;
  }
  if (r.distanceWithinValidity == false) {
    add(FumeReasonCode.captureOutOfRange, FumeLevel.caution);
  }
}
