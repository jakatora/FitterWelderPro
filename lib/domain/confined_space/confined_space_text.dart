/// Teksty modułu „Przestrzeń zamknięta”: zastrzeżenie, opis stanu,
/// ostrzeżenia dla spawacza, wiersze danych i protokół tekstowy.
///
/// Czysty Dart — te same wiersze składają tekst i PDF.
library;

import '../hot_work/hot_work_permit.dart' show hotWorkDate;
import 'confined_space_checklist.dart';
import 'confined_space_gas.dart';
import 'confined_space_record.dart';

/// Zastrzeżenie — na ekranie (góra i dół), w tekście i w PDF.
String confinedSpaceDisclaimer({required bool en}) => en
    ? 'Checklist aid only — not a permit. Binding are the law (in Poland '
        'e.g. the general OHS regulation, §§ 85–90 on work in tanks and '
        'confined spaces, the welding OHS regulation and the OEL regulation), '
        'the site procedure and the written permit issued by the employer. '
        'Gas limits, equipment and rescue: always as stated in the permit.'
    : 'Lista pomocnicza — nie zastępuje pisemnego pozwolenia. Wiążą przepisy '
        '(w PL m.in. rozporządzenie w sprawie ogólnych przepisów BHP — '
        '§§ 85–90 o pracach w zbiornikach i przestrzeniach zamkniętych, '
        'rozporządzenie w sprawie BHP przy pracach spawalniczych i NDS), '
        'instrukcja zakładu i pozwolenie wydane przez pracodawcę. Progi '
        'gazów, sprzęt i ratunek — zawsze wg pozwolenia.';

/// Liczba ppm do „≈”: dwa miejsca po przecinku („≈ 4,94 ppm”), bez
/// zbędnych zer.
String _approxPpm(double ppm, {required bool en}) {
  var s = ppm.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return en ? s : s.replaceAll('.', ',');
}

/// Podgląd przeliczenia wartości w mg/m³: „≈ 4,94 ppm” (inne jednostki —
/// `null`).
String? csPpmPreview(CsGas gas, CsQty q, {required bool en}) =>
    q.unit == CsUnit.mgM3
        ? '≈ ${_approxPpm(csCanonical(gas, q), en: en)} ppm'
        : null;

/// Próg do tekstu: „19,5 %”, „10 % DGW”, „20 ppm”, „7 mg/m³ (≈ 4,94 ppm)”.
String formatCsLimit(CsBound b, CsQty q, {required bool en}) {
  final s = formatCsQty(b.gas, q, en: en);
  final preview = csPpmPreview(b.gas, q, en: en);
  return preview == null ? s : '$s ($preview)';
}

/// Zakres tlenu z progów: „19,5–23,5 %” (brak — kreska).
String formatCsO2Range(CsLimits l, {required bool en}) {
  final min = l[CsBound.o2Min];
  final max = l[CsBound.o2Max];
  String n(CsQty? q) => q == null ? '…' : formatCsNumber(q.value, en: en);
  if (min == null && max == null) return '—';
  return '${n(min)}–${n(max)} %';
}

/// Próg gazu do tekstu (dla tlenu — zakres).
String formatCsGasLimit(CsGas gas, CsLimits l, {required bool en}) {
  if (gas == CsGas.o2) return formatCsO2Range(l, en: en);
  final b = csMaxBound(gas)!;
  final q = l[b];
  return q == null ? '—' : '≤ ${formatCsLimit(b, q, en: en)}';
}

/// Próg bez znaku „≤” (do zdań „poniżej 19,5 %”, „powyżej 20 ppm”). Bez
/// progu z pozwolenia — twarda granica z dopiskiem.
String _plainLimit(CsBound b, CsLimits l, {required bool en}) {
  final q = l[b];
  if (q != null) return formatCsLimit(b, q, en: en);
  final hard = formatCsLimit(b, b.hardLimit, en: en);
  return en ? '$hard (hard limit, no permit limit)' : '$hard (granica '
      'twarda, brak progu z pozwolenia)';
}

/// Godzina odczytu do tekstu — z datą, gdy pomiar jest z innego dnia niż
/// [recordDate] („2026-10-16 23:50”).
String csMeasurementTime(CsMeasurement m, String recordDate) {
  final t = m.time.isEmpty ? '—' : m.time;
  final d = hotWorkDate(DateTime.fromMillisecondsSinceEpoch(m.at));
  return d == recordDate ? t : '$d $t';
}

