/// Teksty modułu „Prace pożarowo niebezpieczne”: zastrzeżenie, opis stanu,
/// wiersze danych zezwolenia i protokół tekstowy do udostępnienia.
///
/// Czysty Dart — te same wiersze składają tekst i PDF.
library;

import 'hot_work_checklist.dart';
import 'hot_work_permit.dart';

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
  if (a.closed) {
    return en
        ? 'Work closed — post-work checks and fire watch ticked.'
        : 'Praca zamknięta — kontrola i dozór po pracy odhaczone.';
  }
  switch (a.readiness) {
    case HotWorkReadiness.overLimit:
      final m = a.lastMeasurement!;
      return en
          ? 'STOP — last gas reading ${hotWorkDgw(m.dgwPct, en: true)} is '
              'above the permitted ${hotWorkDgw(a.limitPct!, en: true)}. '
              'Do not start; remove the source, ventilate and test again.'
          : 'STOP — ostatni pomiar ${hotWorkDgw(m.dgwPct, en: false)} '
              'przekracza dopuszczalne ${hotWorkDgw(a.limitPct!, en: false)}. '
              'Nie rozpoczynać; usunąć źródło, przewietrzyć i zmierzyć ponownie.';
    case HotWorkReadiness.noMeasurement:
      return en
          ? 'No gas test result — enter the reading (% LEL) and its time.'
          : 'Brak pomiaru atmosfery — wpisz wynik (% DGW) i godzinę.';
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

/// Krótka etykieta stanu (historia, nagłówek PDF).
String hotWorkReadinessShort(HotWorkAssessment a, {required bool en}) {
  if (a.closed) return en ? 'Closed' : 'Zamknięte';
  return switch (a.readiness) {
    HotWorkReadiness.overLimit => en ? 'STOP — gas' : 'STOP — gazy',
    HotWorkReadiness.noMeasurement => en ? 'No gas test' : 'Brak pomiaru',
    HotWorkReadiness.noLimit => en ? 'No LEL limit' : 'Brak limitu DGW',
    HotWorkReadiness.incomplete => en ? 'Incomplete' : 'Niekompletne',
    HotWorkReadiness.ready => en ? 'Ready' : 'Gotowe',
  };
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
  ];
}

/// Oznaczenie punktu w protokole: [x] sprawdzone, [n/d] nie dotyczy, [ ].
String hotWorkMark(HotWorkPermit p, HotWorkCheck c, {required bool en}) {
  if (p.isChecked(c)) return '[x]';
  if (p.isNa(c)) return en ? '[n/a]' : '[n/d]';
  return '[ ]';
}

/// Wiersz pomiaru „07:10 — 0 % DGW — studzienka K-3”.
String hotWorkMeasurementLine(HotWorkMeasurement m, double? limit,
    {required bool en}) {
  final parts = [
    m.time.isEmpty ? '—' : m.time,
    hotWorkDgw(m.dgwPct, en: en),
    if (m.note.trim().isNotEmpty) m.note.trim(),
  ];
  final verdict = limit == null
      ? ''
      : hotWorkMeasurementOk(m.dgwPct, limit)
          ? (en ? ' (OK)' : ' (OK)')
          : (en ? ' (ABOVE LIMIT)' : ' (POWYŻEJ LIMITU)');
  return '${parts.join(' — ')}$verdict';
}

/// Protokół tekstowy do udostępnienia (komunikator, e-mail).
String hotWorkProtocolText(HotWorkPermit p, {required bool en}) {
  final a = p.assess();
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
    for (final m in p.measurements) {
      b.writeln('- ${hotWorkMeasurementLine(m, p.dgwLimitPct, en: en)}');
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
