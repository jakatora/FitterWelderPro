/// Raport postępu dla szefa (dzienny / tygodniowy / za okres): wspólne
/// formatowanie liczb i wierszy dla ekranu, tekstu do wysłania i PDF, oraz
/// seria dzienna do wykresu.
///
/// Czysty Dart.
library;

import '../quotes/quote_calculator.dart' show formatQty;
import '../weld_journal/weld_dates.dart';
import '../weld_journal/weld_entry.dart';
import 'progress_filter.dart';
import 'progress_forecast.dart';
import 'weld_progress.dart';
import 'work_calendar.dart';

/// Liczba bez zbędnych zer; przecinek po polsku, kropka po angielsku.
String progressNum(double v, {required bool en, int decimals = 1}) {
  final s = formatQty(v, decimals: decimals);
  return en ? s.replaceAll(',', '.') : s;
}

/// „33%" (jedno miejsce po przecinku poniżej 10%).
String progressPct(double v, {required bool en}) =>
    '${progressNum(v, en: en, decimals: v.abs() >= 10 ? 0 : 1)}%';

/// DI z „≈", gdy część spoin liczono z OD / 25,4.
String progressDi(double di, {required bool en, bool approx = false}) =>
    '${approx ? '≈ ' : ''}${progressNum(di, en: en)} DI';

/// „1 spoina", „3 spoiny", „5 spoin" / „1 weld", „3 welds".
String weldsCount(int n, {required bool en}) {
  if (en) return '$n ${n == 1 ? 'weld' : 'welds'}';
  if (n == 1) return '1 spoina';
  final m10 = n % 10, m100 = n % 100;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n spoiny';
  return '$n spoin';
}

/// Spoiny wspólne z innym spawaczem: „1 wspólna", „3 wspólne", „5 wspólnych".
String sharedCount(int n, {required bool en}) {
  if (en) return '$n shared';
  if (n == 1) return '1 wspólna';
  final m10 = n % 10, m100 = n % 100;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n wspólne';
  return '$n wspólnych';
}

/// Jednostka zakresu: „spoin" / „DI".
String scopeUnitLabel(ScopeUnit u, {required bool en}) => switch (u) {
      ScopeUnit.welds => en ? 'welds' : 'spoin',
      ScopeUnit.di => 'DI',
    };

/// Wartość w jednostce zakresu, np. „120 DI" albo „35 spoin".
String scopeAmount(double v, ScopeUnit u, {required bool en}) => switch (u) {
      ScopeUnit.welds => en
          ? '${progressNum(v, en: en)} welds'
          : '${progressNum(v, en: en)} spoin',
      ScopeUnit.di => '${progressNum(v, en: en)} DI',
    };

const List<String> _weekdaysPl = ['pn', 'wt', 'śr', 'czw', 'pt', 'sob', 'nd'];
const List<String> _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdayShort(DateTime d, {required bool en}) =>
    (en ? _weekdaysEn : _weekdaysPl)[d.weekday - 1];

/// „2026-10-14 (śr)".
String dayLabel(DateTime d, {required bool en}) =>
    '${isoDate(d)} (${weekdayShort(d, en: en)})';

/// Każdy dzień kalendarzowy [window] z liczbą spoin i DI (zera też).
List<DayProgress> dailySeries(Iterable<WeldEntry> entries, DayRange window) {
  final acc = <DateTime, (int, double)>{};
  for (final e in entries) {
    if (e.isDeleted) continue;
    final d = parseIsoDay(e.date);
    if (d == null || !window.contains(d)) continue;
    final prev = acc[d] ?? (0, 0.0);
    acc[d] = (prev.$1 + 1, prev.$2 + (weldDiameterInches(e)?.inches ?? 0));
  }
  final out = <DayProgress>[];
  for (var d = window.from; !d.isAfter(window.to); d = addDays(d, 1)) {
    final v = acc[d];
    out.add(DayProgress(d, welds: v?.$1 ?? 0, di: v?.$2 ?? 0));
  }
  return out;
}

/// Dni na wykresie: koniec okresu (albo dziś dla „Całość"), co najmniej 7
/// i najwyżej 31 dni wstecz.
DayRange chartWindow({
  required DayRange? range,
  required DateTime today,
  DateTime? firstWeld,
}) {
  final end = range?.to ?? dayOnly(today);
  var start = range?.from ?? firstWeld ?? end;
  if (start.isAfter(end)) start = end;
  final span = end.difference(start).inDays + 1;
  if (span > 31) start = addDays(end, -30);
  if (span < 7) start = addDays(end, -6);
  return DayRange(start, end);
}

