// Lista kontrolna przed pracą szlifierką: punkt niezaznaczony ≠ OK, trwałe
// identyfikatory, źródło przy każdym punkcie, bieg próbny 1 min,
// odsyłacz do modułu prac pożarowych.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/grinding/grinding_checklist.dart';
import 'package:cut_list_app/domain/grinding/grinding_sources.dart';

void main() {
  test(
      'identyfikatory unikalne i trwałe; teksty PL i EN; źródło albo '
      'reguła aplikacji', () {
    final ids = kGrindingChecks.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, [
      'guard',
      'handle',
      'flanges',
      'inspect',
      'test-run',
      'bystanders',
      'ppe',
      'sparks',
      'workpiece',
      'switch',
    ]);
    for (final c in kGrindingChecks) {
      expect(c.pl.trim(), isNotEmpty, reason: c.id);
      expect(c.en.trim(), isNotEmpty, reason: c.id);
      expect(c.sourceLabel(en: false), isNotNull, reason: c.id);
      expect(grindingCheckById(c.id), same(c));
    }
    expect(grindingCheckById('switch')!.sourceLabel(en: false), kSrcApp);
  });

  test('punkt niezaznaczony ≠ OK: gotowe dopiero przy wszystkich', () {
    expect(evaluateChecklist({}).complete, isFalse);
    expect(evaluateChecklist({}).missing, hasLength(kGrindingChecks.length));
    final allButOne = {for (final c in kGrindingChecks.skip(1)) c.id};
    final s = evaluateChecklist(allButOne);
    expect(s.complete, isFalse);
    expect(s.missing.single.id, 'guard');
    expect(s.checked, kGrindingChecks.length - 1);
    final all = evaluateChecklist({for (final c in kGrindingChecks) c.id});
    expect(all.complete, isTrue);
    expect(all.checked, all.total);
  });

  test('nieznane identyfikatory nie dopełniają listy', () {
    final s = evaluateChecklist({
      for (final c in kGrindingChecks.skip(1)) c.id,
      'stary-punkt',
      'guard-v0',
    });
    expect(s.complete, isFalse);
    expect(s.checked, kGrindingChecks.length - 1);
  });

  test('bieg próbny 1 min (EN 62841-2-3), nie 30 s', () {
    expect(kTestRunMinutes, 1);
    final c = grindingCheckById('test-run')!;
    expect(c.pl, contains('1 min'));
    expect(c.en, contains('1 min'));
    expect(c.pl, isNot(contains('30 s')));
    expect(c.source, kSrcEn62841);
  });

  test('iskry: odsyłacz do modułu „Prace pożarowo niebezpieczne”', () {
    final c = grindingCheckById('sparks')!;
    expect(c.pl, contains('„Prace pożarowo niebezpieczne”'));
    expect(c.en, contains('Hot work permit'));
  });

  test('ŚOI: oczy, słuch, ręce', () {
    final c = grindingCheckById('ppe')!;
    expect(c.pl, contains('Okulary'));
    expect(c.pl, contains('ochronniki słuchu'));
    expect(c.pl, contains('rękawice'));
  });
}
