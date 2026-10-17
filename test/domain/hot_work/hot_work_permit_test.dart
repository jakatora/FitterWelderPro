// Protokół prac pożarowo niebezpiecznych: ocena gotowości (brak pomiaru
// nigdy nie daje zielonego stanu), „nie dotyczy”, JSON tam i z powrotem,
// duplikat „jak wczoraj”.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/hot_work/hot_work_checklist.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_sources.dart';

final _now = DateTime(2026, 10, 17, 7, 30);

HotWorkPermit _blank() => HotWorkPermit.blank(id: 'p1', now: _now);

HotWorkPermit _allBefore(HotWorkPermit p) => p.copyWith(checked: {
      ...p.checked,
      for (final c in hotWorkChecksIn(HotWorkPhase.before)) c.id,
    });

HotWorkPermit _full() => HotWorkPermit(
      id: 'abc',
      permitNo: 'ZPP/112/2026',
      location: 'Rafineria — instalacja HDS, kołnierz F-12',
      description: 'Spawanie króćca DN50; szlifowanie',
      workTypes: const {HotWorkType.welding, HotWorkType.grinding},
      date: '2026-10-16',
      validFrom: '07:00',
      validTo: '15:00',
      contractor: 'Jan Kowalski (Monter-Bud)',
      securedBy: 'Adam Nowak',
      fireWatch: 'Piotr Wiśniewski',
      issuer: 'Ewa Zając, kier. instalacji',
      dgwLimitPct: 5,
      measurements: const [
        HotWorkMeasurement(time: '06:50', dgwPct: 0, note: 'studzienka K-3'),
        HotWorkMeasurement(time: '10:00', dgwPct: 1.5, note: 'O₂ 20,9 %'),
      ],
      fireWatchAfterMin: 60,
      checked: const {'perm-written', 'comb-remove', 'dur-watch'},
      na: const {'cyl-flashback'},
      notes: 'Dodatkowy koc pod rurociągiem.',
      createdAt: 1000,
      updatedAt: 2000,
    );