/// Wszystko, co trafia do raportu.
class ProgressReport {
  final ProgressFilter filter;
  final DayRange? range;
  final ProgressSummary summary;
  final ProgressPace? pace;
  final ProgressForecast? forecast;
  final DateTime generatedAt;

  const ProgressReport({
    required this.filter,
    required this.range,
    required this.summary,
    required this.pace,
    required this.forecast,
    required this.generatedAt,
  });

  bool get isDaily => filter.period == ProgressPeriod.today;
  bool get isWeekly => filter.period == ProgressPeriod.week;

  /// „Raport dzienny" / „Raport tygodniowy" / „Raport postępu robót".
  String title({required bool en}) {
    if (isDaily) return en ? 'Daily progress report' : 'Raport dzienny';
    if (isWeekly) return en ? 'Weekly progress report' : 'Raport tygodniowy';
    return en ? 'Work progress report' : 'Raport postępu robót';
  }

  /// „2026-10-14 (śr)" albo „2026-10-12 – 2026-10-14" albo „całość".
  String periodText({required bool en}) {
    final r = range;
    if (r == null) return en ? 'all dates' : 'wszystkie daty';
    if (r.from == r.to) return dayLabel(r.from, en: en);
    return '${isoDate(r.from)} – ${isoDate(r.to)}';
  }

  /// Nazwa pliku PDF, np. `Raport_postepu_Blok_4_2026-10-14.pdf`.
  String fileName({required bool en}) {
    String safe(String s) => s
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final parts = <String>[
      en ? 'Progress_report' : 'Raport_postepu',
      if (safe(filter.project).isNotEmpty) safe(filter.project),
      if (safe(filter.testPackage).isNotEmpty) safe(filter.testPackage),
      isoDate(range?.to ?? generatedAt),
    ];
    return '${parts.join('_')}.pdf';
  }
}

/// „Wykonano" — spoiny i DI.
String doneLine(ProgressSummary s, {required bool en}) =>
    '${weldsCount(s.welds, en: en)} · '
    '${progressDi(s.di, en: en, approx: s.diApprox)}';

/// „OK 2 · NOK 0 · czeka na odbiór 3".
String statusLine(ProgressSummary s, {required bool en}) => [
      'OK ${s.statusOk}',
      'NOK ${s.statusNok}',
      '${en ? 'awaiting acceptance' : 'czeka na odbiór'} ${s.statusPending}',
      if (s.statusOther > 0) '${en ? 'other' : 'inne'} ${s.statusOther}',
    ].join(' · ');

/// Tempo, np. „9,5 DI/dzień rob. · 4,2 spoiny/dzień rob.".
String paceLine(ProgressPace p, {required bool en}) {
  final perDay = en ? '/working day' : '/dzień rob.';
  return '${progressNum(p.diPerDay, en: en)} DI$perDay · '
      '${progressNum(p.weldsPerDay, en: en)} '
      '${en ? 'welds' : 'spoin'}$perDay';
}

/// Okno tempa, np. „ostatnie 10 dni rob.: 2026-10-01 – 2026-10-14".
String paceWindowLine(ProgressPace p, {required bool en}) {
  final shorter = p.workingDays < p.requestedDays;
  final head = en
      ? 'last ${p.workingDays} working day${p.workingDays == 1 ? '' : 's'}'
      : 'ostatnie ${p.workingDays} dni rob.';
  final note = shorter
      ? (en ? ' (work started later)' : ' (praca zaczęła się później)')
      : '';
  return '$head: ${isoDate(p.from)} – ${isoDate(p.to)}$note';
}

/// Odsetek napraw: „33% (1 z 3 zbadanych RT/UT)" albo „brak badań RT/UT".
String repairRateText(QualityCounts q, {required bool en}) {
  final rate = q.repairRatePct;
  if (rate == null) return en ? 'no RT/UT results' : 'brak wyników RT/UT';
  return en
      ? '${progressPct(rate, en: en)} (${q.volumetricRejected} of '
          '${q.volumetricExamined} RT/UT examined)'
      : '${progressPct(rate, en: en)} (${q.volumetricRejected} z '
          '${q.volumetricExamined} zbadanych RT/UT)';
}

