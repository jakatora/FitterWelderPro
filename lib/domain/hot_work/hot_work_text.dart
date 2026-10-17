/// Teksty modułu „Prace pożarowo niebezpieczne”: zastrzeżenie, opis stanu,
/// wiersze danych zezwolenia i protokół tekstowy do udostępnienia.
///
/// Czysty Dart — te same wiersze składają tekst i PDF.
library;

import 'hot_work_checklist.dart';
import 'hot_work_permit.dart';
import 'hot_work_sources.dart';

/// Zastrzeżenie — na ekranie (góra i dół), w tekście i w PDF.
String hotWorkDisclaimer({required bool en}) => en
    ? 'Checklist aid only — not a permit. Binding are the law (in Poland '
        'e.g. the Regulation of the Minister of the Interior and '
        'Administration of 7 June 2010 on fire protection of buildings, '
        'other construction works and areas, § 36 on hot work, and the '
        'regulation on health and safety in welding), the site fire safety '
        'instruction and the hot work permit issued by the site. Distances, '
        'gas limits and watch times: always as stated in the permit.'
    : 'Lista pomocnicza — nie zastępuje zezwolenia. Wiążące są przepisy '
        '(w PL m.in. rozporządzenie MSWiA z 7 czerwca 2010 r. w sprawie '
        'ochrony przeciwpożarowej budynków, innych obiektów budowlanych '
        'i terenów — § 36 o pracach niebezpiecznych pod względem '
        'pożarowym — oraz rozporządzenie w sprawie BHP przy pracach '
        'spawalniczych), instrukcja bezpieczeństwa pożarowego zakładu '
        'i zezwolenie wystawione przez zakład. Odległości, dopuszczalne '
        'stężenia i czas dozoru — zawsze wg zezwolenia.';

/// Liczba % DGW do tekstu („0,5 % DGW” / „0.5 % LEL”).
String hotWorkDgw(double v, {required bool en}) =>
    '${formatHotWorkNumber(v, en: en)} % ${en ? 'LEL' : 'DGW'}';

/// Główny komunikat stanu.
String hotWorkReadinessText(HotWorkAssessment a, {required bool en}) {
  if (a.closed && !a.otherDay) {
    return en
        ? 'Work closed — post-work checks and fire watch ticked.'
        : 'Praca zamknięta — kontrola i dozór po pracy odhaczone.';
  }
  switch (a.readiness) {
    case HotWorkReadiness.overLimit:
      final m = a.lastMeasurement!;
      final limit = hotWorkDgw(a.effectiveLimitPct, en: en);
      final noPermitLimit = a.limitMissing
          ? (en
              ? ' (regulation limit, no permit limit)'
              : ' (granica przepisu, brak limitu z zezwolenia)')
          : '';
      final value = hotWorkDgw(m.dgwPct, en: en);
      final which = a.enteredLater && a.latestMeasurement != null
          ? (en
              ? 'the $value reading entered after the '
                  '${a.latestMeasurement!.time} one'
              : 'pomiar $value wpisany po pomiarze z '
                  '${a.latestMeasurement!.time}')
          : (en ? 'last gas reading $value' : 'ostatni pomiar $value');
      return en
          ? 'STOP — $which is above the permitted $limit$noPermitLimit. Do '
              'not start; remove the source, ventilate and test again.'
          : 'STOP — $which przekracza dopuszczalne $limit$noPermitLimit. '
              'Nie rozpoczynać; usunąć źródło, przewietrzyć i zmierzyć '
              'ponownie.';
    case HotWorkReadiness.otherDay:
      return en
          ? 'Record dated ${a.recordDate} — out of date, never valid for '
              'today. For new work use “Same as yesterday” and test again.'
          : 'Protokół z dnia ${a.recordDate} — nieaktualny, nie obowiązuje '
              'dziś. Do nowej pracy użyj „Jak wczoraj” i zmierz ponownie.';
    case HotWorkReadiness.noMeasurement:
      if (a.measurementMissing) {
        return en
            ? 'No gas test result — enter the reading (% LEL) and its time.'
            : 'Brak pomiaru atmosfery — wpisz wynik (% DGW) i godzinę.';
      }
      final from = a.latestMeasurement == null
          ? '—'
          : hotWorkMeasurementTime(a.latestMeasurement!, a.recordDate);
      return en
          ? 'Gas test out of date (from $from, valid ${a.maxAgeMin} min) — '
              'test again.'
          : 'Pomiar nieaktualny (z $from, ważny ${a.maxAgeMin} min) — '
              'zmierz ponownie.';
    case HotWorkReadiness.noLimit:
      return en
          ? 'Enter the permitted % LEL from the permit — without it the '
              'reading cannot be judged.'
          : 'Wpisz dopuszczalne % DGW z zezwolenia — bez tego wyniku nie '
              'da się ocenić.';
    case HotWorkReadiness.incomplete:
      final n = a.openBefore.length;
      return en
          ? '$n item(s) left before work starts.'
          : 'Do odhaczenia przed rozpoczęciem: $n.';
    case HotWorkReadiness.ready:
      return en
          ? 'Area prepared — ready for the permit to be signed.'
          : 'Stanowisko przygotowane — zezwolenie może zostać podpisane.';
  }
}

