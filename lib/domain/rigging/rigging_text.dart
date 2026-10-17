/// Teksty i liczby modułu „Zawiesia i podwieszanie” (PL/EN).
///
/// Liczby: przecinek dziesiętny i spacja tysięcy po polsku, kropka
/// i przecinek tysięcy po angielsku. Masa pokazywana z zaokrąglenia
/// W GÓRĘ, nośność z zaokrąglenia W DÓŁ — formatowanie dostaje już
/// zaokrąglone kilogramy (rigging_calc.dart), więc tekst nie „poprawia”
/// werdyktu.
///
/// Czysty Dart.
library;

import '../fitter/fitter_calcs.dart' show PipeMaterial;
import 'rigging_calc.dart';
import 'rigging_checklist.dart';

/// Liczba bez zbędnych zer, z separatorem tysięcy.
String rigNum(double v, {int decimals = 2, required bool en}) {
  if (!v.isFinite) return '—';
  final neg = v < 0;
  var s = v.abs().toStringAsFixed(decimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(en ? ',' : ' ');
    buf.write(intPart[i]);
  }
  final frac = parts.length > 1 ? '${en ? '.' : ','}${parts[1]}' : '';
  return '${neg ? '−' : ''}$buf$frac';
}

/// „1 600 kg”.
String kgText(num kg, {required bool en}) =>
    '${rigNum(kg.toDouble(), decimals: 0, en: en)} kg';

/// „1,6 t” — kilogramy w tonach (3 miejsca = dokładność 1 kg).
String tText(num kg, {required bool en}) =>
    '${rigNum(kg / 1000, decimals: 3, en: en)} t';

/// Masa w wybranej jednostce, druga w nawiasie: „1,6 t (1 600 kg)”.
String massInUnit(int kg, MassUnit unit, {required bool en}) =>
    unit == MassUnit.t
        ? '${tText(kg, en: en)} (${kgText(kg, en: en)})'
        : '${kgText(kg, en: en)} (${tText(kg, en: en)})';

/// „×1,4”, „×1,0”, „×1,12” — zawsze z miejscem po przecinku, jak w tabelach.
String factorText(double f, {required bool en}) {
  final s = rigNum(f, decimals: 2, en: en);
  final sep = en ? '.' : ',';
  return '×${s.contains(sep) ? s : '$s${sep}0'}';
}

/// „45°”.
String degText(double deg, {required bool en}) =>
    '${rigNum(deg, decimals: 1, en: en)}°';

String unitLabel(MassUnit u) => u == MassUnit.t ? 't' : 'kg';

String slingTypeLabel(SlingType s, {required bool en}) => switch (s) {
      SlingType.webbing =>
        en ? 'Flat webbing sling (polyester)' : 'Pas płaski (poliester)',
      SlingType.roundsling => en ? 'Roundsling' : 'Pas okrągły',
      SlingType.chain => en ? 'Chain sling, grade 8' : 'Łańcuchowe kl. 8',
      SlingType.wireRope => en ? 'Wire rope sling' : 'Linowe stalowe',
    };

String slingTypeStandard(SlingType s) => switch (s) {
      SlingType.webbing => 'EN 1492-1',
      SlingType.roundsling => 'EN 1492-2',
      SlingType.chain => 'EN 818-4 / EN 818-6',
      SlingType.wireRope => 'EN 13414-1 / EN 13414-2',
    };

String hitchModeLabel(HitchMode m, {required bool en}) => switch (m) {
      HitchMode.straight => en ? 'Straight (vertical)' : 'Proste (pionowo)',
      HitchMode.choke => en ? 'Choke hitch' : 'Zadusznik',
      HitchMode.basketParallel =>
        en ? 'Basket, vertical legs' : 'Koszowe równoległe',
      HitchMode.basketAngled => en ? 'Basket, angled' : 'Koszowe pod kątem',
      HitchMode.twoLeg => en ? '2 legs' : '2 cięgna',
      HitchMode.multiLeg => en ? '3–4 legs' : '3–4 cięgna',
    };

String angleBandLabel(AngleBand b, {required bool en}) => switch (b) {
      AngleBand.upTo45 => en ? 'β 0–45° (below 45°)' : 'β 0–45° (poniżej 45°)',
      AngleBand.from45to60 =>
        en ? 'β 45–60° (45° included)' : 'β 45–60° (45° włącznie)',
      AngleBand.over60 => en ? 'β above 60°' : 'β ponad 60°',
    };