/// Naprawy: „naprawy 2 (R1 2, R2+ 0)".
String repairsText(QualityCounts q, {required bool en}) =>
    '${en ? 'repairs' : 'naprawy'} ${q.repairs} '
    '(R1 ${q.r1}, R2+ ${q.r2plus})';

/// Wiersz spawacza do tekstu i PDF.
String welderLine(WelderProgress w, {required bool en}) {
  final name = w.isUnstamped ? (en ? 'no stamp' : 'bez stempla') : w.stamp;
  final shared =
      w.sharedWelds == 0 ? '' : ' (${sharedCount(w.sharedWelds, en: en)})';
  return '$name — ${weldsCount(w.welds, en: en)}$shared · '
      '${progressDi(w.diShare, en: en, approx: w.diApprox)} · '
      '${repairsText(w.quality, en: en)} · '
      '${en ? 'repair rate' : 'odsetek napraw'} '
      '${repairRateText(w.quality, en: en)}';
}

/// Opis prognozy (kilka linii).
List<String> forecastLines(ProgressForecast f, {required bool en}) {
  final u = f.unit;
  final out = <String>[
    '${en ? 'Scope' : 'Zakres'}: ${scopeAmount(f.total, u, en: en)} · '
        '${en ? 'done' : 'wykonano'} ${scopeAmount(f.done, u, en: en)} '
        '(${progressPct(f.pct, en: en)})'
        '${f.isDone ? '' : ' · ${en ? 'left' : 'zostało'} ${scopeAmount(f.remaining, u, en: en)}'}',
  ];
  if (f.isDone) {
    out.add(en ? 'Scope completed.' : 'Zakres wykonany.');
    return out;
  }
  final finish = f.finish;
  if (finish == null) {
    out.add(en
        ? 'Finish date: no pace yet — log some welds first.'
        : 'Data końca: brak tempa — najpierw muszą być spoiny w dzienniku.');
  } else {
    out.add(en
        ? 'Finish at the current pace: ${dayLabel(finish, en: en)} '
            '(${f.workingDaysNeeded} working days)'
        : 'Koniec przy obecnym tempie: ${dayLabel(finish, en: en)} '
            '(${f.workingDaysNeeded} dni rob.)');
  }
  final due = f.due;
  if (due != null) {
    if (f.dueMissed) {
      out.add(en
          ? 'Deadline ${isoDate(due)}: no working days left.'
          : 'Termin ${isoDate(due)}: nie zostały dni robocze.');
    } else if (f.requiredPerDay != null) {
      final need = f.requiredPerDay!;
      final unit = u == ScopeUnit.di
          ? 'DI'
          : (en ? 'welds' : 'spoin');
      final verdict = switch (f.onTrack) {
        true => en ? 'current pace is enough' : 'obecne tempo wystarczy',
        false => en ? 'current pace is too slow' : 'obecne tempo za małe',
        null => '',
      };
      out.add(en
          ? 'Deadline ${isoDate(due)}: ${progressNum(need, en: en)} $unit'
              '/working day needed (${f.workingDaysToDue} days)'
              '${verdict.isEmpty ? '' : ' — $verdict'}'
          : 'Termin ${isoDate(due)}: trzeba ${progressNum(need, en: en)} '
              '$unit/dzień rob. (${f.workingDaysToDue} dni rob.)'
              '${verdict.isEmpty ? '' : ' — $verdict'}');
    }
  }
  return out;
}

/// Uwagi o danych: DI przybliżone, spoiny bez OD, bez daty.
List<String> dataNotes(ProgressSummary s, {required bool en}) => [
      if (s.approxWelds > 0)
        en
            ? '≈ ${weldsCount(s.approxWelds, en: en)} with OD outside the NPS '
                'table — DI ≈ OD / 25.4'
            : '≈ ${weldsCount(s.approxWelds, en: en)} z OD spoza tabeli NPS '
                '— DI ≈ OD / 25,4',
      if (s.noOdWelds > 0)
        en
            ? '${weldsCount(s.noOdWelds, en: en)} without OD — no DI'
            : '${weldsCount(s.noOdWelds, en: en)} bez OD — bez DI',
      if (s.undatedWelds > 0)
        en
            ? '${weldsCount(s.undatedWelds, en: en)} without a valid date'
            : '${weldsCount(s.undatedWelds, en: en)} bez poprawnej daty',
    ];

