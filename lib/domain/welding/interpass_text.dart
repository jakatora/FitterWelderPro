/// Teksty modułu „Temperatura podgrzania i międzyściegowa”: zastrzeżenie,
/// zasady pomiaru ze źródłami, opis werdyktu, wiersze danych spoiny
/// i protokół tekstowy do udostępnienia.
///
/// Zasady pomiaru — sprawdzone 2026-10-17:
/// * EN ISO 13916:2017 (= ISO 13916:2017; obecne wydanie ISO 13916:2025,
///   DIN EN ISO 13916:2026-02) — z podglądu STN EN ISO 13916:2018
///   potwierdzony tylko zakres i układ: 4.1 punkt pomiaru, 4.2 czas pomiaru,
///   4.3 przyrządy, 5 sprawozdanie. Treść wymagań jest płatna — aplikacja
///   jej nie cytuje.
/// * TWI FAQ „Why is preheat used when arc welding steel, and how is it
///   applied?” (powołuje BS EN ISO 13916 i BS EN 1011-2): podgrzanie
///   kontrolować w odległości 4t od podłużnej krawędzi rowka dla t < 50 mm,
///   co najmniej 75 mm od przygotowania złącza dla t > 50 mm, po stronie
///   przeciwnej do źródła ciepła; typowe metody — kredki, termopary,
///   termometry kontaktowe.
/// * TWI FAQ „What is a Tempil stick?”: kredka pokazuje tylko, że
///   temperatura została osiągnięta lub przekroczona; jednorazowa — przy
///   międzyściegowej trzeba ją nakładać ponownie; do kontroli termopary
///   lub termometry kontaktowe.
/// * SSAB „Attaining and measuring the preheating temperature”: strefa
///   75 + 75 mm wokół złącza; min. 2 min na 25 mm grubości przed pomiarem;
///   międzyściegowa na spoinie w miejscu rozpoczęcia ściegu albo na
///   materiale rodzimym tuż obok.
/// * Fluke „How to get great results with an infrared thermometer”:
///   błyszczący metal ma niską emisyjność — pirometr może zaniżać odczyt.
///
/// NIEPOTWIERDZONE w tekście normy (tylko streszczenia): górny limit
/// odległości 50 mm przy 4t i 2 min / 25 mm jako wymóg samej normy — dlatego
/// tego nie liczymy i nie podajemy jako wymogu normy.
///
/// Czysty Dart — te same wiersze składają tekst i PDF.
library;

import 'interpass_log.dart';

/// Zastrzeżenie — na ekranie, w tekście i w PDF.
String interpassDisclaimer({required bool en}) => en
    ? 'Record aid only. Binding are the WPS limits and measuring method, '
        'the client / product standard requirements and the current EN ISO '
        '13916. The app gives NO “typical” temperatures — enter the values '
        'from the WPS.'
    : 'Rejestr pomocniczy. Wiążące są limity i sposób pomiaru z WPS, '
        'wymagania zamawiającego / normy wyrobu i aktualna EN ISO 13916. '
        'Aplikacja NIE podaje „typowych” temperatur — wpisz wartości z WPS.';

/// Zasada na granicy — przy limitach i w protokole.
String interpassBoundaryNote({required bool en}) => en
    ? 'At the limit: a temperature equal to the limit is OK (minimum: at '
        'least the limit, maximum: not above it).'
    : 'Na granicy: temperatura równa limitowi = OK (min.: co najmniej limit, '
        'maks.: nie więcej niż limit).';

/// Co jest oceniane względem czego.
String interpassPassRule({required bool en}) => en
    ? 'Pass 1 = reading before the first run, checked against the minimum '
        'preheat. Pass n ≥ 2 = reading before run n, checked against the '
        'maximum (and minimum, if set) interpass temperature. The latest '
        'reading in time before a run decides.'
    : 'Ścieg 1 = pomiar przed pierwszym ściegiem, oceniany względem min. '
        'podgrzania. Ścieg n ≥ 2 = pomiar przed ściegiem n, oceniany '
        'względem maks. (i min., jeśli ustawiona) międzyściegowej. Decyduje '
        'najpóźniejszy w czasie pomiar przed danym ściegiem.';

