/// Postęp robót z dziennika spoin: ile spoin i cali-średnic (DI), dzień po
/// dniu, kto ile zespawał, ile było napraw i jakie jest tempo.
///
/// Definicje (te same w UI, w raporcie tekstowym i w PDF):
///
/// * **Spoina wykonana** — nieusunięty wpis dziennika. Status nie ma
///   znaczenia: PENDING to spoina zespawana, czekająca na odbiór; NOK też
///   została zespawana. Naprawa (R1, R2) to ta sama spoina — nie dolicza się
///   drugi raz do postępu.
/// * **DI (cal-średnica, dia-inch)** — rozmiar NPS spoiny w calach, z OD przez
///   tabelę B36.10M/B36.19M ([npsInchesForOd], ta sama co w wycenach). OD
///   spoza tabeli → OD / 25,4, oznaczone „≈". Spoina bez OD (puste, nie liczba)
///   nie wnosi DI i jest liczona osobno.
/// * **Spawacz** — stemple spawacza, grani i lica ([WeldEntry.stamps]). Spoina
///   z dwoma spawaczami jest w wierszu każdego z nich (obaj za nią
///   odpowiadają), ale DI i „udział" dzielą się po równo — suma DI spawaczy =
///   DI brygady, a suma brygady liczy każdą spoinę raz.
/// * **Odsetek napraw (RT/UT)** — spoiny odrzucone w RT lub UT / spoiny
///   zbadane RT lub UT. Liczy się także wynik sprzed naprawy (zapisany w
///   rekordzie naprawy): naprawiona spoina czeka na ponowne badanie i nie ma
///   już bieżącego wyniku, a jej NOK nadal świadczy o jakości. Bez badań
///   RT/UT odsetka nie ma (nie podstawiamy innego mianownika po cichu).
/// * **Tempo** — DI (i spoiny) z ostatnich N dni roboczych / N. Dziś liczy
///   się do tempa, gdy ma już wpisy; inaczej okno kończy się wczoraj. Okno nie
///   sięga przed pierwszą spoinę zakresu.
///
/// Liczniki napraw i §341.3.4 („do dobadania") pochodzą z
/// [computeWeldJournalStats] — tej samej funkcji, której używa podsumowanie
/// NDT dziennika.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import '../../utils/decimal_parse.dart';
import '../quotes/quote_calculator.dart' show npsInchesForOd;
import '../weld_journal/weld_entry.dart';
import '../weld_journal/weld_ndt.dart';
import '../weld_journal/weld_stats.dart';
import 'work_calendar.dart';

/// DI jednej spoiny.
class WeldDi {
  final double inches;

  /// OD spoza tabeli NPS — DI ≈ OD / 25,4.
  final bool approx;

  const WeldDi(this.inches, {this.approx = false});
}

/// DI spoiny z jej OD albo null, gdy OD nie ma albo nie jest liczbą > 0.
WeldDi? weldDiameterInches(WeldEntry e) {
  final od = parseDecimal(e.od);
  if (od == null || od <= 0) return null;
  final nps = npsInchesForOd(od);
  if (nps != null) return WeldDi(nps);
  return WeldDi(od / 25.4, approx: true);
}

bool _volumetricResult(Map<NdtMethod, WeldNdt> ndt) =>
    ndt.entries.any((x) => x.key.isVolumetric && x.value.hasResult);

bool _volumetricReject(Map<NdtMethod, WeldNdt> ndt) =>
    ndt.entries.any((x) => x.key.isVolumetric && x.value.isRejected);

/// Spoina ma wynik RT lub UT — teraz albo sprzed którejś naprawy.
bool weldVolumetricExaminedEver(WeldEntry e) =>
    _volumetricResult(e.ndt) || e.repairs.any((r) => _volumetricResult(r.prevNdt));

/// Spoina została odrzucona w RT lub UT — teraz albo przed którąś naprawą.
bool weldVolumetricRejectedEver(WeldEntry e) =>
    _volumetricReject(e.ndt) || e.repairs.any((r) => _volumetricReject(r.prevNdt));