/// Krótka etykieta stanu (historia, nagłówek PDF). Protokół z innego dnia
/// ma dopisek „nieaktualne”.
String hotWorkReadinessShort(HotWorkAssessment a, {required bool en}) {
  final String base;
  if (a.readiness == HotWorkReadiness.overLimit) {
    base = en ? 'STOP — gas' : 'STOP — gazy';
  } else if (a.closed) {
    base = en ? 'Closed' : 'Zamknięte';
  } else {
    base = switch (a.readiness) {
      HotWorkReadiness.otherDay => en ? 'Out of date' : 'Nieaktualne',
      HotWorkReadiness.noMeasurement => a.measurementMissing
          ? (en ? 'No gas test' : 'Brak pomiaru')
          : (en ? 'Gas test out of date' : 'Pomiar nieaktualny'),
      HotWorkReadiness.noLimit => en ? 'No LEL limit' : 'Brak limitu DGW',
      HotWorkReadiness.incomplete => en ? 'Incomplete' : 'Niekompletne',
      _ => en ? 'Ready' : 'Gotowe',
    };
  }
  if (!a.otherDay ||
      (a.readiness == HotWorkReadiness.otherDay && !a.closed)) {
    return base;
  }
  return '$base · ${en ? 'out of date' : 'nieaktualne'}';
}

/// Wiersz „etykieta — wartość” danych zezwolenia.
class HotWorkLine {
  final String label;
  final String value;
  const HotWorkLine(this.label, this.value);
}

String _orDash(String s) => s.trim().isEmpty ? '—' : s.trim();

/// Godziny ważności „07:00–15:00” (brak — kreska).
String hotWorkHours(HotWorkPermit p) {
  if (p.validFrom.isEmpty && p.validTo.isEmpty) return '—';
  return '${p.validFrom.isEmpty ? '…' : p.validFrom}–'
      '${p.validTo.isEmpty ? '…' : p.validTo}';
}

/// Dane zezwolenia w kolejności protokołu.
List<HotWorkLine> hotWorkPermitLines(HotWorkPermit p, {required bool en}) {
  final types = [
    for (final t in HotWorkType.values)
      if (p.workTypes.contains(t)) t.label(en: en),
  ].join(', ');
  return [
    HotWorkLine(en ? 'Permit no.' : 'Nr zezwolenia', _orDash(p.permitNo)),
    HotWorkLine(en ? 'Location' : 'Miejsce pracy', _orDash(p.location)),
    HotWorkLine(en ? 'Type of work' : 'Rodzaj pracy', _orDash(types)),
    HotWorkLine(en ? 'Description' : 'Opis pracy', _orDash(p.description)),
    HotWorkLine(en ? 'Date' : 'Data', _orDash(p.date)),
    HotWorkLine(en ? 'Valid (hours)' : 'Ważne (godziny)', hotWorkHours(p)),
    HotWorkLine(
        en ? 'Performed by' : 'Wykonawca', _orDash(p.contractor)),
    HotWorkLine(
        en ? 'Responsible for securing the area'
            : 'Odpowiedzialny za zabezpieczenie',
        _orDash(p.securedBy)),
    HotWorkLine(en ? 'Fire watch' : 'Dozorujący', _orDash(p.fireWatch)),
    HotWorkLine(en ? 'Permit issuer' : 'Wystawiający zezwolenie',
        _orDash(p.issuer)),
    HotWorkLine(
        en ? 'Permitted gas level' : 'Dopuszczalne stężenie',
        p.dgwLimitPct == null
            ? (en ? '— (per permit)' : '— (wg zezwolenia)')
            : '≤ ${hotWorkDgw(p.dgwLimitPct!, en: en)}'),
    HotWorkLine(
        en ? 'Post-work fire watch' : 'Dozór po zakończeniu',
        p.fireWatchAfterMin == null
            ? (en ? '— (per permit)' : '— (wg zezwolenia)')
            : '${p.fireWatchAfterMin} min'),
    HotWorkLine(
        en ? 'Gas test valid for' : 'Ważność pomiaru',
        '${p.effectiveMaxAgeMin} min — ${p.measurementMaxAgeMin == null ? (en ? 'adopted in the app' : 'przyjęta w aplikacji') : (en ? 'per permit' : 'wg zezwolenia')}'),
  ];
}