/// Opis jednego zatrzymania (STOP) — dla tlenu osobno za mało / za dużo.
String csStopText(CsGasVerdict v, CsLimits l,
    {required bool en, String? recordDate}) {
  final value = formatCsQty(v.gas, v.value!, en: en);
  final d = v.decisive!;
  final at = recordDate == null ? d.time : csMeasurementTime(d, recordDate);
  final later = v.enteredLater
      ? (en
          ? ' (entered after the ${v.latest.first.time} reading)'
          : ' (wpisany po odczycie z ${v.latest.first.time})')
      : '';
  if (v.gas == CsGas.o2 && v.state == CsReadingState.low) {
    final min = _plainLimit(CsBound.o2Min, l, en: en);
    return en
        ? 'oxygen $value at $at$later is below $min — oxygen deficiency '
            '(argon, CO₂ or nitrogen displace oxygen)'
        : 'tlen $value o $at$later — poniżej $min, niedotlenienie (argon, '
            'CO₂ lub azot wypierają tlen)';
  }
  if (v.gas == CsGas.o2) {
    final max = _plainLimit(CsBound.o2Max, l, en: en);
    return en
        ? 'oxygen $value at $at$later is above $max — oxygen enrichment: '
            'clothing ignites from a spark; find the oxygen leak'
        : 'tlen $value o $at$later — powyżej $max, wzbogacenie tlenem: '
            'odzież zapala się od iskry; szukaj nieszczelności tlenu';
  }
  final max = _plainLimit(csMaxBound(v.gas)!, l, en: en);
  final name = v.gas.label(en: en);
  return en
      ? '$name $value at $at$later — above the $max limit'
      : '$name $value o $at$later — powyżej progu $max';
}

/// Nieaktualne odczyty: „O₂ z 07:00” (z datą, gdy z innego dnia).
String _staleList(CsAssessment a, {required bool en}) => [
      for (final v in a.stale)
        '${v.gas.short(en: en)} ${en ? 'from' : 'z'} '
            '${csMeasurementTime(v.latest.first, a.recordDate)}',
    ].join(', ');

/// Główny komunikat stanu.
String confinedSpaceReadinessText(CsAssessment a, CsLimits l,
    {required bool en}) {
  if (a.closed && !a.otherDay) {
    return en
        ? 'Work closed — exit and close-out ticked.'
        : 'Praca zamknięta — wyjście i zamknięcie odhaczone.';
  }
  switch (a.readiness) {
    case CsReadiness.stop:
      final first = csStopText(a.stops.first, l,
          en: en, recordDate: a.recordDate);
      return en
          ? 'STOP — $first. Do not enter / get out; ventilate with air, '
              'remove the source and test again.'
          : 'STOP — $first. Nie wchodzić / wyjść; przewietrzyć powietrzem, '
              'usunąć źródło i zmierzyć ponownie.';
    case CsReadiness.otherDay:
      return en
          ? 'Record dated ${a.recordDate} — out of date, never valid for '
              'today. For a new entry use “Same as yesterday” and test the '
              'atmosphere again.'
          : 'Protokół z dnia ${a.recordDate} — nieaktualny, nie obowiązuje '
              'dziś. Do nowego wejścia użyj „Jak wczoraj” i zmierz atmosferę '
              'od nowa.';
    case CsReadiness.noMeasurement:
      final names = [for (final v in a.missing) v.gas.short(en: en)].join(', ');
      final stale = _staleList(a, en: en);
      final age = a.maxAgeMin;
      if (stale.isEmpty) {
        return en
            ? 'No reading for: $names — a missing reading is never OK.'
            : 'Brak odczytu: $names — brak pomiaru to nie „w normie”.';
      }
      final staleText = en
          ? 'reading out of date: $stale (valid $age min) — test again.'
          : 'pomiar nieaktualny: $stale (ważny $age min) — zmierz ponownie.';
      if (names.isEmpty) {
        return staleText[0].toUpperCase() + staleText.substring(1);
      }
      return en
          ? 'No reading for: $names; $staleText'
          : 'Brak odczytu: $names; $staleText';
    case CsReadiness.noLimit:
      final names = [for (final v in a.noLimits) v.gas.short(en: en)].join(', ');
      return en
          ? 'Enter the limit from the permit for: $names — without it the '
              'reading cannot be judged.'
          : 'Wpisz próg z pozwolenia dla: $names — bez niego odczytu nie da '
              'się ocenić.';
    case CsReadiness.incomplete:
      final n = a.openBefore.length;
      return en
          ? 'Atmosphere within limits; $n item(s) left before entry.'
          : 'Atmosfera w progach; do odhaczenia przed wejściem: $n.';
    case CsReadiness.ready:
      return en
          ? 'Prepared and atmosphere within limits — entry per the permit; '
              'keep monitoring.'
          : 'Przygotowane, atmosfera w progach — wejście wg pozwolenia; '
              'mierz dalej w trakcie.';
  }
}