/// Jakość grupy spoin (brygady albo spawacza).
class QualityCounts {
  final int welds;

  /// Rekordy napraw (R1, R2, …) i spoiny z co najmniej jedną naprawą.
  final int repairs;
  final int repairedWelds;

  /// Naprawy pierwsze (R1) i kolejne (R2, R3, …).
  final int r1;
  final int r2plus;

  /// Spoiny zbadane RT/UT i z nich odrzucone (patrz definicja w nagłówku).
  final int volumetricExamined;
  final int volumetricRejected;

  /// ASME B31.3 §341.3.4 — dodatkowe badania do wykonania (z weld_stats).
  final int toExamine;

  const QualityCounts({
    this.welds = 0,
    this.repairs = 0,
    this.repairedWelds = 0,
    this.r1 = 0,
    this.r2plus = 0,
    this.volumetricExamined = 0,
    this.volumetricRejected = 0,
    this.toExamine = 0,
  });

  /// Odsetek napraw RT/UT w %, albo null, gdy nic nie zbadano RT/UT.
  double? get repairRatePct => volumetricExamined == 0
      ? null
      : volumetricRejected * 100 / volumetricExamined;

  /// Spoiny naprawiane / wszystkie spoiny w % (informacyjnie).
  double get repairedWeldsPct => welds == 0 ? 0 : repairedWelds * 100 / welds;
}

/// Jeden dzień pracy.
class DayProgress {
  final DateTime day;
  final int welds;
  final double di;
  const DayProgress(this.day, {this.welds = 0, this.di = 0});
}

/// Jeden spawacz.
class WelderProgress {
  /// Stempel; „—", gdy spoina nie ma żadnego.
  final String stamp;

  /// Spoiny z jego stemplem (spawacz, grań lub lico).
  final int welds;

  /// Z tego spoiny wspólne z innym spawaczem.
  final int sharedWelds;

  /// Udział: 1 / liczba spawaczy spoiny, zsumowany.
  final double weldsShare;

  /// DI dzielone po równo między spawaczy spoiny.
  final double diShare;

  /// Część DI z OD spoza tabeli (≈).
  final bool diApprox;

  final QualityCounts quality;

  const WelderProgress({
    required this.stamp,
    required this.welds,
    required this.sharedWelds,
    required this.weldsShare,
    required this.diShare,
    required this.diApprox,
    required this.quality,
  });

  bool get isUnstamped => stamp == kNoStamp;
}

/// Klucz grupy spoin bez stempla — ten sam, którego używa weld_stats.
const String kNoStamp = '—';

class ProgressSummary {
  /// Spoiny wykonane (każda raz).
  final int welds;

  final double di;

  /// Spoiny, których DI liczono z OD / 25,4.
  final int approxWelds;

  /// Spoiny bez OD (bez DI).
  final int noOdWelds;

  /// Spoiny bez poprawnej daty (nie ma ich na wykresie dziennym).
  final int undatedWelds;

  /// Spoiny wg statusu: OK, NOK, PENDING, pozostałe (stare bazy).
  final int statusOk;
  final int statusNok;
  final int statusPending;
  final int statusOther;

  /// Dni z wpisami, rosnąco.
  final List<DayProgress> days;

  /// Spawacze: najwięcej DI pierwsi.
  final List<WelderProgress> welders;

  /// Jakość całej brygady (każda spoina raz).
  final QualityCounts crew;

  const ProgressSummary({
    required this.welds,
    required this.di,
    required this.approxWelds,
    required this.noOdWelds,
    required this.undatedWelds,
    required this.statusOk,
    required this.statusNok,
    required this.statusPending,
    required this.statusOther,
    required this.days,
    required this.welders,
    required this.crew,
  });

  static const ProgressSummary empty = ProgressSummary(
    welds: 0,
    di: 0,
    approxWelds: 0,
    noOdWelds: 0,
    undatedWelds: 0,
    statusOk: 0,
    statusNok: 0,
    statusPending: 0,
    statusOther: 0,
    days: [],
    welders: [],
    crew: QualityCounts(),
  );