/// Oznaczenie punktu w protokole: [x] sprawdzone, [n/d] nie dotyczy, [ ].
String hotWorkMark(HotWorkPermit p, HotWorkCheck c, {required bool en}) {
  if (p.isChecked(c)) return '[x]';
  if (p.isNa(c)) return en ? '[n/a]' : '[n/d]';
  return '[ ]';
}

/// Wiersz pomiaru „07:10 — 0 % DGW — studzienka K-3”; pomiar z innego dnia
/// niż [recordDate] — z datą („2026-10-16 23:50 — …”). Bez limitu
/// z zezwolenia wynik ponad 10 % DGW z przepisu i tak jest „POWYŻEJ”.
String hotWorkMeasurementLine(HotWorkMeasurement m, double? limit,
    {required bool en, String? recordDate}) {
  final parts = [
    recordDate == null
        ? (m.time.isEmpty ? '—' : m.time)
        : hotWorkMeasurementTime(m, recordDate),
    hotWorkDgw(m.dgwPct, en: en),
    if (m.note.trim().isNotEmpty) m.note.trim(),
  ];
  final String verdict;
  if (limit != null) {
    verdict = hotWorkMeasurementOk(m.dgwPct, limit)
        ? ' (OK)'
        : (en ? ' (ABOVE LIMIT)' : ' (POWYŻEJ LIMITU)');
  } else if (!hotWorkMeasurementOk(m.dgwPct, kHotWorkDefaultDgwLimitPct)) {
    verdict = en
        ? ' (ABOVE THE REGULATION LIMIT)'
        : ' (POWYŻEJ LIMITU Z PRZEPISU)';
  } else {
    verdict = '';
  }
  return '${parts.join(' — ')}$verdict';
}

/// Protokół tekstowy do udostępnienia (komunikator, e-mail) — stan
/// w chwili [now].
String hotWorkProtocolText(HotWorkPermit p,
    {required bool en, required DateTime now}) {
  final a = p.assess(now: now);
  final b = StringBuffer()
    ..writeln(en
        ? 'HOT WORK — WORK AREA PREPARATION RECORD'
        : 'PRACE POŻAROWO NIEBEZPIECZNE — PROTOKÓŁ PRZYGOTOWANIA STANOWISKA')
    ..writeln(en
        ? '(checklist aid — not a permit)'
        : '(lista pomocnicza — nie zastępuje zezwolenia)')
    ..writeln();
  for (final l in hotWorkPermitLines(p, en: en)) {
    b.writeln('${l.label}: ${l.value}');
  }
  b
    ..writeln()
    ..writeln('${en ? 'STATUS' : 'STAN'}: ${hotWorkReadinessText(a, en: en)}')
    ..writeln()
    ..writeln(en ? 'GAS TEST' : 'POMIAR ATMOSFERY');
  if (p.measurements.isEmpty) {
    b.writeln(en ? '— no reading —' : '— brak pomiaru —');
  } else {
    for (final m in p.measurementsChrono) {
      b.writeln('- '
          '${hotWorkMeasurementLine(m, p.dgwLimitPct, en: en, recordDate: p.date)}');
    }
  }
  for (final phase in HotWorkPhase.values) {
    final checks = hotWorkChecksIn(phase);
    final done = checks.where(p.isSettled).length;
    b
      ..writeln()
      ..writeln('${phase.label(en: en).toUpperCase()} ($done/${checks.length})');
    for (final g in hotWorkGroupsIn(phase)) {
      for (final c in hotWorkChecksInGroup(g)) {
        b.writeln('${hotWorkMark(p, c, en: en)} ${c.label(en: en)}');
      }
    }
  }
  if (p.notes.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('${en ? 'Notes' : 'Uwagi'}: ${p.notes.trim()}');
  }
  b
    ..writeln()
    ..writeln(hotWorkDisclaimer(en: en))
    ..write('Fitter Welder Pro');
  return b.toString();
}