/// Krótka etykieta stanu (historia, nagłówek PDF). Protokół z innego dnia
/// ma dopisek „nieaktualne”.
String confinedSpaceReadinessShort(CsAssessment a, {required bool en}) {
  final String base;
  if (a.readiness == CsReadiness.stop) {
    base = en ? 'STOP — atmosphere' : 'STOP — atmosfera';
  } else if (a.closed) {
    base = en ? 'Closed' : 'Zamknięte';
  } else {
    base = switch (a.readiness) {
      CsReadiness.otherDay => en ? 'Out of date' : 'Nieaktualne',
      CsReadiness.noMeasurement => a.missing.isEmpty
          ? (en ? 'Reading out of date' : 'Pomiar nieaktualny')
          : (en ? 'No gas reading' : 'Brak pomiaru'),
      CsReadiness.noLimit => en ? 'No limit' : 'Brak progu',
      CsReadiness.incomplete => en ? 'Incomplete' : 'Niekompletne',
      _ => en ? 'Ready' : 'Gotowe',
    };
  }
  if (!a.otherDay || (a.readiness == CsReadiness.otherDay && !a.closed)) {
    return base;
  }
  return '$base · ${en ? 'out of date' : 'nieaktualne'}';
}

/// Ostrzeżenie o remisie (kilka różnych odczytów z tej samej minuty).
String csTieText(CsGasVerdict v, {required bool en}) {
  final name = v.gas.short(en: en);
  final time = v.latest.first.time;
  return en
      ? '$name: different readings in the same minute ($time) — the worse '
          'one decides. Delete the wrong one or take a new reading.'
      : '$name: różne odczyty z tej samej minuty ($time) — decyduje gorszy. '
          'Usuń błędny albo zmierz ponownie.';
}

// ── Ostrzeżenia dla spawacza ───────────────────────────────────────────────

class CsWarning {
  /// Trwały identyfikator (klucze w UI i testach).
  final String id;
  final String pl;
  final String en;
  final String source;
  const CsWarning(this.id, this.pl, this.en, {required this.source});
  String label({required bool en}) => en ? this.en : pl;
}

const Set<CsProcess> _inertGas = {
  CsProcess.tig,
  CsProcess.migMag,
  CsProcess.purge,
};
const Set<CsProcess> _arc = {
  CsProcess.tig,
  CsProcess.migMag,
  CsProcess.mma,
  CsProcess.plasma,
};
const Set<CsProcess> _fume = {
  CsProcess.tig,
  CsProcess.migMag,
  CsProcess.mma,
  CsProcess.plasma,
  CsProcess.oxyFuel,
};
const Set<CsProcess> _gasHoses = {
  CsProcess.tig,
  CsProcess.migMag,
  CsProcess.purge,
  CsProcess.oxyFuel,
  CsProcess.plasma,
};