  bool get isEmpty => welds == 0;
  bool get diApprox => approxWelds > 0;

  /// Dzień [d] (zero, gdy bez wpisów).
  DayProgress dayOf(DateTime d) {
    final k = dayOnly(d);
    for (final x in days) {
      if (x.day == k) return x;
    }
    return DayProgress(k);
  }
}

class _WelderAcc {
  final String stamp;
  int welds = 0, shared = 0, r1 = 0, r2plus = 0, vol = 0, volNok = 0;
  double share = 0, di = 0;
  bool approx = false;
  _WelderAcc(this.stamp);
}

int _r1(WeldEntry e) => e.repairs.where((r) => r.seq <= 1).length;
int _r2plus(WeldEntry e) => e.repairs.where((r) => r.seq >= 2).length;

/// Podsumowanie [entries] (już przefiltrowanych; usunięte są pomijane).
ProgressSummary summarizeProgress(Iterable<WeldEntry> entries) {
  final live = entries.where((e) => !e.isDeleted).toList();
  if (live.isEmpty) return ProgressSummary.empty;

  var di = 0.0;
  var approx = 0, noOd = 0, undated = 0;
  var ok = 0, nok = 0, pending = 0, other = 0;
  var r1 = 0, r2plus = 0, vol = 0, volNok = 0;
  final days = <DateTime, (int, double)>{};
  final welders = <String, _WelderAcc>{};

  for (final e in live) {
    final d = weldDiameterInches(e);
    final inches = d?.inches ?? 0;
    if (d == null) {
      noOd++;
    } else {
      di += inches;
      if (d.approx) approx++;
    }
    switch (e.status) {
      case WeldStatus.ok:
        ok++;
      case WeldStatus.nok:
        nok++;
      case WeldStatus.pending:
        pending++;
      default:
        other++;
    }
    final day = parseIsoDay(e.date);
    if (day == null) {
      undated++;
    } else {
      final prev = days[day] ?? (0, 0.0);
      days[day] = (prev.$1 + 1, prev.$2 + inches);
    }
    final eR1 = _r1(e), eR2 = _r2plus(e);
    final eVol = weldVolumetricExaminedEver(e);
    final eNok = weldVolumetricRejectedEver(e);
    r1 += eR1;
    r2plus += eR2;
    if (eVol) vol++;
    if (eNok) volNok++;

    final stamps = e.stamps.isEmpty ? const [kNoStamp] : e.stamps;
    final part = 1 / stamps.length;
    for (final s in stamps) {
      final a = welders.putIfAbsent(s.toLowerCase(), () => _WelderAcc(s));
      a.welds++;
      if (stamps.length > 1) a.shared++;
      a.share += part;
      a.di += inches * part;
      if (d?.approx ?? false) a.approx = true;
      a.r1 += eR1;
      a.r2plus += eR2;
      if (eVol) a.vol++;
      if (eNok) a.volNok++;
    }
  }

  // Naprawy i §341.3.4 — z podsumowania NDT dziennika.
  final stats = computeWeldJournalStats(live);
  final byWelder = {for (final g in stats.byWelder) g.key.toLowerCase(): g};
  final toExamineCrew =
      stats.byWelder.fold<int>(0, (s, g) => s + g.toExamine);

  final welderList = [
    for (final a in welders.values)
      WelderProgress(
        stamp: a.stamp,
        welds: a.welds,
        sharedWelds: a.shared,
        weldsShare: a.share,
        diShare: a.di,
        diApprox: a.approx,
        quality: QualityCounts(
          welds: a.welds,
          repairs: byWelder[a.stamp.toLowerCase()]?.repairs ?? 0,
          repairedWelds: byWelder[a.stamp.toLowerCase()]?.repairedWelds ?? 0,
          r1: a.r1,
          r2plus: a.r2plus,
          volumetricExamined: a.vol,
          volumetricRejected: a.volNok,
          toExamine: byWelder[a.stamp.toLowerCase()]?.toExamine ?? 0,
        ),
      ),
  ]..sort((x, y) {
      // Bez stempla zawsze na końcu.
      if (x.isUnstamped != y.isUnstamped) return x.isUnstamped ? 1 : -1;
      final byDi = y.diShare.compareTo(x.diShare);
      if (byDi != 0) return byDi;
      final byWelds = y.welds.compareTo(x.welds);
      if (byWelds != 0) return byWelds;
      return x.stamp.toLowerCase().compareTo(y.stamp.toLowerCase());
    });

  final dayList = [
    for (final e in days.entries)
      DayProgress(e.key, welds: e.value.$1, di: e.value.$2),
  ]..sort((a, b) => a.day.compareTo(b.day));

  return ProgressSummary(
    welds: live.length,
    di: di,
    approxWelds: approx,
    noOdWelds: noOd,
    undatedWelds: undated,
    statusOk: ok,
    statusNok: nok,
    statusPending: pending,
    statusOther: other,
    days: dayList,
    welders: welderList,
    crew: QualityCounts(
      welds: live.length,
      repairs: stats.total.repairs,
      repairedWelds: stats.total.repairedWelds,
      r1: r1,
      r2plus: r2plus,
      volumetricExamined: vol,
      volumetricRejected: volNok,
      toExamine: toExamineCrew,
    ),
  );
}

