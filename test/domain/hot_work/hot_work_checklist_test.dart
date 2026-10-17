// Lista kontrolna prac pożarowo niebezpiecznych: kompletna (wszystkie grupy
// i fazy), trwałe identyfikatory, liczby tylko ze źródłem, punkty
// podstawowe bez „nie dotyczy”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/hot_work/hot_work_checklist.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_sources.dart';

Set<String> _numbers(String s) =>
    RegExp(r'\d+').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  test('identyfikatory unikalne, teksty PL i EN niepuste', () {
    final ids = kHotWorkChecks.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final c in kHotWorkChecks) {
      expect(c.id, matches(RegExp(r'^[a-z]+-[a-z-]+$')), reason: c.id);
      expect(c.pl.trim(), isNotEmpty, reason: c.id);
      expect(c.en.trim(), isNotEmpty, reason: c.id);
      expect(hotWorkCheckById(c.id), same(c));
    }
  });

  test('lista kompletna: każda grupa i każda faza ma punkty', () {
    for (final g in HotWorkGroup.values) {
      expect(hotWorkChecksInGroup(g), isNotEmpty, reason: g.name);
    }
    for (final p in HotWorkPhase.values) {
      expect(hotWorkChecksIn(p), isNotEmpty, reason: p.name);
      expect(hotWorkGroupsIn(p), isNotEmpty, reason: p.name);
    }
    // Wymagane obszary przygotowania stanowiska (brief modułu).
    expect(
      HotWorkGroup.values.map((g) => g.name),
      containsAll([
        'combustibles',
        'openings',
        'atmosphere',
        'extinguishing',
        'shields',
        'ventilation',
        'cylinders',
        'equipment',
        'ppe',
        'watchDuring',
        'closeOut',
      ]),
    );
    // Kolejność listy = kolejność faz (przed → w trakcie → po).
    final phases = kHotWorkChecks.map((c) => c.phase.index).toList();
    expect(phases, [...phases]..sort());
  });

  test('zawartość: kluczowe punkty bezpieczeństwa są na liście', () {
    for (final id in [
      'perm-written',
      'perm-persons',
      'comb-remove',
      'comb-cover',
      'open-cover',
      'atm-measure',
      'ext-ready',
      'shield-screens',
      'vent-ok',
      'cyl-secured',
      'cyl-flashback',
      'weq-return',
      'ppe-basic',
      'dur-watch',
      'aft-inspect',
      'aft-watch',
    ]) {
      expect(hotWorkCheckById(id), isNotNull, reason: id);
    }
    expect(hotWorkCheckById('weq-return')!.pl, contains('jak najbliżej'));
    expect(hotWorkCheckById('cyl-flashback')!.pl, contains('bezpiecznik'));
  });

  test('punkty podstawowe nie mają opcji „nie dotyczy”', () {
    for (final id in [
      'perm-written',
      'perm-persons',
      'perm-briefing',
      'comb-remove',
      'comb-floor',
      'atm-meter',
      'atm-measure',
      'ext-ready',
      'dur-watch',
      'dur-stop',
      'aft-inspect',
      'aft-watch',
      'aft-handover',
    ]) {
      expect(hotWorkCheckById(id)!.naAllowed, isFalse, reason: id);
    }
    // Butle — „n/d” przy pracy bez gazów.
    expect(hotWorkCheckById('cyl-flashback')!.naAllowed, isTrue);
  });

  test('każda liczba w punkcie ma źródło, PL i EN mają te same liczby', () {
    for (final c in kHotWorkChecks) {
      // 112 — numer alarmowy, nie parametr bezpieczeństwa.
      final pl = _numbers(c.pl)..remove('112');
      final en = _numbers(c.en)..remove('112');
      expect(pl, en, reason: c.id);
      if (pl.isNotEmpty) {
        expect(c.source, isNotNull, reason: '${c.id}: liczby $pl bez źródła');
      }
    }
  });

  test('przepis PL bez odległości i czasu — liczby praktyki podpisane', () {
    final remove = hotWorkCheckById('comb-remove')!;
    expect(remove.pl, contains('wg zezwolenia'));
    expect(remove.pl, contains('praktyka'));
    expect(remove.source, contains('§ 36 ust. 2'));
    final watch = hotWorkCheckById('aft-watch')!;
    expect(watch.pl, contains('wskazany w zezwoleniu'));
    expect(watch.pl, contains('NFPA 51B:2019'));
    expect(watch.source, contains('praktyka'));
  });

  test('domyślny próg DGW = 10 % (rozp. MSWiA § 36 ust. 2)', () {
    expect(kHotWorkDefaultDgwLimitPct, 10);
    expect(kHotWorkSources.first.pl, contains('§ 36'));
    expect(kHotWorkSources.first.pl, contains('10 % DGW'));
    for (final s in kHotWorkSources) {
      expect(s.en.trim(), isNotEmpty);
    }
  });
}
