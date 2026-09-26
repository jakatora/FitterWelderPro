// Przypadki z sond przeglądu G3 (docs/przeglad-modulow/G3-siodlo-iso-skaner.md,
// sekcja iso-notebook) jako testy domeny zeszytu ISO: każda sonda, która
// dawała błędne cięcie bez ostrzeżenia, ma tu swój przypadek z ręcznym
// przeliczeniem.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/iso_notebook/sketch_cut.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_to_project.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/models/prefab/end_connection.dart';
import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/services/takeout_catalog.dart';

import 'sketch_fakes.dart';

const _tol = kSketchJointTolerance;

Comp _elbow(Offset p, {int? cte = 152, int dn = 100}) =>
    Comp(p, 'elbow90', dn: dn, cteMm: cte);

Comp _wn(Offset p, {int y = 76}) => Comp(p, 'flange',
    dn: 100,
    physicalLengthMm: y,
    endA: EndConnection.weldNeck,
    endB: EndConnection.none);

double _stored(SketchSegmentPlan s, double gap) =>
    PrefabEngine.storedSegmentCutMm(
      isoMm: s.isoMm,
      isoRef: s.isoRef,
      startKind: s.start.kind,
      startValueMm: s.start.valueMm,
      endKind: s.end.kind,
      endValueMm: s.end.valueMm,
      gapMm: gap,
    );