/// Wpisy zakresu z datą [today] — „dziś już coś wpisano".
bool isTodayLogged(Iterable<WeldEntry> scope, DateTime today) {
  final t = dayOnly(today);
  return scope.any((e) => !e.isDeleted && parseIsoDay(e.date) == t);
}

/// Tempo pracy z okna ostatnich dni roboczych.
class ProgressPace {
  final DateTime from;
  final DateTime to;

  /// Dni robocze w oknie (mianownik).
  final int workingDays;

  /// Ile dni roboczych chciano (N); [workingDays] bywa mniejsze, gdy praca
  /// zaczęła się później.
  final int requestedDays;

  final int welds;
  final double di;

  const ProgressPace({
    required this.from,
    required this.to,
    required this.workingDays,
    required this.requestedDays,
    required this.welds,
    required this.di,
  });

  double get weldsPerDay => workingDays == 0 ? 0 : welds / workingDays;
  double get diPerDay => workingDays == 0 ? 0 : di / workingDays;
}

/// Tempo z ostatnich [workingDays] dni roboczych zakresu [scope] (bez filtra
/// okresu) albo null, gdy nie ma ani jednej spoiny z datą do dziś.
///
/// Okno kończy się dziś, jeśli dziś są wpisy, inaczej wczoraj. Zaczyna się
/// [workingDays] dni roboczych wcześniej, ale nie przed pierwszą spoiną.
/// Spoiny z dni wolnych w oknie (nadgodziny w sobotę) liczą się do sumy, nie
/// do mianownika. Spoiny z datą w przyszłości (literówka) nie liczą się.
ProgressPace? computePace(
  Iterable<WeldEntry> scope, {
  required DateTime today,
  required WorkWeek week,
  int workingDays = 10,
}) {
  final n = math.max(1, workingDays);
  final t = dayOnly(today);
  final dated = <(DateTime, WeldEntry)>[
    for (final e in scope)
      if (!e.isDeleted)
        if (parseIsoDay(e.date) case final d? when !d.isAfter(t)) (d, e),
  ];
  if (dated.isEmpty) return null;
  final end = isTodayLogged(scope, t) ? t : addDays(t, -1);
  var start = week.windowStart(end, n);
  final first = dated.map((x) => x.$1).reduce((a, b) => a.isBefore(b) ? a : b);
  if (first.isAfter(start)) start = first;
  if (start.isAfter(end)) return null;
  var welds = 0;
  var di = 0.0;
  for (final (d, e) in dated) {
    if (d.isBefore(start) || d.isAfter(end)) continue;
    welds++;
    di += weldDiameterInches(e)?.inches ?? 0;
  }
  final days = math.max(1, week.countWorkingDays(start, end));
  return ProgressPace(
    from: start,
    to: end,
    workingDays: days,
    requestedDays: n,
    welds: welds,
    di: di,
  );
}