/// Uwaga o metodzie pomiaru (ze źródłem).
String interpassMethodNote(InterpassMethod m, {required bool en}) {
  switch (m) {
    case InterpassMethod.contact:
      return en
          ? 'Contact thermometer / thermocouple probe gives a value. Clean '
              'metal, wait until the reading settles. TWI lists '
              'thermocouples and contact thermometers as common ways to '
              'monitor preheat.'
          : 'Termometr kontaktowy / sonda z termoparą podaje wartość. Czysty '
              'metal, odczekaj, aż odczyt się ustabilizuje. TWI wymienia '
              'termopary i termometry kontaktowe jako typowe metody kontroli '
              'podgrzania.';
    case InterpassMethod.crayon:
      return en
          ? 'Crayon (e.g. Tempilstik): the mark MELTS once its rated '
              'temperature is reached — it only tells “reached / not '
              'reached”, gives no value and does not show a later drop or '
              'rise; make a new mark before each run (TWI, “What is a Tempil '
              'stick?”). Preheat: a stick rated at the minimum must melt. '
              'Maximum interpass: a stick rated at the maximum must NOT '
              'melt. Enter the stick rating and the result.'
          : 'Kredka (np. Tempilstik): ślad TOPI SIĘ po osiągnięciu '
              'temperatury znamionowej — mówi tylko „osiągnięto / nie '
              'osiągnięto progu”, nie podaje wartości i nie pokazuje '
              'późniejszego spadku ani wzrostu; przed każdym ściegiem nowy '
              'ślad (TWI, „What is a Tempil stick?”). Podgrzanie: kredka '
              'o progu = min. musi się stopić. Maks. międzyściegowa: kredka '
              'o progu = maks. NIE może się stopić. Wpisz próg kredki i wynik.';
    case InterpassMethod.pyrometer:
      return en
          ? 'Infrared pyrometer: on bright, ground or stainless steel the '
              'low emissivity makes it read LOW (Fluke, “How to get great '
              'results with an infrared thermometer”). For the maximum '
              'interpass that error is unsafe — the real temperature may be '
              'above the limit. Set the emissivity, aim at a dull spot or '
              'check with a contact thermometer.'
          : 'Pirometr (podczerwień): na błyszczącej, szlifowanej lub '
              'nierdzewnej stali niska emisyjność ZANIŻA odczyt (Fluke, „How '
              'to get great results with an infrared thermometer”). Przy '
              'maks. międzyściegowej to błąd na niekorzyść — faktyczna '
              'temperatura może przekraczać limit. Ustaw emisyjność, mierz '
              'na matowym miejscu albo sprawdź termometrem kontaktowym.';
  }
}

/// Miejsce i chwila pomiaru — skrót ze źródeł, które streszczają
/// EN ISO 13916 (pełny tekst normy jest płatny).
List<String> interpassPlaceNotes({required bool en}) => en
    ? const [
        'Preheat: at 4 × t from the longitudinal edge of the groove for '
            't < 50 mm; for t > 50 mm at least 75 mm from the joint '
            'preparation; preferably on the face opposite the heat source '
            '(TWI, citing BS EN ISO 13916 and BS EN 1011-2).',
        'After heating wait about 2 min per 25 mm of thickness before '
            'measuring (SSAB).',
        'Interpass: on the weld metal at the start of the next run or on '
            'the parent metal right next to it, immediately before the run '
            '(SSAB).',
        'The WPS and the current edition of EN ISO 13916 (ISO 13916:2025) '
            'apply — the app does not quote the standard.',
      ]
    : const [
        'Podgrzanie: w odległości 4 × t od podłużnej krawędzi rowka dla '
            't < 50 mm; dla t > 50 mm co najmniej 75 mm od przygotowania '
            'złącza; najlepiej po stronie przeciwnej do źródła ciepła (TWI, '
            'powołuje BS EN ISO 13916 i BS EN 1011-2).',
        'Po podgrzaniu odczekaj ok. 2 min na każde 25 mm grubości przed '
            'pomiarem (SSAB).',
        'Międzyściegowa: na spoinie w miejscu rozpoczęcia następnego ściegu '
            'albo na materiale rodzimym tuż obok, bezpośrednio przed ściegiem '
            '(SSAB).',
        'Obowiązuje WPS i aktualne wydanie EN ISO 13916 (ISO 13916:2025) — '
            'aplikacja nie cytuje normy.',
      ];

