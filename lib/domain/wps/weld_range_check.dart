// Kontrola zakresu spoiny — czyste funkcje, bez Fluttera i bez bazy.
//
//  • [checkWeldAgainstWps] — czy parametry spoiny mieszczą się w WPS
//    (proces, grupa materiałowa, grubość, średnica, pozycja, BW/FW, energia
//    liniowa, podgrzewanie, temperatura międzyściegowa).
//  • [checkWelderCoverage] — czy spawacz ma w dniu spawania WAŻNE
//    uprawnienie (data ważności + ciągłość 6-miesięczna), które obejmuje te
//    parametry (proces, grupa, grubość, średnica, pozycja, BW/FW).
//
// Zasada: brak danych ≠ niezgodność. Jeśli spoina nie podaje np. pozycji,
// pozycji nie sprawdzamy (i nie krzyczymy). Jeśli WPS / certyfikat nie
// ogranicza czegoś — nie ma czego sprawdzić. Niezgodność jest tylko tam, gdzie
// po obu stronach są dane i się nie zgadzają.
//
// Ograniczenia (świadome, opisane w raporcie):
//  • zakresy w WPS / certyfikacie wpisuje się jako ZAKRES KWALIFIKACJI
//    (co jest dopuszczone), nie jako parametry próbki — tabel przeliczeń
//    ISO 15614-1 / ISO 9606-1 / ASME QW-451/452 nie odtwarzamy;
//  • pozycje w jednym systemie (ISO 6947 „PF" albo ASME „5G") porównujemy
//    dosłownie; między systemami przez tabelę odpowiedników
//    ([kPositionEquivalents]) — gdy odpowiednik jest niejednoznaczny (5G to
//    PH/PJ wg ISO 6947:2011, a PF/PG w starszym zapisie EN 287), wynik to
//    „nie da się porównać", nigdy fałszywe „poza zakresem";
//  • grubość spoiny porównujemy z zakresem grubości; ISO 9606-1 dla BW mówi
//    o grubości stopiwa s, co przy spoinie jednym procesem jest tym samym;
//  • ograniczenia z próby ISO 9606-1, których pola certyfikatu nie mają
//    (prowadzenie grani, przenoszenie metalu, blacha / rura, grupa FM,
//    odgałęzienia), czytamy z linii `[ISO9606 v1]` w uwagach certyfikatu
//    ([checkIso9606TestLimits]) — porównanie tylko, gdy spoina ma dane.
//
// Jak to wpiąć w dziennik spoin — patrz dokumentacja [checkWeldAgainstWps]
// i lib/services/welder_qualification_service.dart (`checkWeld`).

import '../qualification/certificate_status.dart';
import '../qualification/iso9606_limits.dart';
import '../qualification/qualification_dates.dart';
import '../qualification/weld_process.dart';
import '../qualification/welder_certificate.dart';
import '../../utils/decimal_parse.dart';
import '../welding/heat_input.dart';
import 'wps_record.dart';

/// Parametry jednej spoiny do kontroli. Wszystko opcjonalne — czego nie ma,
/// tego nie sprawdzamy.
class WeldParameters {
  /// Grubość ścianki / blachy (mm).
  final double? thicknessMm;

  /// Średnica zewnętrzna rury (mm); `null` dla blachy.
  final double? outsideDiameterMm;

  /// Grupa materiałowa: ISO/TR 15608 („8.1") albo P-No („P8"); złącze
  /// różnoimienne jako „1 + 8.1".
  final String? materialGroup;

  /// Proces: numer ISO 4063 („141") albo nazwa („TIG").
  final String? process;

  /// Pozycja spawania („PF", „PC", „5G").
  final String? position;

  final WeldJointKind? jointKind;

  /// Zmierzona / policzona energia liniowa (kJ/mm) i konwencja, w której ją
  /// policzono.
  final double? heatInputKjMm;
  final HeatInputStandard? heatInputMethod;

  /// Surowe parametry łuku — gdy są, energię liczymy od razu w konwencji WPS
  /// (to omija problem różnych konwencji).
  final double? volts;
  final double? amps;
  final double? travelMmPerMin;

  final double? preheatC;
  final double? interpassC;

  // ---- Do ograniczeń z próby ISO 9606-1 (linia `[ISO9606 v1]` w uwagach
  // certyfikatu — patrz qualification/iso9606_limits.dart). `null` = spoina
  // nie ma tej informacji → „nie da się porównać”, nigdy „poza zakresem”.

  /// Prowadzenie grani spoiny czołowej (ss nb, ss mb, bs, …).
  final RootCondition? root;

