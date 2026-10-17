// Protokół wejścia: ocena (brak pomiaru gazu ≠ OK, najpóźniejszy odczyt
// decyduje, remis w minucie → gorszy i zgłoszony), wiek pomiaru i data
// protokołu (nieaktualny = brak), STOP wpisany później blokuje zieleń,
// brak progu → twarda granica, wymagane gazy, „nie dotyczy”, „jak wczoraj”
// bez pomiarów i odhaczeń, JSON i uszkodzony JSON (odrzucone pomiary —
// także z przyszłości — są liczone, nie znikają po cichu).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/confined_space/confined_space_checklist.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_sources.dart';

final _now = DateTime(2026, 10, 17, 7, 30);

DateTime _t(int h, int m, [int s = 0]) => DateTime(2026, 10, 17, h, m, s);

int _at(int h, int m, [int s = 0]) => _t(h, m, s).millisecondsSinceEpoch;

CsMeasurement _m(int h, int min,
        {double? o2 = 20.9,
        double? lel = 0,
        CsQty? co = const CsQty(0, CsUnit.ppm),
        CsQty? h2s = const CsQty(0, CsUnit.ppm),
        int s = 0,
        int? entered,
        String? id,
        String place = ''}) =>
    CsMeasurement(
      id: id ?? 'm$h-$min-$s',
      time: '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}',
      at: _at(h, min, s),
      enteredAt: entered,
      values: {
        if (o2 != null) CsGas.o2: CsQty(o2, CsUnit.pctVol),
        if (lel != null) CsGas.lel: CsQty(lel, CsUnit.pctLel),
        if (co != null) CsGas.co: co,
        if (h2s != null) CsGas.h2s: h2s,
      },
      place: place,
    );

ConfinedSpaceRecord _blank() =>
    ConfinedSpaceRecord.blank(id: 'r1', now: _now);

ConfinedSpaceRecord _allBefore(ConfinedSpaceRecord r) => r.copyWith(checked: {
      ...r.checked,
      for (final c in confinedSpaceChecksIn(ConfinedSpacePhase.before)) c.id,
    });

ConfinedSpaceRecord _full() => ConfinedSpaceRecord(
      id: 'abc',
      permitNo: 'PZ/12/2026',
      location: 'Zbiornik T-101, właz M1',
      description: 'Spawanie króćca DN80 od środka',
      processes: const {CsProcess.tig, CsProcess.purge},
      date: '2026-10-16',
      validFrom: '07:00',
      validTo: '15:00',
      entrants: 'Jan Kowalski',
      attendant: 'Adam Nowak',
      supervisor: 'Ewa Zając',
      issuer: 'Piotr Wiśniewski',
      rescue: 'Straż zakładowa, trójnóg T-2',
      limits: CsLimits.defaults
          .withLimit(CsBound.lelMax, const CsQty(5, CsUnit.pctLel)),
      maxAgeMin: 15,
      requiredGases: const {CsGas.o2, CsGas.lel, CsGas.co},
      measurements: [_m(6, 50, place: 'dno'), _m(9, 15)],
      checked: const {'perm-written', 'iso-blind', 'dur-attendant'},
      na: const {'clean-sewer'},
      notes: 'Nawiew z wentylatora W-3.',
      createdAt: 1000,
      updatedAt: 2000,
    );