void main() {
  group('ocena gotowości', () {
    test('nowy protokół: domyślny próg 10 % DGW, pusty, brak pomiaru', () {
      final p = _blank();
      expect(p.dgwLimitPct, kHotWorkDefaultDgwLimitPct);
      expect(p.date, '2026-10-17');
      expect(p.isBlank, isTrue);
      expect(p.assess().readiness, HotWorkReadiness.noMeasurement);
      expect(p.assess().readyToStart, isFalse);
    });

    test('wszystko odhaczone, ale brak pomiaru — NIE zielony stan', () {
      var p = _allBefore(_blank());
      p = p.copyWith(checked: {
        ...p.checked,
        for (final c in kHotWorkChecks) c.id,
      });
      final a = p.assess();
      expect(a.openBefore, isEmpty);
      expect(a.openDuring, isEmpty);
      expect(a.openAfter, isEmpty);
      expect(a.measurementMissing, isTrue);
      expect(a.readiness, HotWorkReadiness.noMeasurement);
      expect(a.readyToStart, isFalse);
      expect(a.closed, isFalse);
    });

    test('pomiar w normie + wszystkie punkty „przed” — gotowe', () {
      final p = _allBefore(_blank()).copyWith(measurements: const [
        HotWorkMeasurement(time: '07:20', dgwPct: 0),
      ]);
      final a = p.assess();
      expect(a.readiness, HotWorkReadiness.ready);
      expect(a.readyToStart, isTrue);
      // „Zamknięte” dopiero po punktach „w trakcie” i „po zakończeniu”.
      expect(a.closed, isFalse);
      final closed = p.copyWith(checked: {
        for (final c in kHotWorkChecks) c.id,
      });
      expect(closed.assess().closed, isTrue);
    });

    test('pomiar bez punktów — niekompletne', () {
      final p = _blank().copyWith(measurements: const [
        HotWorkMeasurement(time: '07:20', dgwPct: 0),
      ]);
      expect(p.assess().readiness, HotWorkReadiness.incomplete);
      expect(p.assess().openBefore.length,
          hotWorkChecksIn(HotWorkPhase.before).length);
    });

    test('pomiar powyżej progu — STOP, nawet przy odhaczonej liście', () {
      final p = _allBefore(_blank()).copyWith(measurements: const [
        HotWorkMeasurement(time: '07:20', dgwPct: 12),
      ]);
      expect(p.assess().readiness, HotWorkReadiness.overLimit);
      expect(p.assess().readyToStart, isFalse);
    });

    test('decyduje ostatni pomiar (po przewietrzeniu)', () {
      final p = _allBefore(_blank()).copyWith(measurements: const [
        HotWorkMeasurement(time: '07:00', dgwPct: 15),
        HotWorkMeasurement(time: '07:25', dgwPct: 0),
      ]);
      expect(p.assess().readiness, HotWorkReadiness.ready);
      final worse = p.copyWith(measurements: [
        ...p.measurements,
        const HotWorkMeasurement(time: '09:00', dgwPct: 11),
      ]);
      expect(worse.assess().readiness, HotWorkReadiness.overLimit);
    });

    test('próg „nieprzekraczający” (§ 36 ust. 2): równy przechodzi, 0 % '
        'tylko przy 0', () {
      expect(hotWorkMeasurementOk(10, 10), isTrue);
      expect(hotWorkMeasurementOk(10.01, 10), isFalse);
      expect(hotWorkMeasurementOk(0, 0), isTrue);
      expect(hotWorkMeasurementOk(0.5, 0), isFalse);
      expect(hotWorkMeasurementOk(4, 5), isTrue);
    });

    test('bez progu z zezwolenia — wyniku nie da się ocenić', () {
      final p = _allBefore(_blank()).copyWith(
        dgwLimitPct: null,
        measurements: const [HotWorkMeasurement(time: '07:20', dgwPct: 0)],
      );
      expect(p.assess().readiness, HotWorkReadiness.noLimit);
      expect(p.assess().readyToStart, isFalse);
    });
  });

  group('nie dotyczy', () {
    test('tylko przy punktach, które na to pozwalają', () {
      final p = _blank();
      expect(p.toggleNa('comb-remove').na, isEmpty);
      expect(p.toggleNa('nie-ma-takiego').na, isEmpty);
      final na = p.toggleNa('cyl-flashback');
      expect(na.na, {'cyl-flashback'});
      expect(na.isSettled(hotWorkCheckById('cyl-flashback')!), isTrue);
      // Odhaczenie zdejmuje „n/d”, „n/d” zdejmuje odhaczenie.
      final checked = na.toggleChecked('cyl-flashback');
      expect(checked.na, isEmpty);
      expect(checked.checked, {'cyl-flashback'});
      expect(checked.toggleNa('cyl-flashback').checked, isEmpty);
      // Drugi raz — przełącza z powrotem.
      expect(checked.toggleChecked('cyl-flashback').checked, isEmpty);
    });

    test('„n/d” przy punkcie podstawowym (np. z zapisu) nie zwalnia go', () {
      final p = _blank().copyWith(na: {'ext-ready'});
      expect(p.isNa(hotWorkCheckById('ext-ready')!), isFalse);
      expect(p.assess().openBefore.map((c) => c.id), contains('ext-ready'));
    });

    test('punkty „n/d” zaliczają się do gotowości', () {
      final naAll = {
        for (final c in hotWorkChecksIn(HotWorkPhase.before))
          if (c.naAllowed) c.id,
      };
      final p = _blank().copyWith(
        checked: {
          for (final c in hotWorkChecksIn(HotWorkPhase.before))
            if (!c.naAllowed) c.id,
        },
        na: naAll,
        measurements: const [HotWorkMeasurement(time: '07:20', dgwPct: 0)],
      );
      expect(p.assess().readyToStart, isTrue);
    });
  });

  group('JSON', () {
    test('tam i z powrotem — wszystkie pola', () {
      final p = _full();
      final back = HotWorkPermit.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.id, p.id);
      expect(back.permitNo, p.permitNo);
      expect(back.location, p.location);
      expect(back.description, p.description);
      expect(back.workTypes, p.workTypes);
      expect(back.date, p.date);
      expect(back.validFrom, p.validFrom);
      expect(back.validTo, p.validTo);
      expect(back.contractor, p.contractor);
      expect(back.securedBy, p.securedBy);
      expect(back.fireWatch, p.fireWatch);
      expect(back.issuer, p.issuer);
      expect(back.dgwLimitPct, 5);
      expect(back.measurements, p.measurements);
      expect(back.fireWatchAfterMin, 60);
      expect(back.checked, p.checked);
      expect(back.na, p.na);
      expect(back.notes, p.notes);
      expect(back.createdAt, 1000);
      expect(back.updatedAt, 2000);
      expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
    });

    test('lista protokołów tam i z powrotem; uszkodzone wpisy pominięte', () {
      final raw = jsonDecode(jsonEncode([
        ...hotWorkPermitsToJson([_full(), _blank()]),
        'śmieć',
        {'id': '', 'date': '2026-10-17'},
        {'id': 'x'},
      ]));
      final list = hotWorkPermitsFromJson(raw);
      expect(list.map((p) => p.id), ['abc', 'p1']);
      expect(hotWorkPermitsFromJson('nie lista'), isEmpty);
    });

    test('nieznane punkty, „n/d” przy punkcie podstawowym i złe pomiary '
        'są odrzucane', () {
      final json = _full().toJson()
        ..['checked'] = ['comb-remove', 'stary-punkt', 7]
        ..['na'] = ['ext-ready', 'cyl-flashback', 'stary-punkt']
        ..['measurements'] = [
          {'time': '07:00', 'dgw': 2, 'note': ''},
          {'time': '07:10', 'dgw': -1},
          {'time': '07:20'},
          'x',
        ]
        ..['dgwLimit'] = 'dziesięć'
        ..['workTypes'] = ['welding', 'teleportacja'];
      final p = HotWorkPermit.fromJson(json)!;
      expect(p.checked, {'comb-remove'});
      expect(p.na, {'cyl-flashback'});
      expect(p.measurements,
          const [HotWorkMeasurement(time: '07:00', dgwPct: 2)]);
      expect(p.dgwLimitPct, isNull);
      expect(p.workTypes, {HotWorkType.welding});
    });
  });

  group('jak wczoraj', () {
    test('kopia: dane organizacyjne zostają, zaznaczenia i pomiary nie', () {
      final src = _full();
      final copy = src.duplicateFor(newId: 'nowy', now: _now);
      expect(copy.id, 'nowy');
      expect(copy.date, '2026-10-17');
      expect(copy.location, src.location);
      expect(copy.description, src.description);
      expect(copy.workTypes, src.workTypes);
      expect(copy.validFrom, '07:00');
      expect(copy.validTo, '15:00');
      expect(copy.contractor, src.contractor);
      expect(copy.securedBy, src.securedBy);
      expect(copy.fireWatch, src.fireWatch);
      expect(copy.issuer, src.issuer);
      expect(copy.dgwLimitPct, 5);
      expect(copy.fireWatchAfterMin, 60);
      // Stanowisko sprawdza się na nowo; zakład wystawia nowe zezwolenie.
      expect(copy.checked, isEmpty);
      expect(copy.na, isEmpty);
      expect(copy.measurements, isEmpty);
      expect(copy.permitNo, isEmpty);
      expect(copy.notes, isEmpty);
      expect(copy.assess().readiness, HotWorkReadiness.noMeasurement);
      expect(copy.isBlank, isFalse);
    });
  });

  test('formatowanie liczb: przecinek w PL, do 2 miejsc', () {
    expect(formatHotWorkNumber(0, en: false), '0');
    expect(formatHotWorkNumber(1.5, en: false), '1,5');
    expect(formatHotWorkNumber(1.5, en: true), '1.5');
    expect(formatHotWorkNumber(9.96, en: false), '9,96');
    expect(formatHotWorkNumber(10, en: false), '10');
    expect(hotWorkTime(DateTime(2026, 1, 2, 7, 5)), '07:05');
  });

  group('pomiary w czasie i próg (przegląd 2026-10-17)', () {
    final t1030 = DateTime(2026, 10, 17, 10, 30).millisecondsSinceEpoch;
    final t0900 = DateTime(2026, 10, 17, 9, 0).millisecondsSinceEpoch;

    test('zaległy pomiar 0 % z 09:00 dopisany po 15 % z 10:30 — nadal STOP',
        () {
      final p = _allBefore(_blank()).copyWith(measurements: [
        HotWorkMeasurement(time: '10:30', at: t1030, dgwPct: 15),
        HotWorkMeasurement(time: '09:00', at: t0900, dgwPct: 0),
      ]);
      final a = p.assess();
      expect(a.lastMeasurement!.time, '10:30');
      expect(a.readiness, HotWorkReadiness.overLimit);
      expect(p.measurementsChrono.map((m) => m.time), ['09:00', '10:30']);
    });

    test('ta sama chwila — decyduje później dopisany', () {
      final p = _allBefore(_blank()).copyWith(measurements: [
        HotWorkMeasurement(time: '10:30', at: t1030, dgwPct: 15),
        HotWorkMeasurement(time: '10:30', at: t1030, dgwPct: 0),
      ]);
      expect(p.assess().readiness, HotWorkReadiness.ready);
    });

    test('stary zapis bez chwili pomiaru — kolejność wpisów', () {
      final p = _allBefore(_blank()).copyWith(measurements: const [
        HotWorkMeasurement(time: '10:30', dgwPct: 0),
        HotWorkMeasurement(time: '09:00', dgwPct: 15),
      ]);
      expect(p.assess().readiness, HotWorkReadiness.overLimit);
    });

    test('godzina pomiaru: dziś, a „z przyszłości” to wczoraj (zmiana nocna)',
        () {
      final now = DateTime(2026, 10, 17, 0, 12);
      expect(hotWorkMeasurementAt('00:10', now), DateTime(2026, 10, 17, 0, 10));
      expect(hotWorkMeasurementAt('23:50', now), DateTime(2026, 10, 16, 23, 50));
      // Zapas 5 min na różnicę zegarów.
      expect(hotWorkMeasurementAt('00:16', now), DateTime(2026, 10, 17, 0, 16));
      expect(hotWorkMeasurementAt('25:00', now), now);
      expect(hotWorkMeasurementAt('', now), now);
    });

    test('godzina tuż po północy wpisana przed północą: jutro, nie doba wstecz',
        () {
      final now = DateTime(2026, 10, 17, 23, 58);
      // 00:03 mieści się w zapasie 5 min → jutro 00:03.
      expect(hotWorkMeasurementAt('00:03', now), DateTime(2026, 10, 18, 0, 3));
      // 00:04 już poza zapasem → dziś 00:04 (prawie doba wcześniej).
      expect(hotWorkMeasurementAt('00:04', now), DateTime(2026, 10, 17, 0, 4));
      expect(hotWorkMeasurementAt('23:50', now), DateTime(2026, 10, 17, 23, 50));
    });

    test('chwila pomiaru przechodzi przez JSON', () {
      final p = _blank().copyWith(measurements: [
        HotWorkMeasurement(time: '10:30', at: t1030, dgwPct: 1.5),
      ]);
      final back = HotWorkPermit.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.measurements.single.at, t1030);
      expect(back.measurements.single, p.measurements.single);
    });

    test('próg powyżej 10 % DGW nie daje zielonego stanu', () {
      expect(hotWorkLimitValid(10), isTrue);
      expect(hotWorkLimitValid(0), isTrue);
      expect(hotWorkLimitValid(10.01), isFalse);
      expect(hotWorkLimitValid(-1), isFalse);
      final p = _allBefore(_blank()).copyWith(
        dgwLimitPct: 100.0,
        measurements: [HotWorkMeasurement(time: '10:30', at: t1030, dgwPct: 40)],
      );
      expect(p.assess().readiness, HotWorkReadiness.noLimit);
      final json = p.toJson()..['dgwLimit'] = 50;
      expect(HotWorkPermit.fromJson(json)!.dgwLimitPct, isNull);
    });
  });
}