  /// Przenoszenie metalu (131 / 135 / 138): `true` zwarciowe (dip), `false`
  /// inne (natryskowe, pulsujące, kroplowe).
  final bool? dipTransfer;

  /// Wyrób: blacha (P) albo rura (T).
  final WeldProductForm? productForm;

  /// Grupa spoiwa wg ISO 9606-1 tab. 2 (`'FM1'`…`'FM6'`).
  final String? fillerGroup;

  /// Spoina odgałęzienia (BR).
  final bool? branch;

  const WeldParameters({
    this.thicknessMm,
    this.outsideDiameterMm,
    this.materialGroup,
    this.process,
    this.position,
    this.jointKind,
    this.heatInputKjMm,
    this.heatInputMethod,
    this.volts,
    this.amps,
    this.travelMmPerMin,
    this.preheatC,
    this.interpassC,
    this.root,
    this.dipTransfer,
    this.productForm,
    this.fillerGroup,
    this.branch,
  });

  /// Liczba z tekstu dziennika („60,3", „2.0 mm") albo `null`.
  static double? parseNumber(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(raw);
    if (m == null) return null;
    return parseDecimal(m.group(0));
  }
}

/// Czego dotyczy niezgodność.
enum WeldCheckField {
  process,
  materialGroup,
  thickness,
  diameter,
  position,
  jointKind,
  heatInput,
  preheat,
  interpass,

  /// Data ważności uprawnienia (albo egzamin po dacie spoiny).
  validity,

  /// Ciągłość 6-miesięczna uprawnienia.
  continuity,

  // ---- Ograniczenia z próby ISO 9606-1 (linia `[ISO9606 v1]` w uwagach).

  /// Prowadzenie grani (tab. 11).
  rootBacking,

  /// Przenoszenie metalu (§5.2).
  metalTransfer,

  /// Blacha / rura (§5.3).
  productForm,

  /// Grupa spoiwa FM (tab. 3).
  fillerGroup,

  /// Odgałęzienie (§5.4).
  branch,

  /// Ograniczeń z próby nie da się porównać (brak danych spoiny albo
  /// uszkodzona linia w uwagach).
  testLimits,
}

enum RangeIssueSeverity {
  /// Poza zakresem — spoina niezgodna z WPS / nieobjęta uprawnieniem.
  outOfRange,

  /// Nie da się porównać (np. energia liniowa w innej konwencji niż WPS,
  /// błędny zakres w WPS). Do wyjaśnienia, nie do odrzucenia.
  cannotCompare,
}