void main() {
  // ── Sonda G: kołnierz / zawór na końcu ────────────────────────────────
  group('sonda G — kolano → kołnierz WN DN100, ISO 1000', () {
    final e = gp(0, 0);
    final f = gp(8, 0);
    final comps = <SketchComponent>[_elbow(e), _wn(f)];

    test('domyślnie jak w kreatorze: oś kolana → przylga kołnierza', () {
      final pipe = Pipe(e, f, Dim('1000'));
      final d = sketchDefaultStops(pipe, comps, _tol);
      expect(d.a, SideStop.centre);
      expect(d.b, SideStop.end, reason: 'kołnierz: przez szyjkę do przylgi');
    });

    test('1000 − 152 − 76 − 2 × 3 = 766 (szczelina 3), 772 bez szczeliny', () {
      final pipe =
          Pipe(e, f, Dim('1000', stopA: SideStop.centre, stopB: SideStop.end));
      expect(sketchCutMm(pipe, comps, gapMm: 3), 766);
      expect(sketchCutMm(pipe, comps), 772);
      final plan =
          planProjectFromSketch(pipes: [pipe], components: comps, gapMm: 3);
      final s = plan.segments.single;
      expect(s.cutMm, 766);
      expect(s.end.refCode, 'FACE_FAR');
      expect(s.end.valueMm, 76);
      expect(_stored(s, 3), 766, reason: 'wiersz tłumaczy swoje cięcie');
    });

    test('„do spoiny kołnierza” (bez Y) monter musi wybrać świadomie: 842', () {
      final pipe =
          Pipe(e, f, Dim('1000', stopA: SideStop.centre, stopB: SideStop.face));
      expect(sketchCutMm(pipe, comps, gapMm: 3), 842);
    });

    test('stary wymiar z domyślnym „oś-oś” przy kołnierzu = niepotwierdzony',
        () {
      final legacy = Pipe(e, f, Dim('1000'));
      final b = sketchCutBreakdown(legacy, comps, gapMm: 3)!;
      expect(b.refUnconfirmed, isTrue);
      final plan =
          planProjectFromSketch(pipes: [legacy], components: comps, gapMm: 3);
      expect(plan.segments, isEmpty, reason: 'nie wolno zapisać 842 po cichu');
      expect(plan.skipped.single.reason.pl, contains('punkt odniesienia'));
    });

    test('stary wymiar z jawnie wybranym CTE działa jak dawniej: 766', () {
      final legacy = Pipe(e, f, Dim('1000', ref: DimRef.centreToEnd));
      expect(sketchCutBreakdown(legacy, comps)!.refUnconfirmed, isFalse);
      expect(sketchCutMm(legacy, comps, gapMm: 3), 766);
    });

    test('zawór na końcu: domyślnie do czoła zaworu — korpus zostaje w rurze',
        () {
      final valve = Comp(f, 'gateValve', dn: 100, physicalLengthMm: 229);
      final pipe = Pipe(e, f, Dim('1000'));
      final d = sketchDefaultStops(pipe, [_elbow(e), valve], _tol);
      expect(d.b, SideStop.face);
      final chosen = Pipe(e, f, Dim('1000', stopA: d.a, stopB: d.b));
      expect(sketchCutMm(chosen, [_elbow(e), valve], gapMm: 3), 1000 - 152 - 6);
    });

    test('spool między dwoma kołnierzami WN: przez szyjkę na obu końcach', () {
      // DimRef nie ma kodu na „koniec–koniec”; jawne stopy go mają.
      final f1 = gp(0, 4);
      final f2 = gp(8, 4);
      final pipe =
          Pipe(f1, f2, Dim('1000', stopA: SideStop.end, stopB: SideStop.end));
      final comps2 = [_wn(f1), _wn(f2)];
      expect(sketchCutMm(pipe, comps2, gapMm: 3), 1000 - 76 - 76 - 6);
      final plan =
          planProjectFromSketch(pipes: [pipe], components: comps2, gapMm: 3);
      expect(plan.segments.single.cutMm, 842);
      expect(_stored(plan.segments.single, 3), 842);
    });

    test('słowa zamiast kodów', () {
      final w = sketchStopWords(SketchEndKind.flange, SideStop.end);
      expect(w.pl, contains('przylgi'));
      expect(w.pl, isNot(contains('CTE')));
      expect(sketchStopOptionsFor(SketchEndKind.flange).first, SideStop.end);
      expect(sketchStopOptionsFor(SketchEndKind.body).first, SideStop.face);
    });
  });

  // ── Sonda A: nieczytelny wiersz odliczenia ────────────────────────────
  group('sonda A — nieczytelne odliczenie ręczne', () {
    final e1 = gp(0, 0);
    final e2 = gp(8, 0);
    final comps = <SketchComponent>[_elbow(e1), _elbow(e2)];

    test('czytelny wiersz „3” odejmuje się: 2000 − 304 − 6 − 3 = 1687', () {
      final pipe = Pipe(e1, e2, Dim('2000', deducts: [Ded('Uszczelka', '3')]));
      expect(sketchCutMm(pipe, comps, gapMm: 3), 1687);
    });

    for (final bad in ['3+', '76+']) {
      test('„$bad” (operator z paska na końcu): brak cięcia, nie 1690', () {
        final pipe =
            Pipe(e1, e2, Dim('2000', deducts: [Ded('Uszczelka', bad)]));
        final b = sketchCutBreakdown(pipe, comps, gapMm: 3)!;
        expect(b.unreadableDeducts.single.value, bad);
        expect(b.cutMm.isNaN, isTrue);
        final plan =
            planProjectFromSketch(pipes: [pipe], components: comps, gapMm: 3);
        expect(plan.segments, isEmpty);
        expect(plan.skipped.single.reason.pl,
            allOf(contains('nieczytelne odliczenie'), contains(bad)));
      });
    }
  });

  // ── Sonda B: ręczny CTE kolana bez specyfikacji ───────────────────────
  group('sonda B — ręczny wiersz za kolano bez CTE', () {
    final e1 = gp(0, 0);
    final e2 = gp(8, 0);
    final noSpec = _elbow(e1, cte: null);
    final specced = _elbow(e2);
    final pipe =
        Pipe(e1, e2, Dim('2000', deducts: [Ded('Kolano 90° LR (CTE)', '152')]));

    test('wiersz należy do kolana bez CTE: 2000 − 152 − 152 − 6 = 1690', () {
      final b = sketchCutBreakdown(pipe, [noSpec, specced], gapMm: 3)!;
      expect(b.cutMm, 1690, reason: 'było 1842 — drugie kolano bez odliczenia');
      expect(b.axial.missing, isEmpty,
          reason: 'lista nie może mówić „NIE odjęto”');
      expect(b.axial.claimedByHand, [noSpec]);
      expect(b.axial.rightMm, 152);
    });

    test('kolejność na liście komponentów nie ma znaczenia', () {
      expect(sketchCutMm(pipe, [specced, noSpec], gapMm: 3), 1690);
    });

    test('projekt powstaje z tym samym cięciem', () {
      final plan = planProjectFromSketch(
          pipes: [pipe], components: [noSpec, specced], gapMm: 3);
      expect(plan.segments.single.cutMm, 1690);
      expect(_stored(plan.segments.single, 3), 1690);
    });

    test('bez wiersza ręcznego kolano bez CTE nadal blokuje', () {
      final bare = Pipe(e1, e2, Dim('2000'));
      final b = sketchCutBreakdown(bare, [noSpec, specced])!;
      expect(b.axial.missing, [noSpec]);
      final plan =
          planProjectFromSketch(pipes: [bare], components: [noSpec, specced]);
      expect(plan.segments, isEmpty);
    });
  });

  // ── Sonda C: trójnik redukcyjny ───────────────────────────────────────
  group('sonda C — trójnik DN150×80, odgałęzienie do kolana DN80', () {
    // Przelot: L ─ T ─ R (poziomo), odgałęzienie T ─ E (w dół).
    final l = gp(0, 0);
    final t = gp(8, 0);
    final r = gp(16, 0);
    final e = gp(8, 8);
    final tee = Comp(t, 'tee', dn: 150, dnOut: 80);
    final elbow80 = _elbow(e, dn: 80, cte: 114);
    final branch = Pipe(t, e, Dim('1000'));
    final runL = Pipe(l, t, Dim('1000'));
    final runR = Pipe(t, r, Dim('1000'));
    final pipes = <SketchPipe>[runL, runR, branch];
    final comps = <SketchComponent>[tee, elbow80];
    final m = TakeoutCatalog.reducingTeeOutletM[150]![80]!;
    final c = TakeoutCatalog.tee[150]!;

    test('tabela B16.9: M(6×3) = 4,88" = 124 mm, C(6) = 143 mm', () {
      expect(m, 124);
      expect(c, 143);
    });

    test('odgałęzienie: 1000 − M 124 − 114 = 762 (było 743 z C)', () {
      expect(sketchLegRoleAt(branch, t, pipes, _tol), SketchLegRole.branch);
      expect(sketchCutMm(branch, comps, pipes: pipes), 762);
      expect(sketchCutMm(branch, comps, pipes: pipes, gapMm: 3), 756);
    });

    test('przelot: C 143', () {
      expect(sketchLegRoleAt(runL, t, pipes, _tol), SketchLegRole.run);
      expect(sketchCutMm(runL, comps, pipes: pipes), 1000 - 143);
    });

    test('DN odgałęzienia = 80, przelotu = 150', () {
      expect(sketchInferredDn(branch, comps, _tol, pipes: pipes), 80);
      expect(sketchInferredDn(runL, comps, _tol, pipes: pipes), 150);
    });

    test('projekt: odgałęzienie 762, przelot 857', () {
      final plan = planProjectFromSketch(pipes: pipes, components: comps);
      final byNo = {for (final s in plan.segments) s.sketchPipeNo: s};
      expect(byNo[3]!.cutMm, 762);
      expect(byNo[1]!.cutMm, 857);
      expect(_stored(byNo[3]!, 0), 762);
    });

    test('gdy ze szkicu nie wynika, która to odnoga — brak cięcia, nie C', () {
      final lone = Pipe(t, e, Dim('1000'));
      final b = sketchCutBreakdown(lone, comps, pipes: [lone])!;
      expect(b.axial.teeRoleUnknown, [tee]);
      final plan = planProjectFromSketch(pipes: [lone], components: comps);
      expect(plan.segments, isEmpty);
      expect(plan.skipped.single.reason.pl, contains('trójnik redukcyjny'));
    });

    test('trójnik równy: C na każdej odnodze, jak dawniej', () {
      final equal = Comp(t, 'tee', dn: 100);
      expect(sketchCutMm(branch, [equal], pipes: pipes),
          1000 - TakeoutCatalog.tee[100]!);
    });
  });

  // ── Sonda D: olet w węźle przelotu ────────────────────────────────────
  group('sonda D — olet w punkcie, gdzie spotykają się dwie rury przelotu', () {
    final e1 = gp(0, 0);
    final o = gp(8, 0);
    final e2 = gp(16, 0);
    final top = gp(8, -6);
    final olet = Comp(o, 'olet', dn: 50, cteMm: 60);
    final comps = <SketchComponent>[
      _elbow(e1, dn: 150, cte: 229),
      olet,
      _elbow(e2, dn: 150, cte: 229),
    ];
    final h1 = Pipe(e1, o, Dim('1500'));
    final h2 = Pipe(o, e2, Dim('1500'));
    final br = Pipe(o, top, Dim('500'));
    final pipes = <SketchPipe>[h1, h2, br];

    test('rura główna nie jest skracana o olet ani szczelinę: 1500 − 229 − 3',
        () {
      final b = sketchCutBreakdown(h1, comps, pipes: pipes, gapMm: 3)!;
      expect(b.axial.oletHeaderEnds, [olet]);
      expect(b.welds, 1);
      expect(b.cutMm, 1268, reason: 'było 1205');
    });

    test('odgałęzienie oletu nadal odejmuje jego wysokość', () {
      expect(sketchCutMm(br, comps, pipes: pipes, gapMm: 3), 500 - 60 - 3);
    });

    test('projekt nie powstaje z przelotu narysowanego dwiema liniami', () {
      final plan =
          planProjectFromSketch(pipes: pipes, components: comps, gapMm: 3);
      final skipped = {for (final s in plan.skipped) s.sketchPipeNo};
      expect(skipped, containsAll([1, 2]));
      expect(plan.skipped.first.reason.pl, contains('jedną linią'));
    });
  });
}
