// Filtr postępu (projekt, pakiet, warsztat/obiekt, okres) i raport dla
// szefa: tekst, odmiana „spoina/spoiny/spoin", okno wykresu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/progress/progress_filter.dart';
import 'package:cut_list_app/domain/progress/progress_forecast.dart';
import 'package:cut_list_app/domain/progress/progress_report.dart';
import 'package:cut_list_app/domain/progress/weld_progress.dart';
import 'package:cut_list_app/domain/progress/work_calendar.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';

import '../../support/weld_fixtures.dart';

void main() {
  // Środa 2026-10-14.
  final today = DateTime(2026, 10, 14, 9);

  group('okres', () {
    test('dziś / tydzień od poniedziałku / miesiąc od 1. / całość', () {
      DayRange? r(ProgressPeriod p) =>
          ProgressFilter(period: p).rangeFor(today);
      expect(r(ProgressPeriod.today),
          DayRange(DateTime(2026, 10, 14), DateTime(2026, 10, 14)));
      expect(r(ProgressPeriod.week),
          DayRange(DateTime(2026, 10, 12), DateTime(2026, 10, 14)));
      expect(r(ProgressPeriod.month),
          DayRange(DateTime(2026, 10, 1), DateTime(2026, 10, 14)));
      expect(r(ProgressPeriod.all), isNull);
    });

    test('własny zakres odwrócony jest prostowany', () {
      final f = ProgressFilter(
        period: ProgressPeriod.custom,
        customFrom: DateTime(2026, 9, 30),
        customTo: DateTime(2026, 9, 1),
      );
      expect(f.rangeFor(today),
          DayRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
    });

    test('wpis bez daty: poza okresem z granicami, w „całości"', () {
      final w = weld('a', date: '');
      expect(const ProgressFilter(period: ProgressPeriod.week).matches(w, today),
          isFalse);
      expect(const ProgressFilter(period: ProgressPeriod.all).matches(w, today),
          isTrue);
    });
  });

  group('zakres pracy', () {
    final welds = [
      weld('a', project: 'Blok 4').copyWith(
          testPackage: 'TP-01', shopField: WeldLocation.field),
      weld('b', project: 'blok 4 ').copyWith(
          testPackage: 'tp-01', shopField: WeldLocation.shop),
      weld('c', project: 'Blok 4').copyWith(testPackage: 'TP-02'),
      weld('d', project: 'Inny').copyWith(testPackage: 'TP-01'),
      weld('e', project: 'Blok 4', deletedAt: 5),
    ];

    test('projekt i pakiet bez wielkości liter; usunięte nigdy', () {
      const f = ProgressFilter(project: 'Blok 4', testPackage: 'TP-01');
      expect(f.scopeOf(welds).map((e) => e.id), ['a', 'b']);
      expect(const ProgressFilter(project: 'Blok 4').scopeOf(welds),
          hasLength(3));
      expect(const ProgressFilter().scopeOf(welds), hasLength(4));
    });

    test('warsztat / obiekt; spoina bez oznaczenia tylko we „wszystkich"', () {
      const shop = ProgressFilter(location: ProgressLocation.shop);
      const field = ProgressFilter(location: ProgressLocation.field);
      expect(shop.scopeOf(welds).map((e) => e.id), ['b']);
      expect(field.scopeOf(welds).map((e) => e.id), ['a']);
    });

    test('listy projektów i pakietów: bez duplikatów, alfabetycznie', () {
      expect(progressProjects(welds), ['Blok 4', 'Inny']);
      expect(progressPackages(welds, 'BLOK 4'), ['TP-01', 'TP-02']);
      expect(progressPackages(welds, ''), ['TP-01', 'TP-02']);
    });

    test('opis zakresu do nagłówka raportu', () {
      const f = ProgressFilter(
          project: 'Blok 4',
          testPackage: 'TP-01',
          location: ProgressLocation.field);
      expect(f.describeScope(en: false),
          'Projekt: Blok 4 · Pakiet: TP-01 · Obiekt (montaż)');
      expect(const ProgressFilter().describeScope(en: true), 'All projects');
    });
  });

  group('raport', () {
    test('odmiana: 1 spoina, 2 spoiny, 5 spoin, 12 spoin, 22 spoiny', () {
      expect(weldsCount(1, en: false), '1 spoina');
      expect(weldsCount(2, en: false), '2 spoiny');
      expect(weldsCount(5, en: false), '5 spoin');
      expect(weldsCount(12, en: false), '12 spoin');
      expect(weldsCount(22, en: false), '22 spoiny');
      expect(weldsCount(0, en: false), '0 spoin');
      expect(weldsCount(1, en: true), '1 weld');
      expect(weldsCount(3, en: true), '3 welds');
      expect(sharedCount(1, en: false), '1 wspólna');
      expect(sharedCount(3, en: false), '3 wspólne');
      expect(sharedCount(5, en: false), '5 wspólnych');
    });

    test('okno wykresu: min. 7, maks. 31 dni, kończy się z okresem', () {
      final d = chartWindow(
          range: DayRange(dayOnly(today), dayOnly(today)), today: today);
      expect(d.from, DateTime(2026, 10, 8));
      expect(d.to, DateTime(2026, 10, 14));
      final all = chartWindow(
          range: null, today: today, firstWeld: DateTime(2026, 6, 1));
      expect(all.days, 31);
      expect(all.to, DateTime(2026, 10, 14));
      final series = dailySeries([weld('a', date: '2026-10-13')], d);
      expect(series, hasLength(7));
      expect(series.where((x) => x.welds > 0).single.day,
          DateTime(2026, 10, 13));
    });

    ProgressReport report(ProgressPeriod period, {ProgressForecast? f}) {
      final welds = [
        weld('a', date: '2026-10-13', welder: 'JK-12', rootWelder: 'AB-03'),
        weld('b', date: '2026-10-14', welder: 'JK-12').copyWith(od: '114.3'),
        weld('c', date: '2026-10-14', welder: 'AB-03', ndt: {
          NdtMethod.rt: ndtOf(NdtScope.selected, NdtResult.nok),
        }),
      ];
      final filter = ProgressFilter(project: 'Blok 4', period: period);
      final scope = filter.scopeOf(welds);
      return ProgressReport(
        filter: filter,
        range: filter.rangeFor(today),
        summary: summarizeProgress(filter.apply(welds, today)),
        pace: computePace(scope, today: today, week: const WorkWeek()),
        forecast: f,
        generatedAt: DateTime(2026, 10, 14, 16, 5),
      );
    }

    test('raport dzienny: tytuł, liczby, spawacze, brygada, jakość', () {
      final text = buildProgressReportText(report(ProgressPeriod.today),
          en: false);
      expect(text, startsWith('RAPORT DZIENNY — 2026-10-14 (śr)'));
      expect(text, contains('Projekt: Blok 4'));
      expect(text, contains('Wykonano: 2 spoiny · 6 DI'));
      expect(text, contains('Status: OK 0 · NOK 0 · czeka na odbiór 2'));
      expect(text, contains('• JK-12 — 1 spoina · 4 DI'));
      expect(text, contains('Brygada razem: 2 spoiny · 6 DI'));
      expect(text, contains('odsetek napraw 100% (1 z 1 zbadanych RT/UT)'));
      // Dzienny nie wypisuje „dzień po dniu".
      expect(text, isNot(contains('Dzień po dniu')));
      expect(text, endsWith('Fitter Welder Pro · 2026-10-14 16:05'));
    });

    test('raport tygodniowy: dni i prognoza; wersja angielska', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 8,
        total: 40,
        pacePerDay: 4,
        today: today,
        todayLogged: true,
        week: const WorkWeek(),
        due: DateTime(2026, 10, 30),
      );
      final r = report(ProgressPeriod.week, f: f);
      final pl = buildProgressReportText(r, en: false);
      expect(pl, startsWith('RAPORT TYGODNIOWY — 2026-10-12 – 2026-10-14'));
      expect(pl, contains('• 2026-10-13 (wt) — 1 spoina · 2 DI'));
      expect(pl, contains('Wykonano: 3 spoiny · 8 DI'));
      expect(pl, contains('Zakres: 40 DI · wykonano 8 DI (20%) · zostało 32 DI'));
      expect(pl, contains('Koniec przy obecnym tempie: 2026-10-26 (pn) (8 dni rob.)'));
      expect(pl, contains('Termin 2026-10-30: trzeba 2,7 DI/dzień rob.'));
      expect(r.fileName(en: false), 'Raport_postepu_Blok_4_2026-10-14.pdf');

      final en = buildProgressReportText(r, en: true);
      expect(en, startsWith('WEEKLY PROGRESS REPORT'));
      expect(en, contains('Done: 3 welds · 8 DI'));
      expect(en, contains('Crew total: 3 welds · 8 DI'));
      expect(en, contains('2.7 DI/working day needed'));
    });

    test('pusty okres: komunikat zamiast liczb', () {
      const filter = ProgressFilter(project: 'Nic');
      final text = buildProgressReportText(
        ProgressReport(
          filter: filter,
          range: filter.rangeFor(today),
          summary: summarizeProgress(const []),
          pace: null,
          forecast: null,
          generatedAt: today,
        ),
        en: false,
      );
      expect(text, contains('Brak spoin w dzienniku w tym okresie.'));
      expect(text, isNot(contains('Spawacze:')));
    });
  });
}