class InterpassSource {
  final String pl;
  final String en;
  const InterpassSource(this.pl, this.en);
  String label({required bool en}) => en ? this.en : pl;
}

/// Lista „Źródła” na ekranie.
const List<InterpassSource> kInterpassSources = [
  InterpassSource(
    'EN ISO 13916:2017 (ISO 13916:2017; obecnie ISO 13916:2025) — pomiar '
        'temperatury podgrzania, międzyściegowej i utrzymania podgrzania; '
        'rozdziały: punkt pomiaru, czas pomiaru, przyrządy, sprawozdanie.',
    'EN ISO 13916:2017 (ISO 13916:2017; now ISO 13916:2025) — measurement '
        'of preheating, interpass and preheat maintenance temperature; '
        'clauses: point of measurement, time of measurement, equipment, '
        'test report.',
  ),
  InterpassSource(
    'TWI, FAQ „Why is preheat used when arc welding steel, and how is it '
        'applied?” — 4t / 75 mm, strona przeciwna do źródła ciepła; kredki, '
        'termopary, termometry kontaktowe.',
    'TWI, FAQ “Why is preheat used when arc welding steel, and how is it '
        'applied?” — 4t / 75 mm, reverse side to the heat source; crayons, '
        'thermocouples, contact thermometers.',
  ),
  InterpassSource(
    'TWI, FAQ „What is a Tempil stick?” — kredka wskazuje tylko '
        'osiągnięcie / przekroczenie temperatury; ponowne nakładanie przy '
        'międzyściegowej.',
    'TWI, FAQ “What is a Tempil stick?” — a crayon only shows that a '
        'temperature was reached / exceeded; re-apply for interpass.',
  ),
  InterpassSource(
    'SSAB, „Attaining and measuring the preheating temperature” — strefa '
        '75 + 75 mm, 2 min / 25 mm przed pomiarem, międzyściegowa na spoinie '
        'lub tuż obok.',
    'SSAB, “Attaining and measuring the preheating temperature” — '
        '75 + 75 mm zone, 2 min / 25 mm before measuring, interpass on the '
        'weld or right next to it.',
  ),
  InterpassSource(
    'Fluke, „How to get great results with an infrared thermometer” — '
        'błyszczący metal: niska emisyjność, zaniżony odczyt.',
    'Fluke, “How to get great results with an infrared thermometer” — '
        'shiny metal: low emissivity, low reading.',
  ),
];

// ── Ocena i stan ──────────────────────────────────────────────────────────

/// Wartość odczytu: „180 °C”, kredka „≥ 150 °C” / „< 250 °C”.
String interpassReadingValue(InterpassReading r, InterpassUnit unit,
    {required bool en}) {
  final t = formatInterpassTemp(r.tempC, unit, en: en);
  return switch (r.bound) {
    InterpassBound.exact => t,
    InterpassBound.atLeast => '≥ $t',
    InterpassBound.below => '< $t',
  };
}

/// Etykieta oceny pomiaru.
String interpassCheckLabel(InterpassCheck c, {required bool en}) => switch (c) {
      InterpassCheck.ok => 'OK',
      InterpassCheck.low => en ? 'BELOW MIN' : 'PONIŻEJ MIN.',
      InterpassCheck.high => en ? 'ABOVE MAX' : 'POWYŻEJ MAKS.',
      InterpassCheck.unconfirmed =>
        en ? 'not confirmed (crayon)' : 'niepotwierdzony (kredka)',
      InterpassCheck.noLimit => en ? 'no WPS limit' : 'brak limitu z WPS',
    };

String _passes(List<int> p) => p.join(', ');

