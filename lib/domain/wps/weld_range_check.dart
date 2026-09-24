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
//  • pozycje porównujemy dosłownie w jednym systemie (ISO 6947 „PF" albo
//    ASME „5G") — bez tłumaczenia między systemami;
//  • grubość spoiny porównujemy z zakresem grubości; ISO 9606-1 dla BW mówi
//    o grubości stopiwa s, co przy spoinie jednym procesem jest tym samym.
//
// Jak to wpiąć w dziennik spoin — patrz dokumentacja [checkWeldAgainstWps]
// i lib/services/welder_qualification_service.dart (`checkWeld`).

import '../qualification/certificate_status.dart';
import '../qualification/qualification_dates.dart';
import '../qualification/weld_process.dart';
import '../qualification/welder_certificate.dart';
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
  });

  /// Liczba z tekstu dziennika („60,3", „2.0 mm") albo `null`.
  static double? parseNumber(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(raw);
    if (m == null) return null;
    final v = double.tryParse(m.group(0)!.replaceAll(',', '.'));
    return (v != null && v.isFinite) ? v : null;
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

  const RangeIssue({
    required this.field,
    required this.allowed,
    required this.actual,
    this.severity = RangeIssueSeverity.outOfRange,
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
      };

  String get messagePl => severity == RangeIssueSeverity.outOfRange
      ? '$_namePl: $actual — poza zakresem ($allowed).'
      : '$_namePl: nie da się porównać — $actual ($allowed).';

  String get messageEn => severity == RangeIssueSeverity.outOfRange
      ? '$_nameEn: $actual — out of range ($allowed).'
      : '$_nameEn: cannot compare — $actual ($allowed).';

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
      !_allPositions(allowedPositions) &&
      !weldPositions.every(allowedPositions.contains)) {
    out.add(RangeIssue(
      field: WeldCheckField.position,
      allowed: positions.trim(),
      actual: weld.position!.trim(),
    ));
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
    out.add(CertificateCoverage(evaluation, issues));
  }
  return WelderCoverage(out);
}