String _fmt(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _range(double? min, double? max, String unit) {
  if (min != null && max != null) return '${_fmt(min)}–${_fmt(max)} $unit';
  if (min != null) return '≥ ${_fmt(min)} $unit';
  if (max != null) return '≤ ${_fmt(max)} $unit';
  return '—';
}

class RangeIssue {
  final WeldCheckField field;
  final RangeIssueSeverity severity;

  /// Co dopuszcza WPS / certyfikat (tekst do wyświetlenia).
  final String allowed;

  /// Co ma spoina.
  final String actual;

  /// Powód / podstawa do dopisania za komunikatem (np. punkt normy);
  /// `null` = bez dopisku.
  final String? reasonPl;
  final String? reasonEn;

  const RangeIssue({
    required this.field,
    required this.allowed,
    required this.actual,
    this.severity = RangeIssueSeverity.outOfRange,
    this.reasonPl,
    this.reasonEn,
  });

  String get _namePl => switch (field) {
        WeldCheckField.process => 'Proces',
        WeldCheckField.materialGroup => 'Grupa materiałowa',
        WeldCheckField.thickness => 'Grubość',
        WeldCheckField.diameter => 'Średnica',
        WeldCheckField.position => 'Pozycja',
        WeldCheckField.jointKind => 'Rodzaj spoiny',
        WeldCheckField.heatInput => 'Energia liniowa',
        WeldCheckField.preheat => 'Podgrzewanie wstępne',
        WeldCheckField.interpass => 'Temperatura międzyściegowa',
        WeldCheckField.validity => 'Ważność uprawnienia',
        WeldCheckField.continuity => 'Ciągłość 6 mies.',
        WeldCheckField.rootBacking => 'Prowadzenie grani',
        WeldCheckField.metalTransfer => 'Przenoszenie metalu',
        WeldCheckField.productForm => 'Wyrób (P blacha / T rura)',
        WeldCheckField.fillerGroup => 'Grupa spoiwa',
        WeldCheckField.branch => 'Odgałęzienie',
        WeldCheckField.testLimits => 'Ograniczenia z próby',
      };

  String get _nameEn => switch (field) {
        WeldCheckField.process => 'Process',
        WeldCheckField.materialGroup => 'Material group',
        WeldCheckField.thickness => 'Thickness',
        WeldCheckField.diameter => 'Diameter',
        WeldCheckField.position => 'Position',
        WeldCheckField.jointKind => 'Weld type',
        WeldCheckField.heatInput => 'Heat input',
        WeldCheckField.preheat => 'Preheat',
        WeldCheckField.interpass => 'Interpass temperature',
        WeldCheckField.validity => 'Qualification validity',
        WeldCheckField.continuity => '6-month continuity',
        WeldCheckField.rootBacking => 'Root / backing',
        WeldCheckField.metalTransfer => 'Metal transfer',
        WeldCheckField.productForm => 'Product (P plate / T pipe)',
        WeldCheckField.fillerGroup => 'Filler group',
        WeldCheckField.branch => 'Branch joint',
        WeldCheckField.testLimits => 'Test piece limitations',
      };

  String get messagePl => (severity == RangeIssueSeverity.outOfRange
          ? '$_namePl: $actual — poza zakresem ($allowed).'
          : '$_namePl: nie da się porównać — $actual ($allowed).') +
      (reasonPl == null ? '' : ' $reasonPl');

  String get messageEn => (severity == RangeIssueSeverity.outOfRange
          ? '$_nameEn: $actual — out of range ($allowed).'
          : '$_nameEn: cannot compare — $actual ($allowed).') +
      (reasonEn == null ? '' : ' $reasonEn');

  @override
  String toString() => 'RangeIssue(${field.name}: $actual vs $allowed)';
}

// ─── Normalizacja tokenów ───────────────────────────────────────────────────

final RegExp _kPNumber =
    RegExp(r'^P\s*[-.]?\s*(?:NO|NR|NUMBER)?\s*[.:]?\s*[-]?\s*(\d.*)$');
final RegExp _kGroupPrefix =
    RegExp(r'^(?:GRUPA|GROUP|GR)\s*[.:]?\s*', caseSensitive: false);

/// „P-No. 8" → „P8"; „Grupa 8.1" → „8.1"; „ 8.1. " → „8.1".
String normalizeMaterialGroupToken(String raw) {
  var t = raw.trim().toUpperCase().replaceFirst(_kGroupPrefix, '');
  final p = _kPNumber.firstMatch(t);
  if (p != null) t = 'P${p.group(1)!}';
  t = t.replaceAll(RegExp(r'\s+'), '');
  while (t.endsWith('.')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// „1 + 8.1" → „1+8.1" (posortowane, bez duplikatów: „8.1 + 8.1" → „8.1").
String normalizeMaterialCombination(String raw) {
  final parts = raw
      .split('+')
      .map(normalizeMaterialGroupToken)
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return parts.join('+');
}

/// Dopuszczone grupy / kombinacje z pola WPS / certyfikatu („8.1, 8.2;
/// 1 + 8.1").
Set<String> allowedMaterialCombinations(String raw) => raw
    .split(RegExp(r'[,;/]'))
    .map(normalizeMaterialCombination)
    .where((s) => s.isNotEmpty)
    .toSet();

const Set<String> _kAllPositions = <String>{
  'ALL',
  'WSZYSTKIE',
  'WSZYSTKO',
  '*',
};

/// Pozycje z tekstu („PA, PC / PF" → {PA, PC, PF}). Wielkość liter i spacje
/// bez znaczenia; „H-L045" zostaje całością.
Set<String> positionTokens(String? raw) {
  if (raw == null) return <String>{};
  return raw
      .toUpperCase()
      .split(RegExp(r'[,;/+\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
}

bool _allPositions(Set<String> tokens) => tokens.any(_kAllPositions.contains);

/// Odpowiedniki pozycji w drugim systemie: ASME IX QW-461 (1G–6G, 1F–5F,
/// 2FR) ↔ EN ISO 6947 (PA–PJ, H-L045, J-L045).
///
/// Rura nieobracana poziomo (5G / 5F) to wg ISO 6947:2011 PH (w górę) albo PJ
/// (w dół), ale w dokumentach wg EN 287 / ISO 6947:1993 zapisywana jako PF /
/// PG — stąd kilka kandydatów. Pozycja pokrywa się z zakresem po drugiej
/// stronie tylko wtedy, gdy WSZYSCY kandydaci są w zakresie; gdy tylko
/// część — nie da się porównać.
const Map<String, Set<String>> kPositionEquivalents = <String, Set<String>>{
  // ASME → ISO 6947
  '1G': {'PA'},
  '2G': {'PC'},
  '3G': {'PF', 'PG'},
  '4G': {'PE'},
  '5G': {'PH', 'PJ', 'PF', 'PG'},
  '6G': {'H-L045', 'J-L045'},
  '1F': {'PA'},
  '2F': {'PB'},
  '2FR': {'PB'},
  '3F': {'PF', 'PG'},
  '4F': {'PD'},
  '5F': {'PH', 'PJ', 'PF', 'PG'},
  // ISO 6947 → ASME
  'PA': {'1G', '1F'},
  'PB': {'2F', '2FR'},
  'PC': {'2G'},
  'PD': {'4F'},
  'PE': {'4G'},
  'PF': {'3G', '3F', '5G', '5F'},
  'PG': {'3G', '3F', '5G', '5F'},
  'PH': {'5G', '5F'},
  'PJ': {'5G', '5F'},
  'H-L045': {'6G'},
  'J-L045': {'6G'},
};

/// Wynik porównania jednej pozycji spoiny z zakresem.
enum PositionMatch { covered, outOfRange, cannotCompare }

/// Czy pozycja [weldToken] mieści się w zakresie [allowed] (tokeny po
/// [positionTokens], bez „wszystkie").
PositionMatch matchPosition(String weldToken, Set<String> allowed) {
  if (allowed.contains(weldToken)) return PositionMatch.covered;
  final candidates = kPositionEquivalents[weldToken];
  // Nieznane oznaczenie — nie zgadujemy.
  if (candidates == null) return PositionMatch.cannotCompare;
  final hits = candidates.where(allowed.contains).length;
  if (hits == 0) return PositionMatch.outOfRange;
  if (hits == candidates.length) return PositionMatch.covered;
  return PositionMatch.cannotCompare;
}

bool _outside(double value, double? min, double? max) {
  const eps = 1e-9;
  if (min != null && value < min - eps) return true;
  if (max != null && value > max + eps) return true;
  return false;
}

double? _efficiencyFor(Set<WeldProcessFamily> families) {
  if (families.length != 1) return null;
  return switch (families.single) {
    WeldProcessFamily.smaw => WeldingProcess.smaw.thermalEfficiency,
    WeldProcessFamily.gmaw => WeldingProcess.gmaw.thermalEfficiency,
    WeldProcessFamily.fcaw => WeldingProcess.fcawG.thermalEfficiency,
    WeldProcessFamily.gtaw => WeldingProcess.gtaw.thermalEfficiency,
    WeldProcessFamily.saw => WeldingProcess.saw.thermalEfficiency,
    // EN 1011-1 tab. 1: plazma k = 0,6 (jak TIG).
    WeldProcessFamily.paw => 0.6,
    WeldProcessFamily.ofw => null,
  };
}

/// Etykieta konwencji bez słów w żadnym języku — tekst trafia do komunikatu
/// PL i EN.
String _methodLabel(HeatInputStandard m) => switch (m) {
      HeatInputStandard.en1011 => 'EN 1011-1 (k)',
      HeatInputStandard.asmeIx => 'ASME IX QW-409.1',
    };

// ─── Wspólne kontrole zakresu (WPS i certyfikat) ────────────────────────────

void _checkScope({
  required WeldParameters weld,
  required String processes,
  required String materialGroup,
  required double? thicknessMin,
  required double? thicknessMax,
  required double? diameterMin,
  required double? diameterMax,
  required String positions,
  required Set<WeldJointKind> jointKinds,
  required List<RangeIssue> out,
  Map<int, Set<int>> mutualProcesses = const <int, Set<int>>{},
}) {
  if (matchProcess(weld.process, processes, mutual: mutualProcesses) ==
      ProcessMatch.notCovered) {
    out.add(RangeIssue(
      field: WeldCheckField.process,
      allowed: processes.trim(),
      actual: weld.process!.trim(),
    ));
  }

  final group = weld.materialGroup?.trim() ?? '';
  final allowedGroups = allowedMaterialCombinations(materialGroup);
  if (group.isNotEmpty && allowedGroups.isNotEmpty) {
    final normalized = normalizeMaterialCombination(group);
    if (normalized.isNotEmpty && !allowedGroups.contains(normalized)) {
      out.add(RangeIssue(
        field: WeldCheckField.materialGroup,
        allowed: materialGroup.trim(),
        actual: group,
      ));
    }
  }

  final t = weld.thicknessMm;
  if (t != null && _outside(t, thicknessMin, thicknessMax)) {
    out.add(RangeIssue(
      field: WeldCheckField.thickness,
      allowed: _range(thicknessMin, thicknessMax, 'mm'),
      actual: '${_fmt(t)} mm',
    ));
  }

  final d = weld.outsideDiameterMm;
  if (d != null && _outside(d, diameterMin, diameterMax)) {
    out.add(RangeIssue(
      field: WeldCheckField.diameter,
      allowed: _range(diameterMin, diameterMax, 'mm'),
      actual: '${_fmt(d)} mm',
    ));
  }

  final weldPositions = positionTokens(weld.position);
  final allowedPositions = positionTokens(positions);
  if (weldPositions.isNotEmpty &&
      allowedPositions.isNotEmpty &&
      !_allPositions(allowedPositions)) {
    final results = [
      for (final p in weldPositions) matchPosition(p, allowedPositions),
    ];
    if (results.contains(PositionMatch.outOfRange)) {
      out.add(RangeIssue(
        field: WeldCheckField.position,
        allowed: positions.trim(),
        actual: weld.position!.trim(),
      ));
    } else if (results.contains(PositionMatch.cannotCompare)) {
      final hints = <String>{
        for (final p in weldPositions) ...?kPositionEquivalents[p],
      };
      out.add(RangeIssue(
        field: WeldCheckField.position,
        severity: RangeIssueSeverity.cannotCompare,
        allowed: '${positions.trim()}; ISO 6947 ↔ ASME',
        actual: hints.isEmpty
            ? weld.position!.trim()
            : '${weld.position!.trim()} ≈ ${hints.join('/')}',
      ));
    }
  }

  final kind = weld.jointKind;
  if (kind != null && jointKinds.isNotEmpty && !jointKinds.contains(kind)) {
    out.add(RangeIssue(
      field: WeldCheckField.jointKind,
      allowed: encodeJointKinds(jointKinds),
      actual: kind.code,
    ));
  }
}

/// Niezgodności spoiny [weld] z [wps]; pusta lista = spoina w zakresie WPS
/// (w granicach tego, co obie strony podały).
///
/// Dla dziennika spoin (agent dziennika): przy zapisie spoiny z wybraną WPS
/// zbuduj [WeldParameters] z pól wpisu (t, OD przez
/// [WeldParameters.parseNumber], metoda → `process`) i pokaż
/// [RangeIssue.messagePl] / [RangeIssue.messageEn] jako ostrzeżenie. Pozycje
/// z [RangeIssueSeverity.cannotCompare] to prośba o wyjaśnienie, nie błąd.
List<RangeIssue> checkWeldAgainstWps(WeldParameters weld, WpsRecord wps) {
  final out = <RangeIssue>[];
  _checkScope(
    weld: weld,
    processes: wps.processes,
    materialGroup: wps.materialGroup,
    thicknessMin: wps.thicknessMinMm,
    thicknessMax: wps.thicknessMaxMm,
    diameterMin: wps.diameterMinMm,
    diameterMax: wps.diameterMaxMm,
    positions: wps.positions,
    jointKinds: wps.jointKinds,
    out: out,
  );

  // ---- Energia liniowa — zawsze w konwencji WPS.
  final hiMin = wps.heatInputMinKjMm;
  final hiMax = wps.heatInputMaxKjMm;
  if (hiMin != null || hiMax != null) {
    final allowed =
        '${_range(hiMin, hiMax, 'kJ/mm')}, ${_methodLabel(wps.heatInputMethod)}';
    double? value;
    var rawButNoEfficiency = false;
    final volts = weld.volts;
    final amps = weld.amps;
    final travel = weld.travelMmPerMin;
    if (volts != null && amps != null && travel != null) {
      final families = processFamiliesIn(weld.process).isNotEmpty
          ? processFamiliesIn(weld.process)
          : processFamiliesIn(wps.processes);
      final k = _efficiencyFor(families);
      if (wps.heatInputMethod == HeatInputStandard.asmeIx || k != null) {
        // ASME liczy bez sprawności — k jest wtedy ignorowane.
        value = heatInputKJPerMm(
          volts: volts,
          amps: amps,
          travelMmPerMin: travel,
          standard: wps.heatInputMethod,
          efficiency: k ?? 1.0,
        );
      } else {
        // EN 1011-1 potrzebuje k, a proces jest nieznany albo mieszany.
        rawButNoEfficiency = true;
      }
    }
    if (value == null && weld.heatInputKjMm != null) {
      if (weld.heatInputMethod == wps.heatInputMethod) {
        value = weld.heatInputKjMm;
      } else {
        final method = weld.heatInputMethod;
        out.add(RangeIssue(
          field: WeldCheckField.heatInput,
          severity: RangeIssueSeverity.cannotCompare,
          allowed: allowed,
          actual: '${_fmt(weld.heatInputKjMm!)} kJ/mm, '
              '${method == null ? '?' : _methodLabel(method)}',
        ));
        rawButNoEfficiency = false;
      }
    }
    if (value == null && rawButNoEfficiency) {
      out.add(RangeIssue(
        field: WeldCheckField.heatInput,
        severity: RangeIssueSeverity.cannotCompare,
        allowed: allowed,
        actual: 'k = ? (${weld.process?.trim().isNotEmpty == true ? weld.process!.trim() : wps.processes.trim()})',
      ));
    }
    if (value != null) {
      switch (checkWpsRange(value, min: hiMin, max: hiMax)) {
        case WpsRangeVerdict.belowMin:
        case WpsRangeVerdict.aboveMax:
          out.add(RangeIssue(
            field: WeldCheckField.heatInput,
            allowed: allowed,
            actual: '${_fmt(value)} kJ/mm',
          ));
        case WpsRangeVerdict.invalidRange:
          // Zakres w WPS jest wewnętrznie sprzeczny (min > max) — do poprawy
          // w bibliotece, nie wina spoiny.
          out.add(RangeIssue(
            field: WeldCheckField.heatInput,
            severity: RangeIssueSeverity.cannotCompare,
            allowed: allowed,
            actual: '${_fmt(value)} kJ/mm',
          ));
        case WpsRangeVerdict.inRange:
        case WpsRangeVerdict.notSet:
          break;
      }
    }
  }

  // ---- Podgrzewanie: nie mniej niż minimum z WPS.
  final preheat = weld.preheatC;
  final preheatMin = wps.preheatMinC;
  if (preheat != null && preheatMin != null && preheat < preheatMin - 1e-9) {
    out.add(RangeIssue(
      field: WeldCheckField.preheat,
      allowed: '≥ ${_fmt(preheatMin)} °C',
      actual: '${_fmt(preheat)} °C',
    ));
  }

  // ---- Międzyściegowa: nie więcej niż maksimum z WPS.
  final interpass = weld.interpassC;
  final interpassMax = wps.interpassMaxC;
  if (interpass != null &&
      interpassMax != null &&
      interpass > interpassMax + 1e-9) {
    out.add(RangeIssue(
      field: WeldCheckField.interpass,
      allowed: '≤ ${_fmt(interpassMax)} °C',
      actual: '${_fmt(interpass)} °C',
    ));
  }
  return out;
}

// ─── Ograniczenia z próby ISO 9606-1 (linia w uwagach certyfikatu) ─────────

/// Porównuje spoinę [weld] z ograniczeniami z linii `[ISO9606 v1]` w uwagach
/// certyfikatu [notes] (zapisuje ją „Zakres uprawnień z próbki”; format
/// w qualification/iso9606_limits.dart) i dopisuje niezgodności do [out].
///
///  • brak linii → nic (certyfikat bez ograniczeń z próby);
///  • linia uszkodzona / z nowszej wersji → jedno „nie da się porównać”;
///  • ograniczenie naruszone, gdy spoina MA dane → „poza zakresem” z powodem
///    (spoina ss nb przy „root=mb,bs”, blacha przy „plates=0”, spoiwo FM5
///    przy „fm=FM1,FM2”, zwarciowe przy „dip=0”, odgałęzienie przy
///    „branch=0”);
///  • spoina BEZ danych do ograniczenia, które jej dotyczy → jedno zbiorcze
///    „nie da się porównać” z listą brakujących danych — nigdy fałszywe
///    „poza zakresem”.
/// `nofiller` i `proc2` nie są tu porównywane: 142 z próby ze spoiwem
/// i proces wypełnienia nie trafiają do procesów rejestru, więc taką spoinę
/// zatrzymuje już porównanie procesu.
void checkIso9606TestLimits(
    WeldParameters weld, String notes, List<RangeIssue> out) {
  final parsed = parseIso9606Limits(notes);
  switch (parsed.status) {
    case Iso9606LimitsStatus.absent:
      return;
    case Iso9606LimitsStatus.damaged:
      out.add(const RangeIssue(
        field: WeldCheckField.testLimits,
        severity: RangeIssueSeverity.cannotCompare,
        allowed: kIso9606LimitsTag,
        actual: '[ISO9606 …]',
        reasonPl: 'Linia ograniczeń w uwagach certyfikatu jest uszkodzona '
            'albo z nowszej wersji — ograniczeń z próby nie sprawdzono.',
        reasonEn: 'The limitations line in the certificate notes is damaged '
            'or from a newer version — the test piece limitations were not '
            'checked.',
      ));
      return;
    case Iso9606LimitsStatus.ok:
      break;
  }
  final l = parsed.limits!;
  final families = processFamiliesIn(weld.process);
  final kind = weld.jointKind;
  final missing = <String>[];
  final missingLimits = <String>[];
  void unknown(String what, String limit) {
    missing.add(what);
    missingLimits.add(limit);
  }

  // Prowadzenie grani (tab. 11) — tylko spoiny czołowe.
  final root = l.root;
  if (root != null &&
      root.length < RootCondition.values.length &&
      kind != WeldJointKind.fw) {
    final allowed = [
      for (final r in RootCondition.values)
        if (root.contains(r)) r,
    ];
    final r = weld.root;
    if (r == null) {
      unknown('root', 'root=${allowed.map((r) => r.code).join(',')}');
    } else if (!root.contains(r)) {
      out.add(RangeIssue(
        field: WeldCheckField.rootBacking,
        allowed: allowed.map((r) => r.label).join(', '),
        actual: r.label,
        reasonPl: 'Takie prowadzenie grani obejmuje próba (ISO 9606-1 '
            'tab. 11).',
        reasonEn: 'These root conditions are covered by the test (ISO 9606-1 '
            'Table 11).',
      ));
    }
  }

  // Przenoszenie metalu (§5.2) — dotyczy MIG/MAG (131 / 135 / 138).
  if (l.dip == false &&
      (families.isEmpty || families.contains(WeldProcessFamily.gmaw))) {
    final dip = weld.dipTransfer;
    if (dip == null) {
      unknown('dip', 'dip=0');
    } else if (dip) {
      out.add(const RangeIssue(
        field: WeldCheckField.metalTransfer,
        allowed: '≠ dip',
        actual: 'dip',
        reasonPl: 'Próba bez zwarciowego przenoszenia metalu go nie obejmuje '
            '(ISO 9606-1 §5.2).',
        reasonEn: 'A test without dip (short-circuit) transfer does not cover '
            'it (ISO 9606-1 cl. 5.2).',
      ));
    }
  }

  // Blacha / rura (§5.3 a).
  if (l.plates == false) {
    final p = weld.productForm;
    if (p == null) {
      unknown('P/T', 'plates=0');
    } else if (p == WeldProductForm.plate) {
      out.add(const RangeIssue(
        field: WeldCheckField.productForm,
        allowed: 'T',
        actual: 'P',
        reasonPl: 'Próba na rurze D ≤ 25 mm nie obejmuje blach (ISO 9606-1 '
            '§5.3 a).',
        reasonEn: 'A test on pipe D ≤ 25 mm does not cover plates (ISO 9606-1 '
            'cl. 5.3 a).',
      ));
    }
  }

  // Grupa spoiwa (tab. 3).
  final fm = l.fm;
  if (fm != null) {
    final allowed = (fm.toList()..sort()).join(', ');
    final g = weld.fillerGroup?.trim().toUpperCase();
    if (g == null || g.isEmpty) {
      unknown('FM', 'fm=${allowed.replaceAll(' ', '')}');
    } else if (!fm.contains(g)) {
      out.add(RangeIssue(
        field: WeldCheckField.fillerGroup,
        allowed: allowed,
        actual: g,
        reasonPl: 'Grupy spoiw objęte próbą (ISO 9606-1 tab. 3).',
        reasonEn: 'Filler groups covered by the test (ISO 9606-1 Table 3).',
      ));
    }
  }

  // Odgałęzienia (§5.4 a, c).
  final branch = l.branch;
  if (branch != null) {
    final br = weld.branch;
    if (br == null) {
      unknown('BR', 'branch=$branch');
    } else if (br) {
      if (branch == 0) {
        out.add(const RangeIssue(
          field: WeldCheckField.branch,
          allowed: 'branch=0',
          actual: 'BR',
          reasonPl: 'Próba czołowa na blasze nie obejmuje odgałęzień '
              '(ISO 9606-1 §5.4 a, c).',
          reasonEn: 'A butt test on plate does not cover branch joints '
              '(ISO 9606-1 cl. 5.4 a, c).',
        ));
      } else {
        // Kąta odgałęzienia spoina nie podaje.
        unknown('BR ≥ 60°', 'branch=60');
      }
    }
  }

  // Technika spoin pachwinowych (tab. 12) i kierunek 311 (§5.9) — spoina
  // nie ma takich pól.
  final layers = l.layers;
  if (layers != null && !layers.contains('ml') && kind != WeldJointKind.bw) {
    unknown('sl/ml', 'layers=sl');
  }
  final dir = l.direction;
  if (dir != null &&
      (families.isEmpty || families.contains(WeldProcessFamily.ofw))) {
    unknown('lw/rw', 'dir=$dir');
  }

  if (missing.isNotEmpty) {
    out.add(RangeIssue(
      field: WeldCheckField.testLimits,
      severity: RangeIssueSeverity.cannotCompare,
      allowed: missingLimits.join('; '),
      actual: missing.join(', '),
      reasonPl: 'Spoina nie ma tych danych — sprawdź z blokiem OGRANICZENIA '
          'w uwagach certyfikatu.',
      reasonEn: 'The weld has no such data — check against the LIMITATIONS '
          'block in the certificate notes.',
    ));
  }
}

// ─── Uprawnienia spawacza ───────────────────────────────────────────────────

/// Jeden certyfikat oceniony dla konkretnej spoiny.
class CertificateCoverage {
  /// Status certyfikatu w dniu spawania.
  final CertificateEvaluation evaluation;

  /// Niezgodności: zakres (proces, grupa, t, D, pozycja, BW/FW) oraz ważność
  /// i ciągłość w dniu spawania.
  final List<RangeIssue> issues;

  const CertificateCoverage(this.evaluation, this.issues);

  WelderCertificate get certificate => evaluation.certificate;

  bool get covers =>
      issues.every((i) => i.severity != RangeIssueSeverity.outOfRange);
}

/// Wynik sprawdzenia uprawnień spawacza dla spoiny.
class WelderCoverage {
  final List<CertificateCoverage> certificates;

  const WelderCoverage(this.certificates);

  /// Spawacz nie ma w rejestrze żadnego certyfikatu.
  bool get noCertificates => certificates.isEmpty;

  /// Co najmniej jeden certyfikat obejmuje spoinę i był ważny w dniu
  /// spawania.
  bool get covered => certificates.any((c) => c.covers);

  /// Certyfikat, który obejmuje spoinę (pierwszy), albo `null`.
  CertificateCoverage? get coveringCertificate {
    for (final c in certificates) {
      if (c.covers) return c;
    }
    return null;
  }

  /// Certyfikat z najmniejszą liczbą niezgodności — do pokazania, czego
  /// brakuje, gdy żaden nie obejmuje spoiny.
  CertificateCoverage? get closestCertificate {
    if (certificates.isEmpty) return null;
    final sorted = [...certificates]
      ..sort((a, b) => a.issues.length.compareTo(b.issues.length));
    return sorted.first;
  }
}

/// Czy spawacz ma w dniu [weldDate] ważne uprawnienie obejmujące [weld].
///
/// [journal] — spoiny TEGO spawacza z dziennika (patrz
/// `journalWeldsFromRows`); liczą się do ciągłości ASME tylko te do
/// [weldDate] włącznie.
WelderCoverage checkWelderCoverage({
  required WeldParameters weld,
  required DateTime weldDate,
  required Iterable<WelderCertificate> certificates,
  Iterable<JournalWeld> journal = const <JournalWeld>[],
}) {
  final day = dateOnly(weldDate);
  final journalList = journal.toList(growable: false);
  final out = <CertificateCoverage>[];
  for (final c in certificates) {
    final evaluation = evaluateCertificate(
      c,
      asOf: day,
      journalWelds: journalWeldsFor(c, journalList),
    );
    final issues = <RangeIssue>[];
    final test = c.testDate;
    // Daty bez słów („≥ 2026-01-10" = od, „≤ 2026-09-10" = do), bo tekst
    // trafia do komunikatu PL i EN.
    if (test != null && dateOnly(test).isAfter(day)) {
      issues.add(RangeIssue(
        field: WeldCheckField.validity,
        allowed: '≥ ${formatIsoDate(test)}',
        actual: formatIsoDate(day),
      ));
    }
    if (evaluation.state == QualificationState.expired) {
      issues.add(RangeIssue(
        field: WeldCheckField.validity,
        allowed: '≤ ${formatIsoDate(c.expiryDate!)}',
        actual: formatIsoDate(day),
      ));
    } else if (evaluation.state == QualificationState.lapsed) {
      issues.add(RangeIssue(
        field: WeldCheckField.continuity,
        allowed: '≤ ${formatIsoDate(evaluation.continuityDeadline!)}',
        actual: formatIsoDate(day),
      ));
    }
    _checkScope(
      weld: weld,
      processes: c.processes,
      materialGroup: c.materialGroup,
      thicknessMin: c.thicknessMinMm,
      thicknessMax: c.thicknessMaxMm,
      diameterMin: c.diameterMinMm,
      diameterMax: c.diameterMaxMm,
      positions: c.positions,
      jointKinds: c.jointKinds,
      out: issues,
      mutualProcesses: c.standard == QualificationStandard.iso9606_1
          ? kIso9606MutualProcesses
          : const <int, Set<int>>{},
    );
    // Ograniczenia z próby z uwag certyfikatu (tylko gdy jest linia
    // `[ISO9606 v1]`).
    checkIso9606TestLimits(weld, c.notes, issues);
    out.add(CertificateCoverage(evaluation, issues));
  }
  return WelderCoverage(out);
}
