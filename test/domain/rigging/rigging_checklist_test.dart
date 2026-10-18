// Lista kontrolna przed podniesieniem: niezaznaczona ≠ OK, wada = STOP,
// „nie dotyczy” tylko tam, gdzie wolno, etykieta = stan z kalkulatora,
// pozycje zależne od rodzaju zawiesia, gotowość do podniesienia.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_checklist.dart';

Map<String, CheckMark> _allOk(SlingType s) => {
      for (final c in riggingChecksFor(s))
        if (c.id != kRiggingLabelCheckId) c.id: CheckMark.ok,
    };

RiggingResult _calc(RiggingVerdict v) => RiggingResult(verdict: v);

void main() {
  test('pusta lista — niekompletna, nie OK', () {
    final s = evaluateChecklist(SlingType.webbing, {}, LabelState.unknown);
    expect(s.verdict, ChecklistVerdict.incomplete);
    expect(s.uncheckedCount, s.total);
    expect(s.okCount, 0);
  });

  test('jedna pozycja niezaznaczona — nadal niekompletna', () {
    final marks = _allOk(SlingType.chain)..remove('ch-wear');
    final s = evaluateChecklist(SlingType.chain, marks, LabelState.readable);
    expect(s.verdict, ChecklistVerdict.incomplete);
    expect(s.uncheckedCount, 1);
  });

  test('wszystko OK i etykieta czytelna — kompletna', () {
    for (final sling in SlingType.values) {
      final s = evaluateChecklist(sling, _allOk(sling), LabelState.readable);
      expect(s.verdict, ChecklistVerdict.complete, reason: sling.name);
      expect(s.okCount, s.total);
    }
  });

  test('etykieta: stan z kalkulatora — brak = wada, nieznana = bez oceny', () {
    final marks = _allOk(SlingType.webbing);
    // Próba „zaznaczenia” etykiety w mapie nic nie daje — liczy się stan.
    marks[kRiggingLabelCheckId] = CheckMark.ok;
    final missing =
        evaluateChecklist(SlingType.webbing, marks, LabelState.missing);
    expect(missing.verdict, ChecklistVerdict.rejected);
    expect(missing.defects, [kRiggingLabelCheckId]);
    expect(missing.slingRejected, isTrue);
    final unknown =
        evaluateChecklist(SlingType.webbing, marks, LabelState.unknown);
    expect(unknown.verdict, ChecklistVerdict.incomplete);
  });

  test('wada przy zawiesiu → wycofać; wada miejsca → STOP, zawiesie dobre', () {
    final sling = _allOk(SlingType.wireRope)..['wr-wires'] = CheckMark.defect;
    final s1 =
        evaluateChecklist(SlingType.wireRope, sling, LabelState.readable);
    expect(s1.verdict, ChecklistVerdict.rejected);
    expect(s1.slingRejected, isTrue);
    final site = _allOk(SlingType.wireRope)..['site-zone'] = CheckMark.defect;
    final s2 = evaluateChecklist(SlingType.wireRope, site, LabelState.readable);
    expect(s2.verdict, ChecklistVerdict.rejected);
    expect(s2.slingRejected, isFalse);
  });

  test('„nie dotyczy” tylko tam, gdzie wolno — inaczej brak oceny', () {
    final marks = _allOk(SlingType.webbing)
      ..['site-edges'] = CheckMark.na
      ..['fit-hooks'] = CheckMark.na;
    final ok = evaluateChecklist(SlingType.webbing, marks, LabelState.readable);
    expect(ok.verdict, ChecklistVerdict.complete);
    expect(ok.naCount, 2);
    marks['tx-cuts'] = CheckMark.na; // nacięć nie da się „nie dotyczyć”
    final bad =
        evaluateChecklist(SlingType.webbing, marks, LabelState.readable);
    expect(bad.verdict, ChecklistVerdict.incomplete);
  });

  test('pozycje zależą od rodzaju zawiesia', () {
    Set<String> ids(SlingType s) =>
        riggingChecksFor(s).map((c) => c.id).toSet();
    final web = ids(SlingType.webbing);
    final chain = ids(SlingType.chain);
    final rope = ids(SlingType.wireRope);
    expect(web, containsAll(['tx-cuts', 'tx-seams', 'tx-heat', 'tx-chem']));
    expect(web.any((i) => i.startsWith('ch-') || i.startsWith('wr-')), isFalse);
    expect(chain, containsAll(['ch-stretch', 'ch-wear', 'ch-damage']));
    expect(chain.any((i) => i.startsWith('tx-')), isFalse);
    expect(rope, containsAll(['wr-wires', 'wr-deform', 'wr-ends']));
    for (final s in [web, chain, rope]) {
      expect(s, containsAll([kRiggingLabelCheckId, 'site-edges', 'site-zone']));
    }
    // Identyfikatory unikalne, każda pozycja ma źródło.
    expect(
        kRiggingChecks.map((c) => c.id).toSet().length, kRiggingChecks.length);
    expect(kRiggingChecks.where((c) => c.source.isEmpty), isEmpty);
  });

  test('pozycje bezpieczeństwa nie mają „nie dotyczy”', () {
    for (final id in [
      kRiggingLabelCheckId,
      'tx-cuts',
      'ch-stretch',
      'wr-wires',
      'site-zone',
      'site-cog',
      'site-trial',
    ]) {
      expect(kRiggingChecks.firstWhere((c) => c.id == id).naAllowed, isFalse,
          reason: id);
    }
  });

  group('gotowość do podniesienia', () {
    final complete = evaluateChecklist(
        SlingType.chain, _allOk(SlingType.chain), LabelState.readable);
    final incomplete =
        evaluateChecklist(SlingType.chain, {}, LabelState.readable);
    final rejected = evaluateChecklist(
        SlingType.chain,
        _allOk(SlingType.chain)..['ch-wear'] = CheckMark.defect,
        LabelState.readable);

    test('tylko OK z kalkulatora i kompletna lista → można podnosić', () {
      expect(
          liftReadiness(_calc(RiggingVerdict.ok), complete), LiftReadiness.go);
      expect(liftReadiness(_calc(RiggingVerdict.ok), incomplete),
          LiftReadiness.notReady);
      expect(liftReadiness(_calc(RiggingVerdict.incomplete), complete),
          LiftReadiness.notReady);
    });

    test('STOP z kalkulatora albo wada na liście → nie podnoś', () {
      for (final v in [
        RiggingVerdict.overload,
        RiggingVerdict.angleNotAllowed,
        RiggingVerdict.noLabel,
      ]) {
        expect(liftReadiness(_calc(v), complete), LiftReadiness.stop);
      }
      expect(liftReadiness(_calc(RiggingVerdict.ok), rejected),
          LiftReadiness.stop);
    });
  });
}