/// Krótkie definicje wskaźników (stopka raportu i PDF).
List<String> definitionLines({required bool en}) => en
    ? const [
        'Weld done = live journal entry (any status; a repair is the same weld).',
        'DI = NPS size in inches from OD (B36.10M/B36.19M); ≈ = OD / 25.4.',
        'A weld with two welders (root/cap) appears under both; its DI is '
            'split equally, crew totals count it once.',
        'Repair rate = welds rejected by RT/UT ÷ welds examined by RT/UT '
            '(including results before a repair).',
        'Pace = output of the last N working days ÷ N (Mon–Fri, Sat optional).',
      ]
    : const [
        'Spoina wykonana = nieusunięty wpis dziennika (każdy status; naprawa to '
            'ta sama spoina).',
        'DI = rozmiar NPS w calach z OD (B36.10M/B36.19M); ≈ = OD / 25,4.',
        'Spoina z dwoma spawaczami (grań/lico) jest u obu, DI dzielone po '
            'równo, suma brygady liczy ją raz.',
        'Odsetek napraw = spoiny odrzucone w RT/UT ÷ spoiny zbadane RT/UT '
            '(łącznie z wynikami sprzed naprawy).',
        'Tempo = wynik ostatnich N dni roboczych ÷ N (pn–pt, sobota opcjonalnie).',
      ];

/// Tekst raportu do wysłania (SMS, WhatsApp, e-mail).
String buildProgressReportText(ProgressReport r, {required bool en}) {
  final s = r.summary;
  final b = StringBuffer()
    ..writeln('${r.title(en: en).toUpperCase()} — ${r.periodText(en: en)}')
    ..writeln(r.filter.describeScope(en: en))
    ..writeln();
  if (s.isEmpty) {
    b.writeln(en
        ? 'No welds in the journal for this period.'
        : 'Brak spoin w dzienniku w tym okresie.');
  } else {
    b
      ..writeln('${en ? 'Done' : 'Wykonano'}: ${doneLine(s, en: en)}')
      ..writeln('Status: ${statusLine(s, en: en)}');
  }
  final p = r.pace;
  if (p != null) {
    b.writeln('${en ? 'Pace' : 'Tempo'}: ${paceLine(p, en: en)} '
        '(${paceWindowLine(p, en: en)})');
  }
  if (!r.isDaily && s.days.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Day by day:' : 'Dzień po dniu:');
    final days = s.days.length > 31 ? s.days.sublist(s.days.length - 31) : s.days;
    for (final d in days) {
      b.writeln('• ${dayLabel(d.day, en: en)} — ${weldsCount(d.welds, en: en)}'
          ' · ${progressNum(d.di, en: en)} DI');
    }
  }
  if (s.welders.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Welders:' : 'Spawacze:');
    for (final w in s.welders) {
      b.writeln('• ${welderLine(w, en: en)}');
    }
    b.writeln(en
        ? 'Crew total: ${doneLine(s, en: en)} (a weld with two welders counts once)'
        : 'Brygada razem: ${doneLine(s, en: en)} (spoina z dwoma spawaczami '
            'liczona raz)');
  }
  if (!s.isEmpty) {
    b
      ..writeln()
      ..writeln('${en ? 'Quality' : 'Jakość'}: ${repairsText(s.crew, en: en)} · '
          '${en ? 'repair rate' : 'odsetek napraw'} '
          '${repairRateText(s.crew, en: en)}');
    if (s.crew.toExamine > 0) {
      b.writeln(en
          ? 'Additional examinations due (B31.3 §341.3.4): ${s.crew.toExamine}'
          : 'Do dobadania (B31.3 §341.3.4): ${s.crew.toExamine}');
    }
  }
  final f = r.forecast;
  if (f != null) {
    b
      ..writeln()
      ..writeln(en ? 'Forecast:' : 'Prognoza:');
    for (final line in forecastLines(f, en: en)) {
      b.writeln(line);
    }
  }
  final notes = dataNotes(s, en: en);
  if (notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Notes:' : 'Uwagi:');
    for (final n in notes) {
      b.writeln('• $n');
    }
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final g = r.generatedAt;
  b
    ..writeln()
    ..write('Fitter Welder Pro · ${isoDate(g)} ${two(g.hour)}:${two(g.minute)}');
  return b.toString();
}