/// Wszystkie ostrzeżenia (do testów źródeł i liczb).
const List<CsWarning> kCsWarnings = [
  CsWarning(
    'oxygen',
    'Nigdy nie wentyluj, nie przedmuchuj i nie „odświeżaj” powietrza tlenem. '
        'Powietrze wzbogacone tlenem zapala odzież i włosy od jednej iskry — '
        'tak samo działa nieszczelny wąż tlenowy w zbiorniku.',
    'Never ventilate, purge or “freshen” the air with oxygen. '
        'Oxygen-enriched air sets clothing and hair alight from a single '
        'spark — a leaking oxygen hose inside does the same.',
    source: '§ 87 ust. 1 pkt 1 $kSrcBhp; praktyka OSHA 1910.252(c)(4)(v)',
  ),
  CsWarning(
    'inert',
    'Argon i CO₂ (TIG, MIG/MAG, formowanie) są bezwonne i cięższe od '
        'powietrza — zbierają się przy dnie i w zagłębieniach, wypierając '
        'tlen. Utrata przytomności przychodzi bez ostrzeżenia. Osobisty '
        'detektor O₂ przez cały czas, ciągły nawiew powietrza, pomiar także '
        'przy dnie.',
    'Argon and CO₂ (TIG, MIG/MAG, purging) are odourless and heavier than '
        'air — they collect at the bottom and in low spots, displacing '
        'oxygen. Collapse comes without warning. Personal O₂ monitor the '
        'whole time, continuous air supply, test at the bottom too.',
    source: '§ 87 ust. 1 pkt 6, § 90 ust. 1 $kSrcBhp; praktyka OSHA '
        '1910.252(c)(4)(i)',
  ),
  CsWarning(
    'purge',
    'Formowanie: gaz z grani wypływa do wnętrza zbiornika lub rury. Wylot '
        'formowania wyprowadź na zewnątrz albo z dala od pracującego; po '
        'formowaniu przewietrz i zmierz tlen przed wejściem.',
    'Purging: the backing gas flows into the vessel or pipe. Route the purge '
        'vent outside or away from the welder; after purging ventilate and '
        'test oxygen before entry.',
    source: '§ 87 ust. 1 pkt 6, § 90 ust. 1 $kSrcBhp',
  ),
  CsWarning(
    'break',
    'Przerwa: zamknij gaz osłonowy / formujący i zawory butli na zewnątrz, '
        'wyjmij palnik, uchwyt i węże ze zbiornika, elektrodę z uchwytu — '
        'nieszczelność w przerwie napełnia zbiornik gazem.',
    'Break: shut the shielding / purge gas and cylinder valves outside, take '
        'the torch, holder and hoses out of the space, the electrode out of '
        'the holder — a leak during the break fills the space with gas.',
    source: 'praktyka: OSHA 1910.252(b)(4)(v)–(vi)',
  ),
  CsWarning(
    'arc',
    'Spawanie łukowe w zbiorniku metalowym: źródło prądu do pracy przy '
        'zwiększonym zagrożeniu porażeniem, ustawione na zewnątrz; maty '
        'izolacyjne, sucha odzież i rękawice.',
    'Arc welding in a metal vessel: power source rated for increased '
        'electric shock hazard, placed outside; insulating mats, dry clothing '
        'and gloves.',
    source: '§ 30 pkt 5 $kSrcWeld',
  ),
  CsWarning(
    'fume',
    'Dymy i gazy spawalnicze w małej kubaturze: odciąg przy łuku, wywiew na '
        'zewnątrz. Stal nierdzewna (chrom sześciowartościowy): zob. Pomoc — '
        '„Kiedy PAPR przy spawaniu SS?”. Sprzęt filtrujący, także PAPR, nie '
        'chroni przy niedoborze tlenu — wtedy tylko sprzęt izolujący.',
    'Welding fume and gases in a small volume: extraction at the arc, '
        'exhaust outside. Stainless steel (hexavalent chromium): see Help — '
        '“When PAPR for SS welding?”. Filtering respirators, PAPR included, '
        'do not protect in oxygen deficiency — then only supplied air.',
    source: '§ 89 ust. 2 pkt 3, ust. 4 $kSrcBhp',
  ),
  CsWarning(
    'cylinders',
    'Butle i urządzenia zasilające poza zbiornikiem; propan i inne gazy '
        'palne cięższe od powietrza — nie poniżej terenu, nie przy '
        'studzienkach i kanałach.',
    'Cylinders and supply equipment outside the space; propane and other '
        'fuel gases heavier than air — not below ground, not near manholes '
        'and sewers.',
    source: '§ 34 ust. 3, § 32 pkt 5 $kSrcWeld',
  ),
];

CsWarning _w(String id) => kCsWarnings.firstWhere((w) => w.id == id);

/// Ostrzeżenia dla wybranych rodzajów pracy (zakaz tlenu — zawsze).
List<CsWarning> confinedSpaceWarnings(Set<CsProcess> processes) {
  bool any(Set<CsProcess> s) => processes.any(s.contains);
  return [
    _w('oxygen'),
    if (any(_inertGas)) _w('inert'),
    if (processes.contains(CsProcess.purge)) _w('purge'),
    if (any(_gasHoses) || any(_arc)) _w('break'),
    if (any(_arc)) _w('arc'),
    if (any(_fume)) _w('fume'),
    if (any(_gasHoses)) _w('cylinders'),
  ];
}

