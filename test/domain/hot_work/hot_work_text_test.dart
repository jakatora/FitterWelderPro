// Protokół tekstowy prac pożarowo niebezpiecznych: dane zezwolenia, stan,
// pomiary z oceną, punkty [x] / [n/d] / [ ], zastrzeżenie — PL i EN.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/hot_work/hot_work_checklist.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_text.dart';

HotWorkPermit _permit({List<HotWorkMeasurement> measurements = const []}) =>
    HotWorkPermit(
      id: 'p',
      permitNo: 'ZPP/7/2026',
      location: 'Instalacja HDS, kołnierz F-12',
      description: 'Spawanie króćca DN50',
      workTypes: const {HotWorkType.welding, HotWorkType.cutting},
      date: '2026-10-17',
      validFrom: '07:00',
      validTo: '15:00',
      contractor: 'Jan Kowalski',
      securedBy: 'Adam Nowak',
      fireWatch: 'Piotr Wiśniewski',
      issuer: 'Ewa Zając',
      dgwLimitPct: 10,
      measurements: measurements,
      checked: const {'comb-remove'},
      na: const {'cyl-flashback'},
      notes: 'Koc pod rurociągiem.',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  test('tekst PL: dane, stan, pomiary, punkty i zastrzeżenie', () {
    final text = hotWorkProtocolText(
      _permit(measurements: const [
        HotWorkMeasurement(time: '06:50', dgwPct: 0, note: 'studzienka K-3'),
        HotWorkMeasurement(time: '09:15', dgwPct: 12.5),
      ]),
      en: false,
      now: DateTime(2026, 10, 17, 9, 20),
    );
    expect(text,
        startsWith('PRACE POŻAROWO NIEBEZPIECZNE — PROTOKÓŁ PRZYGOTOWANIA'));
    expect(text, contains('(lista pomocnicza — nie zastępuje zezwolenia)'));
    expect(text, contains('Nr zezwolenia: ZPP/7/2026'));
    expect(text, contains('Miejsce pracy: Instalacja HDS, kołnierz F-12'));
    expect(text, contains('Rodzaj pracy: Spawanie, Cięcie'));
    expect(text, contains('Ważne (godziny): 07:00–15:00'));
    expect(text, contains('Dozorujący: Piotr Wiśniewski'));
    expect(text, contains('Dopuszczalne stężenie: ≤ 10 % DGW'));
    expect(text, contains('Dozór po zakończeniu: — (wg zezwolenia)'));
    expect(text, contains('- 06:50 — 0 % DGW — studzienka K-3 (OK)'));
    expect(text, contains('- 09:15 — 12,5 % DGW (POWYŻEJ LIMITU)'));
    expect(text, contains('STAN: STOP — ostatni pomiar 12,5 % DGW przekracza'));
    final remove = hotWorkCheckById('comb-remove')!;
    final flash = hotWorkCheckById('cyl-flashback')!;
    final ext = hotWorkCheckById('ext-ready')!;
    expect(text, contains('[x] ${remove.pl}'));
    expect(text, contains('[n/d] ${flash.pl}'));
    expect(text, contains('[ ] ${ext.pl}'));
    expect(text, contains('PRZED ROZPOCZĘCIEM (2/'));
    expect(text, contains('Uwagi: Koc pod rurociągiem.'));
    expect(text, contains('rozporządzenie MSWiA z 7 czerwca 2010 r.'));
    expect(text, contains('§ 36'));
    expect(text, endsWith('Fitter Welder Pro'));
  });

  test('brak pomiaru — tekst mówi to wprost', () {
    final text = hotWorkProtocolText(_permit(),
        en: false, now: DateTime(2026, 10, 17, 9, 20));
    expect(text, contains('— brak pomiaru —'));
    expect(text, contains('STAN: Brak pomiaru atmosfery'));
  });

  test('tekst EN', () {
    final text = hotWorkProtocolText(
      _permit(measurements: const [
        HotWorkMeasurement(time: '06:50', dgwPct: 1.5),
      ]),
      en: true,
      now: DateTime(2026, 10, 17, 7),
    );
    expect(text, startsWith('HOT WORK — WORK AREA PREPARATION RECORD'));
    expect(text, contains('Type of work: Welding, Cutting'));
    expect(text, contains('Permitted gas level: ≤ 10 % LEL'));
    expect(text, contains('- 06:50 — 1.5 % LEL (OK)'));
    expect(text, contains('[n/a] ${hotWorkCheckById('cyl-flashback')!.en}'));
    expect(text, contains('BEFORE WORK STARTS (2/'));
    expect(text, contains('Checklist aid only — not a permit.'));
  });

  test('krótkie etykiety stanu', () {
    HotWorkAssessment a(HotWorkPermit p) =>
        p.assess(now: DateTime(2026, 10, 17, 7, 5));
    expect(hotWorkReadinessShort(a(_permit()), en: false), 'Brak pomiaru');
    final ready = _permit(measurements: const [
      HotWorkMeasurement(time: '07:00', dgwPct: 0),
    ]).copyWith(checked: {
      for (final c in hotWorkChecksIn(HotWorkPhase.before)) c.id,
    });
    expect(hotWorkReadinessShort(a(ready), en: false), 'Gotowe');
    expect(hotWorkReadinessText(a(ready), en: false),
        startsWith('Stanowisko przygotowane'));
    final closed = ready.copyWith(checked: {
      for (final c in kHotWorkChecks) c.id,
    });
    expect(hotWorkReadinessShort(a(closed), en: true), 'Closed');
  });

  test('pomiar z innego dnia z datą; bez limitu ponad 10 % — POWYŻEJ', () {
    final p = _permit(measurements: [
      HotWorkMeasurement(
          time: '23:50',
          at: DateTime(2026, 10, 16, 23, 50).millisecondsSinceEpoch,
          dgwPct: 0),
    ]);
    final text =
        hotWorkProtocolText(p, en: false, now: DateTime(2026, 10, 17, 7));
    expect(text, contains('- 2026-10-16 23:50 — 0 % DGW (OK)'));
    expect(text, contains('STAN: Pomiar nieaktualny (z 2026-10-16 23:50'));
    expect(text, contains('Ważność pomiaru: 30 min — przyjęta w aplikacji'));
    expect(
        hotWorkMeasurementLine(
            const HotWorkMeasurement(time: '07:00', dgwPct: 50), null,
            en: false),
        '07:00 — 50 % DGW (POWYŻEJ LIMITU Z PRZEPISU)');
    expect(
        hotWorkMeasurementLine(
            const HotWorkMeasurement(time: '07:00', dgwPct: 5), null,
            en: false),
        '07:00 — 5 % DGW');
  });
}