/// Główny komunikat werdyktu spoiny.
String interpassStatusText(InterpassAssessment a, {required bool en}) {
  switch (a.status) {
    case InterpassWeldStatus.outOfLimits:
      return en
          ? 'OUT OF LIMITS — pass ${_passes(a.failedPasses)}: the reading '
              'before the run is outside the WPS limits. Do not weld on; '
              'wait / reheat and measure again.'
          : 'POZA LIMITEM — ścieg ${_passes(a.failedPasses)}: pomiar przed '
              'ściegiem poza limitem z WPS. Nie spawaj dalej; odczekaj / '
              'dogrzej i zmierz ponownie.';
    case InterpassWeldStatus.limitsConflict:
      return en
          ? 'Limits contradict each other (a minimum above the maximum '
              'interpass) — check the values against the WPS.'
          : 'Limity są sprzeczne (minimum wyżej niż maks. międzyściegowa) — '
              'sprawdź wartości z WPS.';
    case InterpassWeldStatus.noReadings:
      return en
          ? 'No readings — measure before the first run (preheat).'
          : 'Brak pomiarów — zmierz przed pierwszym ściegiem (podgrzanie).';
    case InterpassWeldStatus.missingPasses:
      return en
          ? 'No reading before pass ${_passes(a.missingPasses)}.'
          : 'Brak pomiaru przed ściegiem ${_passes(a.missingPasses)}.';
    case InterpassWeldStatus.passCountConflict:
      return en
          ? 'Readings for pass ${_passes(a.passesBeyondCount)} — more than '
              'the ${a.passCount} passes entered. Correct the pass count or '
              'the pass numbers.'
          : 'Pomiary dla ściegu ${_passes(a.passesBeyondCount)} — więcej niż '
              'wpisana liczba ściegów (${a.passCount}). Popraw liczbę '
              'ściegów albo numery.';
    case InterpassWeldStatus.passCountMissing:
      return en
          ? 'Enter the number of passes — without it nobody can tell '
              'whether every pass has a reading.'
          : 'Wpisz liczbę ściegów — bez niej nie wiadomo, czy każdy ścieg '
              'ma pomiar.';
    case InterpassWeldStatus.orderConflict:
      return en
          ? 'Reading times do not follow the pass numbers (pass '
              '${_passes(a.orderConflictPasses)} measured after the next '
              'pass) — check the times / numbers.'
          : 'Godziny pomiarów nie zgadzają się z numerami ściegów (ścieg '
              '${_passes(a.orderConflictPasses)} zmierzony po następnym) — '
              'sprawdź godziny / numery.';
    case InterpassWeldStatus.unconfirmed:
      return en
          ? 'Crayon does not confirm the limit for pass '
              '${_passes(a.unconfirmedPasses)} — use a stick rated at the '
              'limit or a thermometer.'
          : 'Kredka nie potwierdza limitu dla ściegu '
              '${_passes(a.unconfirmedPasses)} — użyj kredki o progu równym '
              'limitowi albo termometru.';
    case InterpassWeldStatus.noLimit:
      return en
          ? 'No WPS limit for pass ${_passes(a.noLimitPasses)} — the '
              'reading is recorded but cannot be judged. Enter the limit '
              'from the WPS.'
          : 'Brak limitu z WPS dla ściegu ${_passes(a.noLimitPasses)} — '
              'pomiar zapisany, ale nie da się go ocenić. Wpisz limit z WPS.';
    case InterpassWeldStatus.ok:
      return en
          ? 'All ${a.lastPass} passes have a reading before the run and '
              'all are within the WPS limits.'
          : 'Wszystkie ściegi (${a.lastPass}) mają pomiar przed '
              'rozpoczęciem i wszystkie są w limitach z WPS.';
  }
}