// ── Wiersze danych ─────────────────────────────────────────────────────────

/// Wiersz „etykieta — wartość”.
class CsLine {
  final String label;
  final String value;
  const CsLine(this.label, this.value);
}

String _orDash(String s) => s.trim().isEmpty ? '—' : s.trim();

/// Godziny ważności „07:00–15:00” (brak — kreska).
String confinedSpaceHours(ConfinedSpaceRecord r) {
  if (r.validFrom.isEmpty && r.validTo.isEmpty) return '—';
  return '${r.validFrom.isEmpty ? '…' : r.validFrom}–'
      '${r.validTo.isEmpty ? '…' : r.validTo}';
}

/// Dane pozwolenia w kolejności protokołu.
List<CsLine> confinedSpaceLines(ConfinedSpaceRecord r, {required bool en}) {
  final processes = [
    for (final p in CsProcess.values)
      if (r.processes.contains(p)) p.label(en: en),
  ].join(', ');
  return [
    CsLine(en ? 'Permit no.' : 'Nr pozwolenia', _orDash(r.permitNo)),
    CsLine(en ? 'Space' : 'Przestrzeń', _orDash(r.location)),
    CsLine(en ? 'Work' : 'Rodzaj pracy', _orDash(processes)),
    CsLine(en ? 'Description' : 'Opis pracy', _orDash(r.description)),
    CsLine(en ? 'Date' : 'Data', _orDash(r.date)),
    CsLine(en ? 'Valid (hours)' : 'Ważne (godziny)', confinedSpaceHours(r)),
    CsLine(en ? 'Entrants' : 'Wchodzący', _orDash(r.entrants)),
    CsLine(en ? 'Attendant (outside)' : 'Asekurujący (na zewnątrz)',
        _orDash(r.attendant)),
    CsLine(en ? 'Supervisor' : 'Nadzór / kierujący', _orDash(r.supervisor)),
    CsLine(en ? 'Permit issuer' : 'Wydający pozwolenie', _orDash(r.issuer)),
    CsLine(en ? 'Rescue plan' : 'Plan ratunkowy', _orDash(r.rescue)),
  ];
}

/// Progi i wymagania gazów: „O₂ — 19,5–23,5 % — wymagany”.
List<CsLine> confinedSpaceLimitLines(ConfinedSpaceRecord r,
    {required bool en}) {
  return [
    for (final g in CsGas.values)
      CsLine(
        g.label(en: en),
        '${formatCsGasLimit(g, r.limits, en: en)} — '
        '${r.requiredGases.contains(g) ? (en ? 'required' : 'wymagany') : (en ? 'not required by the permit' : 'niewymagany wg pozwolenia')}',
      ),
    CsLine(
      en ? 'Reading valid for' : 'Ważność pomiaru',
      '${r.effectiveMaxAgeMin} min — ${r.maxAgeMin == null ? (en ? 'adopted in the app' : 'przyjęta w aplikacji') : (en ? 'per permit' : 'wg pozwolenia')}',
    ),
  ];
}

/// Oznaczenie punktu w protokole: [x] sprawdzone, [n/d] nie dotyczy, [ ].
String confinedSpaceMark(ConfinedSpaceRecord r, ConfinedSpaceCheck c,
    {required bool en}) {
  if (r.isChecked(c)) return '[x]';
  if (r.isNa(c)) return en ? '[n/a]' : '[n/d]';
  return '[ ]';
}

/// Ocena odczytu słowem: „OK”, „ZA MAŁO”, „ZA DUŻO”, „brak progu”.
String csStateLabel(CsReadingState s, CsGas gas, {required bool en}) =>
    switch (s) {
      CsReadingState.ok => 'OK',
      CsReadingState.low => en ? 'TOO LOW' : 'ZA MAŁO',
      CsReadingState.high => gas == CsGas.o2
          ? (en ? 'TOO HIGH' : 'ZA DUŻO')
          : (en ? 'ABOVE LIMIT' : 'POWYŻEJ PROGU'),
      CsReadingState.noLimit => en ? 'no limit' : 'brak progu',
    };

