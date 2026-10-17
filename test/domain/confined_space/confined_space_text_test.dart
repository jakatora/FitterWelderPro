// Protokół tekstowy przestrzeni zamkniętej: dane pozwolenia, stan (STOP
// tlenu z przyczyną), progi, pomiary z oceną w jednostce wpisanej,
// ostrzeżenia, punkty [x] / [n/d] / [ ], zastrzeżenie — PL i EN.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/confined_space/confined_space_checklist.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_text.dart';

int _at(int h, int m) => DateTime(2026, 10, 17, h, m).millisecondsSinceEpoch;

ConfinedSpaceRecord _record(List<CsMeasurement> ms) => ConfinedSpaceRecord(
      id: 'r',
      permitNo: 'PZ/7/2026',
      location: 'Zbiornik T-101, właz M1',
      description: 'Spawanie króćca od środka',
      processes: const {CsProcess.tig},
      date: '2026-10-17',
      validFrom: '07:00',
      validTo: '15:00',
      entrants: 'Jan Kowalski',
      attendant: 'Adam Nowak',
      supervisor: 'Ewa Zając',
      issuer: 'Piotr Wiśniewski',
      rescue: 'Trójnóg T-2',
      measurements: ms,
      checked: const {'perm-written'},
      na: const {'clean-sewer'},
      notes: 'Nawiew W-3.',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  test('tekst PL: dane, STOP tlenu, progi, pomiary jak wpisane, punkty', () {
    final text = confinedSpaceProtocolText(
      _record([
        CsMeasurement(
          time: '06:50',
          at: _at(6, 50),
          values: const {
            CsGas.o2: CsQty(20.9, CsUnit.pctVol),
            CsGas.lel: CsQty(0, CsUnit.pctLel),
            CsGas.co: CsQty(23, CsUnit.mgM3),
            CsGas.h2s: CsQty(0, CsUnit.ppm),
          },
          place: 'dno',
        ),
        CsMeasurement(
          time: '09:15',
          at: _at(9, 15),
          values: const {CsGas.o2: CsQty(18.2, CsUnit.pctVol)},
        ),
      ]),
      en: false,
    );
    expect(text,
        startsWith('PRZESTRZEŃ ZAMKNIĘTA — PROTOKÓŁ WEJŚCIA I SPAWANIA'));
    expect(text, contains('(lista pomocnicza — nie zastępuje pozwolenia)'));
    expect(text, contains('Nr pozwolenia: PZ/7/2026'));
    expect(text, contains('Przestrzeń: Zbiornik T-101, właz M1'));
    expect(text, contains('Asekurujący (na zewnątrz): Adam Nowak'));
    expect(text, contains('Plan ratunkowy: Trójnóg T-2'));
    expect(text, contains('STAN: STOP — tlen 18,2 % o 09:15 — poniżej 19,5 %'));
    expect(text, contains('niedotlenienie'));
    expect(text, contains('- O₂: 19,5–23,5 % — wymagany'));
    expect(text, contains('- H₂S: ≤ 7 mg/m³ (≈ 4,9 ppm) — wymagany'));
    // CO wpisane w mg/m³ — w protokole tak, jak wpisano.
    expect(
        text,
        contains('- 06:50 — dno — O₂ 20,9 % (OK) · 0 % DGW (OK) · '
            'CO 23 mg/m³ (OK) · H₂S 0 ppm (OK)'));
    expect(text, contains('- 09:15 — O₂ 18,2 % (ZA MAŁO)'));
    expect(text, contains('OSTRZEŻENIA DLA SPAWACZA'));
    expect(text, contains('Argon i CO₂'));
    final written = confinedSpaceCheckById('perm-written')!;
    final sewer = confinedSpaceCheckById('clean-sewer')!;
    final attendant = confinedSpaceCheckById('res-attendant')!;
    expect(text, contains('[x] ${written.pl}'));
    expect(text, contains('[n/d] ${sewer.pl}'));
    expect(text, contains('[ ] ${attendant.pl}'));
    expect(text, contains('PRZED WEJŚCIEM (2/'));
    expect(text, contains('Uwagi: Nawiew W-3.'));
    expect(text, contains('§§ 85–90'));
    expect(text, endsWith('Fitter Welder Pro'));
  });

  test('brak pomiaru — tekst mówi to wprost', () {
    final text = confinedSpaceProtocolText(_record(const []), en: false);
    expect(text, contains('— brak pomiaru —'));
    expect(text, contains('STAN: Brak odczytu: O₂, DGW, CO, H₂S'));
  });

  test('wzbogacenie tlenem — osobny komunikat', () {
    final r = _record([
      CsMeasurement(
        time: '09:15',
        at: _at(9, 15),
        values: const {CsGas.o2: CsQty(24, CsUnit.pctVol)},
      ),
    ]);
    final s = confinedSpaceReadinessText(r.assess(), r.limits, en: false);
    expect(s, startsWith('STOP — tlen 24 % o 09:15 — powyżej 23,5 %'));
    expect(s, contains('wzbogacenie tlenem'));
    expect(confinedSpaceReadinessText(r.assess(), r.limits, en: true),
        contains('oxygen enrichment'));
  });

  test('tekst EN', () {
    final text = confinedSpaceProtocolText(
      _record([
        CsMeasurement(
          time: '06:50',
          at: _at(6, 50),
          values: const {CsGas.lel: CsQty(1.5, CsUnit.pctLel)},
        ),
      ]),
      en: true,
    );
    expect(text, startsWith('CONFINED SPACE — ENTRY AND WELDING RECORD'));
    expect(text, contains('Work: TIG (argon)'));
    expect(text, contains('- 06:50 — 1.5 % LEL (OK)'));
    expect(text, contains('STATUS: No reading for: O₂, CO, H₂S'));
    expect(text, contains('BEFORE ENTRY (2/'));
    expect(text, contains('Checklist aid only — not a permit.'));
  });

  test('krótkie etykiety stanu i remis', () {
    final ready = _record([
      CsMeasurement(
        time: '07:00',
        at: _at(7, 0),
        values: const {
          CsGas.o2: CsQty(20.9, CsUnit.pctVol),
          CsGas.lel: CsQty(0, CsUnit.pctLel),
          CsGas.co: CsQty(0, CsUnit.ppm),
          CsGas.h2s: CsQty(0, CsUnit.ppm),
        },
      ),
    ]).copyWith(checked: {
      for (final c in confinedSpaceChecksIn(ConfinedSpacePhase.before)) c.id,
    });
    expect(confinedSpaceReadinessShort(ready.assess(), en: false), 'Gotowe');
    final tie = ready.addMeasurement(CsMeasurement(
      time: '07:00',
      at: _at(7, 0) + 30000,
      values: const {CsGas.o2: CsQty(19, CsUnit.pctVol)},
    ));
    final a = tie.assess();
    expect(confinedSpaceReadinessShort(a, en: true), 'STOP — atmosphere');
    expect(csTieText(a.ties.single, en: false),
        startsWith('O₂: różne odczyty z tej samej minuty (07:00)'));
  });
}
