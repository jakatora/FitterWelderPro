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
      now: DateTime(2026, 10, 17, 9, 20),
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
    expect(text, contains('- H₂S: ≤ 7 mg/m³ (≈ 4,94 ppm) — wymagany'));
    expect(text, contains('- Ważność pomiaru: 30 min — przyjęta w aplikacji'));
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
    final text = confinedSpaceProtocolText(_record(const []),
        en: false, now: DateTime(2026, 10, 17, 9, 20));
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
    final now = DateTime(2026, 10, 17, 9, 20);
    final s =
        confinedSpaceReadinessText(r.assess(now: now), r.limits, en: false);
    expect(s, startsWith('STOP — tlen 24 % o 09:15 — powyżej 23,5 %'));
    expect(s, contains('wzbogacenie tlenem'));
    expect(confinedSpaceReadinessText(r.assess(now: now), r.limits, en: true),
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
      now: DateTime(2026, 10, 17, 7),
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
    final now = DateTime(2026, 10, 17, 7, 5);
    expect(confinedSpaceReadinessShort(ready.assess(now: now), en: false),
        'Gotowe');
    final tie = ready.addMeasurement(CsMeasurement(
      time: '07:00',
      at: _at(7, 0) + 30000,
      values: const {CsGas.o2: CsQty(19, CsUnit.pctVol)},
    ));
    final a = tie.assess(now: now);
    expect(confinedSpaceReadinessShort(a, en: true), 'STOP — atmosphere');
    expect(csTieText(a.ties.single, en: false),
        startsWith('O₂: różne odczyty z tej samej minuty (07:00)'));
  });

  test('pomiar nieaktualny, protokół z innego dnia, data przy pomiarze', () {
    const all = {
      CsGas.o2: CsQty(20.9, CsUnit.pctVol),
      CsGas.lel: CsQty(0, CsUnit.pctLel),
      CsGas.co: CsQty(0, CsUnit.ppm),
      CsGas.h2s: CsQty(0, CsUnit.ppm),
    };
    final r = _record([
      // Pomiar z wczoraj 23:50 w protokole z 2026-10-17.
      CsMeasurement(
          time: '23:50',
          at: DateTime(2026, 10, 16, 23, 50).millisecondsSinceEpoch,
          values: all),
    ]);
    final now = DateTime(2026, 10, 17, 7);
    final a = r.assess(now: now);
    expect(confinedSpaceReadinessText(a, r.limits, en: false),
        'Pomiar nieaktualny: O₂ z 2026-10-16 23:50, DGW z 2026-10-16 23:50, '
        'CO z 2026-10-16 23:50, H₂S z 2026-10-16 23:50 (ważny 30 min) — '
        'zmierz ponownie.');
    expect(confinedSpaceReadinessShort(a, en: false), 'Pomiar nieaktualny');
    final text = confinedSpaceProtocolText(r, en: false, now: now);
    expect(text, contains('- 2026-10-16 23:50 — O₂ 20,9 % (OK)'));

    // Ten sam protokół następnego dnia — nieaktualny, z dopiskiem.
    final closed = r.copyWith(checked: {
      for (final c in kConfinedSpaceChecks) c.id,
    });
    final tomorrow = DateTime(2026, 10, 18, 7);
    final b = closed.assess(now: tomorrow);
    expect(b.readyToEnter, isFalse);
    expect(confinedSpaceReadinessShort(b, en: false),
        'Zamknięte · nieaktualne');
    expect(confinedSpaceReadinessShort(r.assess(now: tomorrow), en: false),
        'Nieaktualne');
    expect(confinedSpaceReadinessText(r.assess(now: tomorrow), r.limits,
            en: false),
        startsWith('Protokół z dnia 2026-10-17 — nieaktualny'));
  });

  test('STOP bez progu z pozwolenia — granica twarda w tekście; ≈ 4,94 ppm',
      () {
    final r = _record([
      CsMeasurement(
          time: '07:00',
          at: _at(7, 0),
          values: const {CsGas.co: CsQty(500, CsUnit.ppm)}),
    ]).copyWith(limits: CsLimits.defaults.withLimit(CsBound.coMax, null));
    final s = confinedSpaceReadinessText(
        r.assess(now: DateTime(2026, 10, 17, 7, 5)), r.limits,
        en: false);
    expect(s, startsWith('STOP — CO 500 ppm o 07:00 — powyżej progu 20 ppm '
        '(granica twarda, brak progu z pozwolenia)'));
    expect(
        formatCsLimit(CsBound.h2sMax, const CsQty(7, CsUnit.mgM3), en: false),
        '7 mg/m³ (≈ 4,94 ppm)');
    expect(csPpmPreview(CsGas.co, const CsQty(23, CsUnit.mgM3), en: true),
        '≈ 19.75 ppm');
  });
}
