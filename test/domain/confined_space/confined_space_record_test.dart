// Protokół wejścia: ocena (brak pomiaru gazu ≠ OK, najpóźniejszy odczyt
// decyduje, remis w minucie → gorszy i zgłoszony), wymagane gazy,
// „nie dotyczy”, „jak wczoraj” bez pomiarów i odhaczeń, JSON i uszkodzony
// JSON (odrzucone pomiary są liczone, nie znikają po cichu).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/confined_space/confined_space_checklist.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';

final _now = DateTime(2026, 10, 17, 7, 30);

int _at(int h, int m, [int s = 0]) =>
    DateTime(2026, 10, 17, h, m, s).millisecondsSinceEpoch;

CsMeasurement _m(int h, int min,
        {double? o2 = 20.9,
        double? lel = 0,
        CsQty? co = const CsQty(0, CsUnit.ppm),
        CsQty? h2s = const CsQty(0, CsUnit.ppm),
        int s = 0,
        String place = ''}) =>
    CsMeasurement(
      time: '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}',
      at: _at(h, min, s),
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
      expect(r.isBlank, isTrue);
      expect(r.date, '2026-10-17');
      expect(r.assess().readiness, CsReadiness.noMeasurement);
    });

    test('wszystko odhaczone, brak pomiaru — NIE zielony', () {
      final r = _blank().copyWith(checked: {
        for (final c in kConfinedSpaceChecks) c.id,
      });
      final a = r.assess();
      expect(a.openBefore, isEmpty);
      expect(a.readiness, CsReadiness.noMeasurement);
      expect(a.readyToEnter, isFalse);
      expect(a.closed, isFalse);
    });

    test('brak odczytu jednego wymaganego gazu ≠ OK', () {
      // Detektor bez H₂S: tlen, DGW i CO w normie — H₂S nadal wymagany.
      final r = _allBefore(_blank()).addMeasurement(_m(7, 20, h2s: null));
      final a = r.assess();
      expect(a.readiness, CsReadiness.noMeasurement);
      expect(a.missing.map((v) => v.gas), [CsGas.h2s]);
      // Pozwolenie nie wymaga H₂S — dopiero wtedy zielony.
      final notRequired = r.withRequired(CsGas.h2s, false);
      expect(notRequired.assess().readiness, CsReadiness.ready);
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
      expect(r.assess().readiness, CsReadiness.ready);
      expect(r.assess().closed, isFalse);
      final closed =
          r.copyWith(checked: {for (final c in kConfinedSpaceChecks) c.id});
      expect(closed.assess().closed, isTrue);
    });

    test('tlen za mało i za dużo — STOP nawet przy odhaczonej liście', () {
      final low = _allBefore(_blank()).addMeasurement(_m(7, 20, o2: 18.5));
      expect(low.assess().readiness, CsReadiness.stop);
      expect(low.assess().stops.single.state, CsReadingState.low);
      final high = _allBefore(_blank()).addMeasurement(_m(7, 20, o2: 24));
      expect(high.assess().readiness, CsReadiness.stop);
      expect(high.assess().stops.single.state, CsReadingState.high);
    });

    test('gaz niewymagany, ale zmierzony ponad próg — też STOP', () {
      final r = _allBefore(_blank())
          .withRequired(CsGas.h2s, false)
          .addMeasurement(_m(7, 20, h2s: const CsQty(10, CsUnit.ppm)));
      expect(r.assess().readiness, CsReadiness.stop);
      expect(r.assess().stops.single.gas, CsGas.h2s);
    });

    test('decyduje NAJPÓŹNIEJSZY odczyt każdego gazu, nie ostatnio dopisany',
        () {
      // 10:30: tlen 18 % (STOP); dopisany potem zaległy pomiar z 09:00
      // z tlenem 20,9 % nie zdejmuje STOP-u.
      var r = _allBefore(_blank()).addMeasurement(_m(10, 30, o2: 18));
      r = r.addMeasurement(_m(9, 0));
      expect(r.assess().readiness, CsReadiness.stop);
      expect(r.measurementsChrono.map((m) => m.time), ['09:00', '10:30']);
      // Nowy pomiar 10:45 po przewietrzeniu — zielony.
      r = r.addMeasurement(_m(10, 45));
      expect(r.assess().readiness, CsReadiness.ready);
      // Najpóźniejszy odczyt liczy się osobno dla każdego gazu: o 11:00
      // zmierzono tylko tlen, CO decyduje odczyt z 10:45.
      r = r.addMeasurement(_m(11, 0, lel: null, co: null, h2s: null));
      expect(r.assess().verdict(CsGas.co).decisive!.time, '10:45');
      expect(r.assess().verdict(CsGas.o2).decisive!.time, '11:00');
    });

    test('remis w tej samej minucie: decyduje gorszy i jest zgłoszony', () {
      final r = _allBefore(_blank())
          .addMeasurement(_m(10, 30, o2: 20.9))
          .addMeasurement(_m(10, 30, o2: 18, s: 40));
      final v = r.assess().verdict(CsGas.o2);
      expect(v.tie, isTrue);
      expect(v.state, CsReadingState.low);
      expect(r.assess().readiness, CsReadiness.stop);
      expect(r.assess().ties.map((t) => t.gas), [CsGas.o2]);
      // Kolejność wpisów nie zmienia wyniku.
      final reversed = _allBefore(_blank())
          .addMeasurement(_m(10, 30, o2: 18, s: 40))
          .addMeasurement(_m(10, 30, o2: 20.9));
      expect(reversed.assess().readiness, CsReadiness.stop);
      // Ten sam odczyt dwa razy to nie remis.
      final same = _allBefore(_blank())
          .addMeasurement(_m(10, 30))
          .addMeasurement(_m(10, 30, s: 20));
      expect(same.assess().ties, isEmpty);
      expect(same.assess().readiness, CsReadiness.ready);
    });

    test('brak progu ocenianego gazu — nie zielony', () {
      final r = _allBefore(_blank())
          .copyWith(
              limits: CsLimits.defaults.withLimit(CsBound.coMax, null))
          .addMeasurement(_m(7, 20));
      expect(r.assess().readiness, CsReadiness.noLimit);
      expect(r.assess().noLimits.single.gas, CsGas.co);
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
      expect(r.assess().openBefore.map((c) => c.id), contains('res-attendant'));
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
      expect(copy.requiredGases, src.requiredGases);
      expect(copy.measurements, isEmpty);
      expect(copy.checked, isEmpty);
      expect(copy.na, isEmpty);
      expect(copy.permitNo, isEmpty);
      expect(copy.notes, isEmpty);
      expect(copy.assess().readiness, CsReadiness.noMeasurement);
      expect(copy.isBlank, isFalse);
    });
  });

  group('pomiary: usuwanie i przywracanie', () {
    test('restoreMeasurement przywraca raz (idempotentnie)', () {
      final m = _m(9, 15);
      final r = _full().removeMeasurement(m);
      expect(r.measurements, hasLength(1));
      final back = r.restoreMeasurement(m);
      expect(back.measurements, hasLength(2));
      expect(back.restoreMeasurement(m).measurements, hasLength(2));
    });
  });

  group('JSON', () {
    test('tam i z powrotem — wszystkie pola', () {
      final r = _full();
      final back =
          ConfinedSpaceRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(jsonEncode(back.toJson()), jsonEncode(r.toJson()));
      expect(back.limits[CsBound.lelMax], const CsQty(5, CsUnit.pctLel));
      expect(back.requiredGases, {CsGas.o2, CsGas.lel, CsGas.co});
      expect(back.measurements, r.measurements);
      expect(back.droppedOnLoad, 0);
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