String pipeMaterialLabel(PipeMaterial m, {required bool en}) => switch (m) {
      PipeMaterial.cs => en ? 'Carbon steel 7,850' : 'Stal węglowa 7 850',
      PipeMaterial.ss304 => en ? 'SS 304/304L 7,900' : 'Nierdzewna 304 7 900',
      PipeMaterial.ss316 => en ? 'SS 316/316L 8,000' : 'Nierdzewna 316 8 000',
      PipeMaterial.al => en ? 'Aluminium 2,700' : 'Aluminium 2 700',
    };

String pipeProblemText(PipeLoadProblem p, {required bool en}) => switch (p) {
      PipeLoadProblem.od => en
          ? 'Enter the outside diameter (mm)'
          : 'Wpisz średnicę zewnętrzną (mm)',
      PipeLoadProblem.wall => en
          ? 'Enter the wall: > 0 and less than half the OD'
          : 'Wpisz ściankę: > 0 i mniej niż połowa OD',
      PipeLoadProblem.length =>
        en ? 'Enter the length > 0 m' : 'Wpisz długość > 0 m',
      PipeLoadProblem.extra => en
          ? 'Extras: enter ≥ 0 kg or leave empty'
          : 'Dodatki: wpisz ≥ 0 kg albo zostaw puste',
    };

String verdictTitle(RiggingVerdict v, {required bool en}) => switch (v) {
      RiggingVerdict.ok => en
          ? 'OK — the sling can lift the load'
          : 'OK — zawiesie uniesie ładunek',
      RiggingVerdict.overload => en ? 'STOP — overload' : 'STOP — przeciążenie',
      RiggingVerdict.angleNotAllowed => en
          ? 'STOP — more than 60° from vertical: not allowed'
          : 'STOP — ponad 60° od pionu: niedozwolone',
      RiggingVerdict.noLabel => en
          ? 'STOP — no legible label: do not use'
          : 'STOP — brak czytelnej etykiety: nie używać',
      RiggingVerdict.incomplete =>
        en ? 'NO VERDICT — data missing' : 'BRAK WERDYKTU — brakuje danych',
    };

String issueText(RiggingIssue i, {required bool en}) => switch (i) {
      RiggingIssue.massMissing => en ? 'load mass' : 'masa ładunku',
      RiggingIssue.massInvalid => en
          ? 'load mass is not a number > 0'
          : 'masa ładunku nie jest liczbą > 0',
      RiggingIssue.wllMissing => en ? 'WLL from the label' : 'WLL z etykiety',
      RiggingIssue.wllInvalid =>
        en ? 'WLL is not a number > 0' : 'WLL nie jest liczbą > 0',
      RiggingIssue.angleMissing => en
          ? 'leg angle (unknown angle = no verdict)'
          : 'kąt cięgien (kąt nieznany = brak werdyktu)',
      RiggingIssue.angleInvalid => en
          ? 'leg angle unreadable (β must be 0–90°, α 0–180°)'
          : 'kąt nieczytelny (β 0–90°, α 0–180°)',
      RiggingIssue.labelUnconfirmed => en
          ? 'label confirmation (present and legible?)'
          : 'potwierdzenie etykiety (jest i czytelna?)',
    };

String readinessTitle(LiftReadiness r, {required bool en}) => switch (r) {
      LiftReadiness.go => en
          ? 'READY TO LIFT — capacity OK and checklist complete'
          : 'MOŻNA PODNOSIĆ — nośność OK i lista kompletna',
      LiftReadiness.stop => en ? 'DO NOT LIFT' : 'NIE PODNOŚ',
      LiftReadiness.notReady => en
          ? 'NOT YET — no verdict or checklist incomplete'
          : 'JESZCZE NIE — brak werdyktu albo lista niekompletna',
    };

String checklistVerdictText(ChecklistStatus s, {required bool en}) {
  final done = s.okCount + s.naCount;
  return switch (s.verdict) {
    ChecklistVerdict.complete => en
        ? 'Checklist complete: $done of ${s.total}, no defects.'
        : 'Lista kompletna: $done z ${s.total}, bez wad.',
    ChecklistVerdict.incomplete => en
        ? 'Checklist incomplete: $done of ${s.total} — an unchecked item is '
            'not OK.'
        : 'Lista niekompletna: $done z ${s.total} — pozycja niezaznaczona to '
            'nie OK.',
    ChecklistVerdict.rejected => s.slingRejected
        ? (en
            ? 'Defects: ${s.defects.length}. Take the sling out of service — '
                'mark it and report it.'
            : 'Wady: ${s.defects.length}. Zawiesie do wycofania — odłóż, '
                'oznacz, zgłoś.')
        : (en
            ? 'Defects: ${s.defects.length}. Do not lift until fixed.'
            : 'Wady: ${s.defects.length}. Nie podnoś, dopóki nie usuniesz.'),
  };
}