/// Krótka etykieta stanu (lista spoin).
String interpassStatusShort(InterpassAssessment a, {required bool en}) =>
    switch (a.status) {
      InterpassWeldStatus.outOfLimits => en ? 'OUT OF LIMITS' : 'POZA LIMITEM',
      InterpassWeldStatus.limitsConflict =>
        en ? 'Limits contradict' : 'Sprzeczne limity',
      InterpassWeldStatus.noReadings => en ? 'No readings' : 'Brak pomiarów',
      InterpassWeldStatus.missingPasses =>
        en ? 'Missing reading' : 'Brak pomiaru',
      InterpassWeldStatus.passCountConflict =>
        en ? 'Pass count?' : 'Liczba ściegów?',
      InterpassWeldStatus.passCountMissing =>
        en ? 'No pass count' : 'Brak liczby ściegów',
      InterpassWeldStatus.orderConflict =>
        en ? 'Check times' : 'Sprawdź godziny',
      InterpassWeldStatus.unconfirmed =>
        en ? 'Not confirmed' : 'Niepotwierdzone',
      InterpassWeldStatus.noLimit => en ? 'No WPS limit' : 'Brak limitu z WPS',
      InterpassWeldStatus.ok => en ? 'OK — within limits' : 'OK — w limitach',
    };

/// Wszystkie blokady zielonego werdyktu (lista punktów na karcie stanu).
List<String> interpassBlockers(InterpassAssessment a, {required bool en}) => [
      if (a.failedPasses.isNotEmpty)
        en
            ? 'out of limits: pass ${_passes(a.failedPasses)}'
            : 'poza limitem: ścieg ${_passes(a.failedPasses)}',
      if (a.limits.conflict) en ? 'limits contradict' : 'sprzeczne limity',
      if (a.chrono.isEmpty) en ? 'no readings' : 'brak pomiarów',
      if (a.missingPasses.isNotEmpty)
        en
            ? 'no reading before pass ${_passes(a.missingPasses)}'
            : 'brak pomiaru przed ściegiem ${_passes(a.missingPasses)}',
      if (a.passesBeyondCount.isNotEmpty)
        en
            ? 'pass ${_passes(a.passesBeyondCount)} beyond the pass count'
            : 'ścieg ${_passes(a.passesBeyondCount)} ponad liczbę ściegów',
      if (a.passCount == null) en ? 'no pass count' : 'brak liczby ściegów',
      if (a.orderConflictPasses.isNotEmpty)
        en
            ? 'times vs pass numbers: pass ${_passes(a.orderConflictPasses)}'
            : 'godziny a numery: ścieg ${_passes(a.orderConflictPasses)}',
      if (a.unconfirmedPasses.isNotEmpty)
        en
            ? 'crayon not conclusive: pass ${_passes(a.unconfirmedPasses)}'
            : 'kredka nie rozstrzyga: ścieg ${_passes(a.unconfirmedPasses)}',
      if (a.noLimitPasses.isNotEmpty)
        en
            ? 'no WPS limit: pass ${_passes(a.noLimitPasses)}'
            : 'brak limitu z WPS: ścieg ${_passes(a.noLimitPasses)}',
    ];

/// Opis fazy pomiaru: „przed ściegiem 1 (podgrzanie)” / „przed ściegiem 3”.
String interpassPassLabel(int pass, {required bool en}) => pass <= 1
    ? (en ? 'Before pass 1 (preheat)' : 'Przed ściegiem 1 (podgrzanie)')
    : (en ? 'Before pass $pass' : 'Przed ściegiem $pass');

/// Dopisek do pomiaru: zastąpiony późniejszym / wpisany później.
String interpassReadingFlags(InterpassReading r, InterpassAssessment a,
    {required bool en}) {
  final flags = [
    if (!a.isDecisive(r))
      en ? 'superseded by a later reading' : 'zastąpiony późniejszym pomiarem',
    if (r.backdated)
      '${en ? 'entered' : 'wpisano'} ${interpassDateTime(r.recordedAt)}',
  ];
  return flags.isEmpty ? '' : '(${flags.join('; ')})';
}