/// Jeden odczyt: „O₂ 20,9 % (OK)”, „0 % DGW (OK)”, „CO 23 mg/m³ (OK)”.
String csReadingText(CsGas g, CsQty q, CsLimits l, {required bool en}) {
  final value = formatCsQty(g, q, en: en);
  final state = csStateLabel(csReadingState(g, q, l), g, en: en);
  return g == CsGas.lel
      ? '$value ($state)'
      : '${g.short(en: en)} $value ($state)';
}

/// Wiersz pomiaru: „10:30 — dno — O₂ 20,9 % (OK) · 0 % DGW (OK)”; pomiar
/// z innego dnia niż [recordDate] — z datą („2026-10-16 23:50 — …”).
String csMeasurementLine(CsMeasurement m, CsLimits l,
    {required bool en, String? recordDate}) {
  final readings = [
    for (final g in CsGas.values)
      if (m[g] != null) csReadingText(g, m[g]!, l, en: en),
  ].join(' · ');
  final parts = [
    recordDate == null
        ? (m.time.isEmpty ? '—' : m.time)
        : csMeasurementTime(m, recordDate),
    if (m.place.trim().isNotEmpty) m.place.trim(),
    readings,
  ];
  return parts.join(' — ');
}

/// Protokół tekstowy do udostępnienia (komunikator, e-mail) — stan
/// w chwili [now].
String confinedSpaceProtocolText(ConfinedSpaceRecord r,
    {required bool en, required DateTime now}) {
  final a = r.assess(now: now);
  final b = StringBuffer()
    ..writeln(en
        ? 'CONFINED SPACE — ENTRY AND WELDING RECORD'
        : 'PRZESTRZEŃ ZAMKNIĘTA — PROTOKÓŁ WEJŚCIA I SPAWANIA')
    ..writeln(en
        ? '(checklist aid — not a permit)'
        : '(lista pomocnicza — nie zastępuje pozwolenia)')
    ..writeln();
  for (final l in confinedSpaceLines(r, en: en)) {
    b.writeln('${l.label}: ${l.value}');
  }
  b
    ..writeln()
    ..writeln(
        '${en ? 'STATUS' : 'STAN'}: ${confinedSpaceReadinessText(a, r.limits, en: en)}');
  for (final v in a.stops.skip(1)) {
    b.writeln('STOP — ${csStopText(v, r.limits, en: en, recordDate: r.date)}');
  }
  for (final v in a.ties) {
    b.writeln('! ${csTieText(v, en: en)}');
  }
  b
    ..writeln()
    ..writeln(en ? 'GAS LIMITS' : 'PROGI GAZÓW');
  for (final l in confinedSpaceLimitLines(r, en: en)) {
    b.writeln('- ${l.label}: ${l.value}');
  }
  b
    ..writeln()
    ..writeln(en ? 'GAS READINGS' : 'POMIARY ATMOSFERY');
  if (r.measurements.isEmpty) {
    b.writeln(en ? '— no reading —' : '— brak pomiaru —');
  } else {
    for (final m in r.measurementsChrono) {
      b.writeln(
          '- ${csMeasurementLine(m, r.limits, en: en, recordDate: r.date)}');
    }
  }
  final warnings = confinedSpaceWarnings(r.processes);
  b
    ..writeln()
    ..writeln(en ? 'WARNINGS FOR THE WELDER' : 'OSTRZEŻENIA DLA SPAWACZA');
  for (final w in warnings) {
    b.writeln('! ${w.label(en: en)}');
  }
  for (final phase in ConfinedSpacePhase.values) {
    final checks = confinedSpaceChecksIn(phase);
    final done = checks.where(r.isSettled).length;
    b
      ..writeln()
      ..writeln(
          '${phase.label(en: en).toUpperCase()} ($done/${checks.length})');
    for (final g in confinedSpaceGroupsIn(phase)) {
      for (final c in confinedSpaceChecksInGroup(g)) {
        b.writeln('${confinedSpaceMark(r, c, en: en)} ${c.label(en: en)}');
      }
    }
  }
  if (r.notes.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('${en ? 'Notes' : 'Uwagi'}: ${r.notes.trim()}');
  }
  b
    ..writeln()
    ..writeln(confinedSpaceDisclaimer(en: en))
    ..write('Fitter Welder Pro');
  return b.toString();
}
