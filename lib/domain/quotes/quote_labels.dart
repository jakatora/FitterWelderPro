/// Opisy pozycji wyceny — jedno źródło dla ekranu, PDF i tekstu do
/// wysłania. Czysty Dart (język wybiera wywołujący).
library;

import 'quote_calculator.dart';
import 'weld_geometry.dart';
import 'weld_quote.dart';

String jointKindLabel(JointKind k, {required bool en}) => switch (k) {
      JointKind.pipeButt => en ? 'Pipe butt weld' : 'Spoina doczołowa rury',
      JointKind.pipeFillet => en
          ? 'Fillet on pipe (socket / slip-on)'
          : 'Pachwina na rurze (mufa, kołnierz nasuwany)',
      JointKind.branch => en ? 'Set-on branch' : 'Króciec nasadzany',
      JointKind.plateButt => en ? 'Plate butt weld' : 'Blachy doczołowo',
      JointKind.plateFillet => en ? 'Plate fillet weld' : 'Blachy pachwinowo',
    };

/// Krótka nazwa rodzaju (lista, chipy).
String jointKindShort(JointKind k, {required bool en}) => switch (k) {
      JointKind.pipeButt => en ? 'Pipe butt' : 'Doczołowa rury',
      JointKind.pipeFillet => en ? 'Pipe fillet' : 'Pachwina rury',
      JointKind.branch => en ? 'Branch' : 'Króciec',
      JointKind.plateButt => en ? 'Plate butt' : 'Blachy doczołowo',
      JointKind.plateFillet => en ? 'Plate fillet' : 'Blachy pachwinowo',
    };

String _mm(double v) => formatQty(v, decimals: 2);

/// Wymiary pozycji: „DN100 Sch 40 · Ø114,3 × 6,02" / „a = 4 · 2 m".
String jointSizeLabel(QuoteJoint j, {required bool en}) {
  final size = j.sizeLabel.trim();
  final dims = switch (j.kind) {
    JointKind.pipeButt => 'Ø${_mm(j.odMm)} × ${_mm(j.wallMm)}',
    JointKind.pipeFillet => 'Ø${_mm(j.odMm)}, a = ${_mm(j.throatMm)}',
    JointKind.branch => 'Ø${_mm(j.odMm)} × ${_mm(j.wallMm)}'
        '${j.headerOdMm > 0 ? (en ? ' on Ø${_mm(j.headerOdMm)}' : ' na Ø${_mm(j.headerOdMm)}') : ''}',
    JointKind.plateButt =>
      't = ${_mm(j.wallMm)}, ${j.groove.code}, ${_mm(j.lengthM)} m',
    JointKind.plateFillet => 'a = ${_mm(j.throatMm)}, ${_mm(j.lengthM)} m',
  };
  return size.isEmpty ? dims : '$size · $dims';
}

/// Pełny opis pozycji do oferty.
String jointTitle(QuoteJoint j, {required bool en}) {
  final base = '${jointKindLabel(j.kind, en: en)} ${jointSizeLabel(j, en: en)}';
  final label = j.label.trim();
  return label.isEmpty ? base : '$base — $label';
}

/// Komunikat dla problemu z pozycją.
String jointProblemText(JointProblem p, {required bool en}) => switch (p) {
      JointProblem.count =>
        en ? 'Count must be at least 1' : 'Liczba spoin co najmniej 1',
      JointProblem.od =>
        en ? 'Enter the outside diameter' : 'Podaj średnicę zewnętrzną',
      JointProblem.wall => en
          ? 'Enter the wall / plate thickness'
          : 'Podaj grubość ścianki / blachy',
      JointProblem.wallVsOd => en
          ? 'Wall is too thick for this diameter'
          : 'Ścianka za gruba jak na tę średnicę',
      JointProblem.throat =>
        en ? 'Enter the fillet throat a' : 'Podaj grubość spoiny a',
      JointProblem.length =>
        en ? 'Enter the weld length' : 'Podaj długość spoiny',
      JointProblem.rootFace => en
          ? 'Root face must be between 0 and the wall'
          : 'Próg między 0 a grubością ścianki',
      JointProblem.gap =>
        en ? 'Gap cannot be negative' : 'Szczelina nie może być ujemna',
      JointProblem.angle => en
          ? 'Groove angle 0–120° (branch bevel 0–80°)'
          : 'Kąt rowka 0–120° (faza króćca 0–80°)',
      JointProblem.prep => en
          ? 'Prep time cannot be negative'
          : 'Czas przygotowania nie może być ujemny',
      JointProblem.outOfRange => en
          ? 'A value is far outside the usual range — typo?'
          : 'Wartość daleko poza zakresem — literówka?',
    };

String costKindLabel(QuoteCostKind k, {required bool en}) => switch (k) {
      QuoteCostKind.weldLabour =>
        en ? 'Welding labour' : 'Robocizna — spawanie',
      QuoteCostKind.prepLabour => en
          ? 'Fit-up labour (prep, fit, tack)'
          : 'Robocizna — przygotowanie i sczepianie',
      QuoteCostKind.filler => en ? 'Filler metal' : 'Spoiwo',
      QuoteCostKind.shieldGas => en ? 'Shielding gas' : 'Gaz osłonowy',
      QuoteCostKind.purgeGas => en ? 'Backing (purge) gas' : 'Gaz formujący',
      QuoteCostKind.flux => en ? 'SAW flux' : 'Topnik SAW',
      QuoteCostKind.energy => en ? 'Electricity' : 'Energia elektryczna',
      QuoteCostKind.ndt => en ? 'NDT' : 'Badania NDT',
      QuoteCostKind.extras => en ? 'Additional items' : 'Pozycje dodatkowe',
    };

/// Godziny jako „3 h 25 min" / „45 min".
String formatHours(double h) {
  if (!h.isFinite || h <= 0) return '0 min';
  final totalMin = (h * 60).round();
  final hh = totalMin ~/ 60, mm = totalMin % 60;
  if (hh == 0) return '$mm min';
  if (mm == 0) return '$hh h';
  return '$hh h $mm min';
}