/// Wiersz pomiaru „Ścieg 2 · 2026-10-17 07:42 · 180 °C · termometr · OK”.
String interpassReadingLine(
    InterpassReading r, InterpassAssessment a, InterpassUnit unit,
    {required bool en}) {
  final parts = [
    '${en ? 'Pass' : 'Ścieg'} ${r.pass}',
    interpassDateTime(r.at),
    interpassReadingValue(r, unit, en: en),
    r.method.short(en: en),
    interpassCheckLabel(a.checkOf(r), en: en),
    if (r.note.trim().isNotEmpty) r.note.trim(),
  ];
  final flags = interpassReadingFlags(r, a, en: en);
  return flags.isEmpty ? parts.join(' · ') : '${parts.join(' · ')} $flags';
}

/// Wiersz „etykieta — wartość” danych spoiny.
class InterpassLine {
  final String label;
  final String value;
  const InterpassLine(this.label, this.value);
}

String _orDash(String s) => s.trim().isEmpty ? '—' : s.trim();

String _limit(double? c, InterpassUnit unit, String prefix,
        {required bool en}) =>
    c == null
        ? (en ? '— (not entered / per WPS)' : '— (nie wpisano / wg WPS)')
        : '$prefix ${formatInterpassTemp(c, unit, en: en)}';

/// Dane spoiny w kolejności protokołu.
List<InterpassLine> interpassWeldLines(InterpassWeld w, InterpassUnit unit,
    {required bool en}) {
  final l = w.limits;
  return [
    InterpassLine(en ? 'Weld no.' : 'Nr spoiny', _orDash(w.weldNo)),
    InterpassLine(en ? 'Description' : 'Opis', _orDash(w.description)),
    InterpassLine('WPS', _orDash(w.wpsRef)),
    InterpassLine(en ? 'Minimum preheat' : 'Min. podgrzanie',
        _limit(l.preheatMinC, unit, '≥', en: en)),
    InterpassLine(en ? 'Maximum interpass' : 'Maks. międzyściegowa',
        _limit(l.interpassMaxC, unit, '≤', en: en)),
    InterpassLine(
        en ? 'Minimum interpass' : 'Min. międzyściegowa',
        l.interpassMinC == null
            ? (en ? '— (not set)' : '— (nie ustawiono)')
            : '≥ ${formatInterpassTemp(l.interpassMinC!, unit, en: en)}'),
    InterpassLine(
        en ? 'Measuring method' : 'Metoda pomiaru', w.method.label(en: en)),
    InterpassLine(en ? 'Number of passes' : 'Liczba ściegów',
        w.passCount?.toString() ?? '—'),
  ];
}

/// Protokół tekstowy do udostępnienia (komunikator, e-mail).
String interpassProtocolText(InterpassWeld w, InterpassUnit unit,
    {required bool en}) {
  final a = w.assess();
  final b = StringBuffer()
    ..writeln(en
        ? 'PREHEAT AND INTERPASS TEMPERATURE RECORD'
        : 'PROTOKÓŁ TEMPERATURY PODGRZANIA I MIĘDZYŚCIEGOWEJ')
    ..writeln();
  for (final l in interpassWeldLines(w, unit, en: en)) {
    b.writeln('${l.label}: ${l.value}');
  }
  b
    ..writeln()
    ..writeln(
        '${en ? 'VERDICT' : 'WERDYKT'}: ${interpassStatusText(a, en: en)}')
    ..writeln()
    ..writeln(en ? 'READINGS (in time order)' : 'POMIARY (w kolejności czasu)');
  if (a.chrono.isEmpty) {
    b.writeln(en ? '— no readings —' : '— brak pomiarów —');
  } else {
    for (final r in a.chrono) {
      b.writeln('- ${interpassReadingLine(r, a, unit, en: en)}');
    }
  }
  if (unit == InterpassUnit.f) {
    b
      ..writeln()
      ..writeln(en
          ? 'Values are stored in °C and shown here in °F.'
          : 'Wartości zapisane w °C, tu pokazane w °F.');
  }
  b
    ..writeln()
    ..writeln(interpassPassRule(en: en))
    ..writeln(interpassBoundaryNote(en: en))
    ..writeln()
    ..writeln(interpassDisclaimer(en: en))
    ..write('Fitter Welder Pro');
  return b.toString();
}