void main() {
  group('ocena', () {
    test('nowy protokół: progi domyślne, cztery gazy wymagane, brak pomiaru',
        () {
      final r = _blank();
      expect(r.limits.isDefault, isTrue);
      expect(r.requiredGases, kCsDefaultRequired);
      expect(r.effectiveMaxAgeMin, kCsMeasurementMaxAgeMin);
      expect(r.isBlank, isTrue);
      expect(r.date, '2026-10-17');
      expect(r.assess(now: _now).readiness, CsReadiness.noMeasurement);
    });

    test('wszystko odhaczone, brak pomiaru — NIE zielony', () {
      final r = _blank().copyWith(checked: {
        for (final c in kConfinedSpaceChecks) c.id,
      });
      final a = r.assess(now: _now);
      expect(a.openBefore, isEmpty);
      expect(a.readiness, CsReadiness.noMeasurement);
      expect(a.readyToEnter, isFalse);
      expect(a.closed, isFalse);
    });

    test('brak odczytu jednego wymaganego gazu ≠ OK', () {
      // Detektor bez H₂S: tlen, DGW i CO w normie — H₂S nadal wymagany.
      final r = _allBefore(_blank()).addMeasurement(_m(7, 20, h2s: null));
      final a = r.assess(now: _now);
      expect(a.readiness, CsReadiness.noMeasurement);
      expect(a.missing.map((v) => v.gas), [CsGas.h2s]);
      // Pozwolenie nie wymaga H₂S — dopiero wtedy zielony.
      final notRequired = r.withRequired(CsGas.h2s, false);
      expect(notRequired.assess(now: _now).readiness, CsReadiness.ready);
    });

    test('tlenu i gazów palnych nie da się odznaczyć jako wymaganych', () {
      final r = _blank()
          .withRequired(CsGas.o2, false)
          .withRequired(CsGas.lel, false);
      expect(r.requiredGases, containsAll([CsGas.o2, CsGas.lel]));
      final fromJson = ConfinedSpaceRecord.fromJson(
          {...r.toJson(), 'required': <String>[]})!;
      expect(fromJson.requiredGases, {CsGas.o2, CsGas.lel});
    });

    test('komplet w normie + punkty „przed” — gotowe; zamknięte po reszcie',
        () {
      final r = _allBefore(_blank()).addMeasurement(_m(7, 20));
      expect(r.assess(now: _now).readiness, CsReadiness.ready);
      expect(r.assess(now: _now).closed, isFalse);
      final closed =
          r.copyWith(checked: {for (final c in kConfinedSpaceChecks) c.id});
      expect(closed.assess(now: _now).closed, isTrue);
    });

    test('tlen za mało i za dużo — STOP nawet przy odhaczonej liście', () {
      final low = _allBefore(_blank()).addMeasurement(_m(7, 20, o2: 18.5));
      expect(low.assess(now: _now).readiness, CsReadiness.stop);
      expect(low.assess(now: _now).stops.single.state, CsReadingState.low);
      final high = _allBefore(_blank()).addMeasurement(_m(7, 20, o2: 24));
      expect(high.assess(now: _now).readiness, CsReadiness.stop);
      expect(high.assess(now: _now).stops.single.state, CsReadingState.high);
    });

    test('gaz niewymagany, ale zmierzony ponad próg — też STOP', () {
      final r = _allBefore(_blank())
          .withRequired(CsGas.h2s, false)
          .addMeasurement(_m(7, 20, h2s: const CsQty(10, CsUnit.ppm)));
      expect(r.assess(now: _now).readiness, CsReadiness.stop);
      expect(r.assess(now: _now).stops.single.gas, CsGas.h2s);
    });

    test('decyduje NAJPÓŹNIEJSZY odczyt każdego gazu, nie ostatnio dopisany',
        () {
      final now = _t(11, 5);
      // 10:30: tlen 18 % (STOP); dopisany potem zaległy pomiar z 09:00
      // z tlenem 20,9 % nie zdejmuje STOP-u.
      var r = _allBefore(_blank()).addMeasurement(_m(10, 30, o2: 18));
      r = r.addMeasurement(_m(9, 0));
      expect(r.assess(now: now).readiness, CsReadiness.stop);
      expect(r.measurementsChrono.map((m) => m.time), ['09:00', '10:30']);
      // Nowy pomiar 10:45 po przewietrzeniu — zielony.
      r = r.addMeasurement(_m(10, 45));
      expect(r.assess(now: now).readiness, CsReadiness.ready);
      // Najpóźniejszy odczyt liczy się osobno dla każdego gazu: o 11:00
      // zmierzono tylko tlen, CO decyduje odczyt z 10:45.
      r = r.addMeasurement(_m(11, 0, lel: null, co: null, h2s: null));
      expect(r.assess(now: now).verdict(CsGas.co).decisive!.time, '10:45');
      expect(r.assess(now: now).verdict(CsGas.o2).decisive!.time, '11:00');
    });

    test('remis w tej samej minucie: decyduje gorszy i jest zgłoszony', () {
      final now = _t(10, 35);
      final r = _allBefore(_blank())
          .addMeasurement(_m(10, 30, o2: 20.9))
          .addMeasurement(_m(10, 30, o2: 18, s: 40));
      final v = r.assess(now: now).verdict(CsGas.o2);
      expect(v.tie, isTrue);
      expect(v.state, CsReadingState.low);
      expect(r.assess(now: now).readiness, CsReadiness.stop);
      expect(r.assess(now: now).ties.map((t) => t.gas), [CsGas.o2]);
      // Kolejność wpisów nie zmienia wyniku.
      final reversed = _allBefore(_blank())
          .addMeasurement(_m(10, 30, o2: 18, s: 40))
          .addMeasurement(_m(10, 30, o2: 20.9));
      expect(reversed.assess(now: now).readiness, CsReadiness.stop);
      // Ten sam odczyt dwa razy to nie remis.
      final same = _allBefore(_blank())
          .addMeasurement(_m(10, 30))
          .addMeasurement(_m(10, 30, s: 20));
      expect(same.assess(now: now).ties, isEmpty);
      expect(same.assess(now: now).readiness, CsReadiness.ready);
    });

    test('remis przy równej randze: pokazany odczyt dalej od progu', () {
      final now = _t(10, 35);
      // Oba STOP: decyduje (i jest pokazany) najniższy tlen.
      final low = _allBefore(_blank())
          .addMeasurement(_m(10, 30, o2: 18))
          .addMeasurement(_m(10, 30, o2: 15, s: 30));
      expect(low.assess(now: now).verdict(CsGas.o2).value!.value, 15);
      // Oba wzbogacenie: najwyższy tlen.
      final high = _allBefore(_blank())
          .addMeasurement(_m(10, 30, o2: 25, s: 30))
          .addMeasurement(_m(10, 30, o2: 24));
      expect(high.assess(now: now).verdict(CsGas.o2).value!.value, 25);
      // Oba STOP: najwyższe CO w ppm (23,4 mg/m³ ≈ 20,09 ppm < 30 ppm).
      final co = _allBefore(_blank())
          .addMeasurement(_m(10, 30, co: const CsQty(30, CsUnit.ppm)))
          .addMeasurement(
              _m(10, 30, s: 30, co: const CsQty(23.4, CsUnit.mgM3)));
      expect(co.assess(now: now).verdict(CsGas.co).value,
          const CsQty(30, CsUnit.ppm));
      // Oba OK: najwyższe DGW (bliżej progu).
      final lel = _allBefore(_blank())
          .addMeasurement(_m(10, 30, lel: 2))
          .addMeasurement(_m(10, 30, s: 30, lel: 7));
      expect(lel.assess(now: now).verdict(CsGas.lel).value!.value, 7);
    });

    test('brak progu: w granicy twardej „brak progu”, ponad — STOP', () {
      final none = _allBefore(_blank()).copyWith(
          limits: CsLimits.defaults
              .withLimit(CsBound.coMax, null)
              .withLimit(CsBound.o2Min, null));
      final ok = none.addMeasurement(_m(7, 20));
      expect(ok.assess(now: _now).readiness, CsReadiness.noLimit);
      expect(ok.assess(now: _now).noLimits.map((v) => v.gas),
          [CsGas.o2, CsGas.co]);
      // CO 500 ppm przy pustym progu — STOP (twarda granica NDS 20 ppm).
      final co = none.addMeasurement(
          _m(7, 20, co: const CsQty(500, CsUnit.ppm)));
      expect(co.assess(now: _now).readiness, CsReadiness.stop);
      // Tlen 5 % przy pustym dolnym progu — STOP (twarda granica 19,5 %).
      final o2 = none.addMeasurement(_m(7, 20, o2: 5));
      expect(o2.assess(now: _now).readiness, CsReadiness.stop);
      expect(o2.assess(now: _now).stops.single.state, CsReadingState.low);
    });
  });

  group('wiek pomiaru i data protokołu', () {
    test('pomiar starszy niż ważność = brak pomiaru (domyślnie 30 min)', () {
      final r = _allBefore(_blank()).addMeasurement(_m(7, 0));
      expect(r.assess(now: _t(7, 30)).readiness, CsReadiness.ready);
      final late = r.assess(now: _t(7, 31));
      expect(late.readiness, CsReadiness.noMeasurement);
      expect(late.stale.map((v) => v.gas), CsGas.values);
      expect(late.readyToEnter, isFalse);
      // Krótsza ważność z pozwolenia.
      final strict = r.copyWith(maxAgeMin: 10);
      expect(strict.assess(now: _t(7, 10)).readiness, CsReadiness.ready);
      expect(strict.assess(now: _t(7, 11)).readiness,
          CsReadiness.noMeasurement);
    });

    test('gaz A świeży, gaz B sprzed godzin — nie zielony', () {
      final r = _allBefore(_blank())
          .addMeasurement(_m(4, 0))
          .addMeasurement(_m(7, 25, co: null, h2s: null));
      final a = r.assess(now: _now);
      expect(a.readiness, CsReadiness.noMeasurement);
      expect(a.stale.map((v) => v.gas), [CsGas.co, CsGas.h2s]);
    });

    test('protokół z innej daty nigdy nie jest zielony', () {
      final r = _allBefore(_blank()).addMeasurement(_m(7, 20));
      expect(r.assess(now: _now).readiness, CsReadiness.ready);
      // Dzień później (ten sam zegar, następna data).
      final tomorrow = DateTime(2026, 10, 18, 7, 25);
      expect(r.assess(now: tomorrow).readiness, CsReadiness.otherDay);
      // Nawet ze świeżym pomiarem, gdy data protokołu jest inna.
      final fresh = r.addMeasurement(CsMeasurement(
          id: 'x',
          time: '07:24',
          at: tomorrow.millisecondsSinceEpoch,
          values: const {
            CsGas.o2: CsQty(20.9, CsUnit.pctVol),
            CsGas.lel: CsQty(0, CsUnit.pctLel),
            CsGas.co: CsQty(0, CsUnit.ppm),
            CsGas.h2s: CsQty(0, CsUnit.ppm),
          }));
      expect(fresh.assess(now: tomorrow).readiness, CsReadiness.otherDay);
      expect(fresh.assess(now: tomorrow).readyToEnter, isFalse);
      // STOP z innego dnia nadal STOP.
      final stop = r.addMeasurement(_m(7, 25, o2: 17));
      expect(stop.assess(now: tomorrow).readiness, CsReadiness.stop);
    });

    test('ważność tylko w dół: 1–30 min, inna wartość = przyjęta 30', () {
      expect(csMaxAgeValid(30), isTrue);
      expect(csMaxAgeValid(1), isTrue);
      expect(csMaxAgeValid(31), isFalse);
      expect(csMaxAgeValid(0), isFalse);
      expect(_blank().copyWith(maxAgeMin: 45).effectiveMaxAgeMin, 30);
      final json = _full().toJson()..['maxAgeMin'] = 120;
      expect(ConfinedSpaceRecord.fromJson(json)!.effectiveMaxAgeMin, 30);
    });
  });

  group('wpis późniejszy niż decydujący', () {
    test('STOP wpisany później niż odczyt z późniejszą godziną blokuje zieleń',
        () {
      // O 14:00 wpis z godziną 14:05 (OK); o 14:02 prawdziwy odczyt 17 %.
      final r = _allBefore(_blank())
          .addMeasurement(_m(14, 5, entered: _at(14, 0)))
          .addMeasurement(_m(14, 2, o2: 17, entered: _at(14, 2)));
      final a = r.assess(now: _t(14, 3));
      expect(a.readiness, CsReadiness.stop);
      expect(a.verdict(CsGas.o2).enteredLater, isTrue);
      expect(a.verdict(CsGas.o2).value!.value, 17);
      // Nowy odczyt wpisany PO alarmie (świeży, w normie) zdejmuje blokadę.
      final after = r.addMeasurement(_m(14, 10, entered: _at(14, 10)));
      expect(after.assess(now: _t(14, 11)).readiness, CsReadiness.ready);
    });
  });

  group('chwila wpisu z przyszłości', () {
    test('zegar +1 h przy dobrym pomiarze nie omija blokady STOP wpisanego '
        'później', () {
      final now = _t(14, 6);
      // Zegar telefonu +1 h: dobry pomiar z ręczną godziną 13:50 wpisany
      // „o 15:00”. Zegar wraca; o 14:05 wpisany zaległy alarm O₂ 17 %
      // z 13:45 — jego wpis jest wcześniejszy niż „15:00”.
      final r = _allBefore(_blank())
          .addMeasurement(_m(13, 50, id: 'ok', entered: _at(15, 0)))
          .addMeasurement(_m(13, 45, o2: 17, id: 'alarm', entered: _at(14, 5)));
      final a = r.assess(now: now);
      expect(a.readiness, CsReadiness.stop);
      expect(a.verdict(CsGas.o2).enteredLater, isTrue);
      // Odczyt zapisu: chwila wpisu z przyszłości jest nieważna (null),
      // nie przycięta do „teraz”; ocena po odczycie — nadal STOP.
      final back = ConfinedSpaceRecord.fromJson(
          jsonDecode(jsonEncode(r.toJson())),
          now: now)!;
      final ok = back.measurements.firstWhere((m) => m.id == 'ok');
      expect(ok.enteredAt, isNull);
      expect(ok.enteredAsOf(now), _at(13, 50));
      expect(back.assess(now: now).readiness, CsReadiness.stop);
    });
  });

  group('nie dotyczy', () {
    test('tylko przy punktach, które na to pozwalają', () {
      final r = _blank();
      expect(r.toggleNa('perm-written').na, isEmpty);
      expect(r.toggleNa('nie-ma-takiego').na, isEmpty);
      final na = r.toggleNa('gas-cyl-outside');
      expect(na.na, {'gas-cyl-outside'});
      final checked = na.toggleChecked('gas-cyl-outside');
      expect(checked.na, isEmpty);
      expect(checked.checked, {'gas-cyl-outside'});
    });

    test('„n/d” przy punkcie podstawowym z zapisu nie zwalnia go', () {
      final r = _blank().copyWith(na: {'res-attendant'});
      expect(r.isNa(confinedSpaceCheckById('res-attendant')!), isFalse);
      expect(r.assess(now: _now).openBefore.map((c) => c.id),
          contains('res-attendant'));
    });
  });

  group('jak wczoraj', () {
    test('kopia: dane, osoby, progi zostają; pomiary i odhaczenia NIE', () {
      final src = _full();
      final copy = src.duplicateFor(newId: 'nowy', now: _now);
      expect(copy.id, 'nowy');
      expect(copy.date, '2026-10-17');
      expect(copy.location, src.location);
      expect(copy.processes, src.processes);
      expect(copy.attendant, src.attendant);
      expect(copy.rescue, src.rescue);
      expect(copy.limits, src.limits);
      expect(copy.maxAgeMin, 15);
      // Wymagane gazy wracają do czterech — wyłączenie to decyzja na dzień.
      expect(copy.requiredGases, kCsDefaultRequired);
      expect(copy.measurements, isEmpty);
      expect(copy.checked, isEmpty);
      expect(copy.na, isEmpty);
      expect(copy.permitNo, isEmpty);
      expect(copy.notes, isEmpty);
      expect(copy.assess(now: _now).readiness, CsReadiness.noMeasurement);
      expect(copy.isBlank, isFalse);
    });
  });

  group('pomiary: usuwanie i przywracanie', () {
    test('restoreMeasurement przywraca raz (idempotentnie)', () {
      final m = _full().measurements.last;
      final r = _full().removeMeasurement(m);
      expect(r.measurements, hasLength(1));
      final back = r.restoreMeasurement(m);
      expect(back.measurements, hasLength(2));
      expect(back.restoreMeasurement(m).measurements, hasLength(2));
    });

    test('dwa identyczne odczyty: usuwanie i „Cofnij” po identyfikatorze',
        () {
      final a = _m(7, 20, id: 'a');
      final b = _m(7, 20, id: 'b');
      final r = _blank().addMeasurement(a).addMeasurement(b);
      final removed = r.removeMeasurement(b);
      expect(removed.measurements.map((m) => m.id), ['a']);
      final back = removed.restoreMeasurement(b);
      expect(back.measurements.map((m) => m.id), ['a', 'b']);
    });
  });

  group('JSON', () {
    test('tam i z powrotem — wszystkie pola', () {
      final r = _full();
      final back =
          ConfinedSpaceRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(jsonEncode(back.toJson()), jsonEncode(r.toJson()));
      expect(back.limits[CsBound.lelMax], const CsQty(5, CsUnit.pctLel));
      expect(back.maxAgeMin, 15);
      expect(back.requiredGases, {CsGas.o2, CsGas.lel, CsGas.co});
      expect(back.measurements, r.measurements);
      expect(back.droppedOnLoad, 0);
    });

    test('stary zapis bez identyfikatorów pomiarów dostaje je z pozycji', () {
      final json = _full().toJson();
      for (final m in json['measurements'] as List) {
        (m as Map).remove('id');
      }
      final r = ConfinedSpaceRecord.fromJson(jsonDecode(jsonEncode(json)))!;
      expect(r.measurements.map((m) => m.id), ['abc-m0', 'abc-m1']);
    });

    test('uszkodzone pomiary i protokoły są liczone, nie znikają po cichu',
        () {
      final json = _full().toJson();
      json['measurements'] = [
        ...(json['measurements'] as List),
        {'time': '10:00', 'at': 'wczoraj', 'o2': {'v': 20.9, 'u': 'pctVol'}},
        {'time': '10:05', 'at': 5, 'o2': {'v': -3, 'u': 'pctVol'}},
        'śmieć',
      ];
      final parsed = confinedSpaceRecordsFromJson(jsonDecode(jsonEncode([
        json,
        'śmieć',
        {'id': '', 'date': '2026-10-17'},
        {'id': 'x'},
      ])));
      expect(parsed.records.single.id, 'abc');
      expect(parsed.records.single.measurements, hasLength(2));
      expect(parsed.records.single.droppedOnLoad, 3);
      expect(parsed.droppedMeasurements, 3);
      expect(parsed.droppedRecords, 3);
      expect(parsed.damaged, isTrue);
      expect(() => confinedSpaceRecordsFromJson('nie lista'),
          throwsFormatException);
    });

    test('pomiar z przyszłości odrzucony przy odczycie i policzony', () {
      final r = _blank().addMeasurement(_m(7, 20)).addMeasurement(
          _m(9, 0, id: 'future')); // 1,5 h po „teraz” 07:30
      final parsed = confinedSpaceRecordsFromJson(
          jsonDecode(jsonEncode([r.toJson()])),
          now: _now);
      expect(parsed.records.single.measurements.map((m) => m.time),
          ['07:20']);
      expect(parsed.droppedMeasurements, 1);
      // W zapasie 5 min — przyjęty.
      final near = confinedSpaceRecordsFromJson(
          jsonDecode(jsonEncode([r.toJson()])),
          now: _t(8, 55));
      expect(near.droppedMeasurements, 0);
    });

    test('nieznane punkty i „n/d” przy punkcie podstawowym są pomijane', () {
      final json = _full().toJson()
        ..['checked'] = ['perm-written', 'stary-punkt', 7]
        ..['na'] = ['res-attendant', 'clean-sewer']
        ..['processes'] = ['tig', 'teleportacja'];
      final r = ConfinedSpaceRecord.fromJson(json)!;
      expect(r.checked, {'perm-written'});
      expect(r.na, {'clean-sewer'});
      expect(r.processes, {CsProcess.tig});
    });
  });
}
