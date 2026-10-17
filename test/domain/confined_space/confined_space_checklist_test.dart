// Lista kontrolna przestrzeni zamkniętej: kompletna (fazy, grupy, kluczowe
// punkty z briefu), trwałe identyfikatory, każdy punkt i ostrzeżenie ma
// źródło, PL i EN mają te same liczby, punkty podstawowe bez „n/d”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/confined_space/confined_space_checklist.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_sources.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_text.dart';

/// Liczby w tekście (ASCII — indeksy „O₂”, „H₂S” to nie liczby).
Set<String> _numbers(String s) =>
    RegExp(r'\d+([.,]\d+)?').allMatches(s).map((m) {
      return m.group(0)!.replaceAll(',', '.');
    }).toSet();

void main() {
  test('identyfikatory unikalne, teksty PL i EN niepuste', () {
    final ids = kConfinedSpaceChecks.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final c in kConfinedSpaceChecks) {
      expect(c.id, matches(RegExp(r'^[a-z]+-[a-z0-9-]+$')), reason: c.id);
      expect(c.pl.trim(), isNotEmpty, reason: c.id);
      expect(c.en.trim(), isNotEmpty, reason: c.id);
      expect(confinedSpaceCheckById(c.id), same(c));
    }
  });

  test('lista kompletna: każda grupa i faza ma punkty, kolejność faz', () {
    for (final g in ConfinedSpaceGroup.values) {
      expect(confinedSpaceChecksInGroup(g), isNotEmpty, reason: g.name);
    }
    for (final p in ConfinedSpacePhase.values) {
      expect(confinedSpaceChecksIn(p), isNotEmpty, reason: p.name);
    }
    final phases = kConfinedSpaceChecks.map((c) => c.phase.index).toList();
    expect(phases, [...phases]..sort());
  });

  test('zawartość: kluczowe punkty briefu są na liście', () {
    for (final id in [
      'perm-written', // zezwolenie pisemne
      'iso-blind', // odcięcie i zaślepienie mediów
      'iso-energy', // LOTO
      'clean-empty', // opróżnienie
      'clean-no-oxygen', // nie tlenem
      'atm-measure', // pomiar przed wejściem
      'vent-hatches', // wentylacja ciągła
      'vent-air-only', // nawiew, nie tlen
      'res-attendant', // asekurujący stale na zewnątrz
      'res-harness', // szelki i linka
      'res-signals', // łączność
      'res-plan', // plan ratunkowy
      'el-light', // bezpieczne napięcie
      'gas-cyl-outside', // butle poza zbiornikiem
      'dur-break', // gaz zamknięty w przerwie
    ]) {
      expect(confinedSpaceCheckById(id), isNotNull, reason: id);
    }
    expect(confinedSpaceCheckById('perm-written')!.pl, contains('Pisemne'));
    expect(confinedSpaceCheckById('clean-no-oxygen')!.pl, contains('tlenu'));
    expect(confinedSpaceCheckById('vent-air-only')!.pl, contains('nigdy tlenem'));
    expect(confinedSpaceCheckById('atm-measure')!.pl, contains('przy dnie'));
  });

  test('punkty podstawowe nie mają opcji „nie dotyczy”', () {
    for (final id in [
      'perm-written',
      'perm-supervision',
      'perm-briefing',
      'iso-blind',
      'iso-energy',
      'clean-no-oxygen',
      'atm-meter',
      'atm-measure',
      'vent-hatches',
      'vent-air-only',
      'res-attendant',
      'res-signals',
      'res-harness',
      'res-plan',
      'ppe-monitor',
      'el-light',
      'dur-attendant',
      'dur-monitor',
      'dur-evacuate',
      'aft-headcount',
      'aft-close',
    ]) {
      expect(confinedSpaceCheckById(id)!.naAllowed, isFalse, reason: id);
    }
    // Butle — „n/d” przy pracy bez gazów.
    expect(confinedSpaceCheckById('gas-cyl-outside')!.naAllowed, isTrue);
  });

  test('każdy punkt ma źródło, PL i EN mają te same liczby', () {
    for (final c in kConfinedSpaceChecks) {
      expect(c.source.trim(), isNotEmpty, reason: c.id);
      expect(
          c.source,
          anyOf(contains('rozp.'), contains('praktyka'), contains('MSWiA')),
          reason: c.id);
      // 112 — numer alarmowy, nie parametr bezpieczeństwa.
      final pl = _numbers(c.pl)..remove('112');
      final en = _numbers(c.en)..remove('112');
      expect(pl, en, reason: c.id);
    }
    // Liczby w treści są — i mają źródło z paragrafem.
    final temp = confinedSpaceCheckById('clean-temp')!;
    expect(_numbers(temp.pl), {'5'});
    expect(temp.source, contains('§ 87 ust. 1 pkt 7'));
    final resp = confinedSpaceCheckById('ppe-respirator')!;
    expect(_numbers(resp.pl), {'18'});
    expect(resp.source, contains('§ 89'));
  });

  test('ostrzeżenia dla spawacza: źródło i te same liczby PL/EN', () {
    for (final w in kCsWarnings) {
      expect(w.source.trim(), isNotEmpty, reason: w.id);
      expect(_numbers(w.pl), _numbers(w.en), reason: w.id);
    }
    // Pomoc o PAPR / Cr(VI) — tylko odwołanie tekstowe.
    final fume = kCsWarnings.firstWhere((w) => w.id == 'fume');
    expect(fume.pl, contains('Kiedy PAPR przy spawaniu SS?'));
    expect(fume.en, contains('When PAPR for SS welding?'));
  });

  test('ostrzeżenia wg procesu: argon przy TIG/MIG/formowaniu, tlen zawsze',
      () {
    List<String> ids(Set<CsProcess> p) =>
        confinedSpaceWarnings(p).map((w) => w.id).toList();
    expect(ids({}), ['oxygen']);
    expect(ids({CsProcess.inspection}), ['oxygen']);
    expect(ids({CsProcess.tig}), containsAll(['oxygen', 'inert', 'break', 'arc']));
    expect(ids({CsProcess.purge}), containsAll(['inert', 'purge']));
    expect(ids({CsProcess.mma}), isNot(contains('inert')));
    expect(ids({CsProcess.oxyFuel}), containsAll(['cylinders', 'fume']));
  });

  test('źródła: progi z przepisu / praktyki i liczby PL = EN', () {
    expect(kCsO2MinPct, 19.5);
    expect(kCsO2MaxPct, 23.5);
    expect(kCsLelMaxPct, 10);
    expect(kCsCoNdsPpm, 20);
    expect(kCsCoNdsMgM3, 23);
    expect(kCsH2sNdsMgM3, 7);
    expect(kCsO2NoRespiratorPlPct, 18);
    for (final s in kConfinedSpaceSources) {
      expect(_numbers(s.pl), _numbers(s.en), reason: s.pl);
    }
    expect(kConfinedSpaceSources.first.pl, contains('§§ 85–90'));
    expect(kConfinedSpaceSources[2].pl, contains('Dz.U. 2026 poz. 447'));
  });
}
