// Przejście kwadrat/prostokąt–koło: linie prawdziwe z rzutu (niezależny
// wzór), suma krawędzi rozwinięcia = obwód prostokąta (dokładnie) i obwód
// koła (z dokładnością próbkowania), części identyczne / lustrzane,
// szwy w narożu i na boku, walidacja.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fitter/cone_development.dart';
import 'package:cut_list_app/domain/fitter/transition_development.dart';

void main() {
  const eps = 1e-6;

  double line(TransitionPart p, String label) =>
      p.trueLines.firstWhere((l) => l.label == label).lengthMm;

  test('kwadrat 600, koło 300, H 400: A–1 522,02, A–3 485,00, trójkąt 427,20',
      () {
    final r = computeTransition(const TransitionInput(
        sideAMm: 600,
        sideBMm: 600,
        diameterMm: 300,
        heightMm: 400,
        divisions: 16,
        parts: 4,
        seam: TransitionSeam.sideA))!;
    // Część 1: M1 (środek boku D–A) → A → M2.
    final p = r.parts.first;
    expect(line(p, 'A–1'), closeTo(522.0153, 1e-4));
    // Punkt 3 = φ 45° (16 podziałów).
    expect(line(p, 'A–3'), closeTo(484.9956, 1e-4));
    expect(r.sides.first.label, 'D–A');
    expect(r.sides.first.heightMm, closeTo(427.2002, 1e-4));
    expect(r.sides.first.lengthMm, closeTo(600, eps));
    // Linia szwu M1–1 = wysokość trójkąta (środek boku pod punktem 1).
    expect(line(p, 'M1–1'), closeTo(427.2002, 1e-4));
  });

  test('niezmienniki: krawędź prostokąta = 2(A + B), krawędź kołowa = π·D', () {
    for (final input in const [
      TransitionInput(
          sideAMm: 600, sideBMm: 600, diameterMm: 300, heightMm: 400),
      TransitionInput(
          sideAMm: 800,
          sideBMm: 500,
          diameterMm: 350,
          heightMm: 300,
          offsetXMm: 120,
          offsetYMm: -40,
          thicknessMm: 4,
          ref: DiameterRef.outside,
          divisions: 24,
          parts: 2,
          seam: TransitionSeam.corner),
      TransitionInput(
          sideAMm: 1000,
          sideBMm: 400,
          diameterMm: 200,
          heightMm: 150,
          divisions: 12,
          parts: 4,
          seam: TransitionSeam.corner),
    ]) {
      final r = computeTransition(input)!;
      expect(r.bottomEdgeMm, closeTo(2 * (r.meanAMm + r.meanBMm), 1e-9));
      expect(r.topEdgeMm,
          closeTo(math.pi * r.meanDMm, math.pi * r.meanDMm * 1e-4));
      // Z części: linie prawdziwe = odległości punktów na blasze.
      for (final part in r.parts) {
        final byLabel = {for (final m in part.pattern.marks) m.label: m.at};
        for (final l in part.trueLines) {
          final ends = l.label.split('–');
          final a = byLabel[ends[0]], b = byLabel[ends[1]];
          if (a == null || b == null) continue;
          // Etykiety końców powtarzają się na szwie (np. D na obu końcach
          // części) — sprawdzamy tylko jednoznaczne.
          if (part.pattern.marks.where((m) => m.label == ends[0]).length > 1 ||
              part.pattern.marks.where((m) => m.label == ends[1]).length > 1) {
            continue;
          }
          expect(a.distanceTo(b), closeTo(l.lengthMm, 1e-6), reason: l.label);
        }
      }
    }
  });

  test('cięciwy na blasze zbieżne do obwodu, dłuższe niż w rzucie', () {
    double sum(int n) {
      final r = computeTransition(TransitionInput(
          sideAMm: 600,
          sideBMm: 400,
          diameterMm: 300,
          heightMm: 350,
          divisions: n))!;
      return r.parts.fold(
          0.0, (s, p) => s + p.topChords.fold(0.0, (t, c) => t + c.lengthMm));
    }

    final circ = math.pi * 300;
    final e12 = circ - sum(12), e48 = circ - sum(48);
    expect(e12, greaterThan(0));
    expect(e48, greaterThan(0));
    expect(e48, lessThan(e12 / 10));
    final r = computeTransition(const TransitionInput(
        sideAMm: 600, sideBMm: 400, diameterMm: 300, heightMm: 350))!;
    for (final c in r.parts.single.topChords) {
      expect(c.lengthMm, greaterThan(r.planChordMm));
    }
  });

  test('kąt wachlarza naroża = suma kątów drobnej triangulacji (niezależnie)',
      () {
    // Naroże A (300, 200, 0), ćwiartka koła 0–90°, koło Ø300 na H 350.
    final r = computeTransition(const TransitionInput(
        sideAMm: 600,
        sideBMm: 400,
        diameterMm: 300,
        heightMm: 350,
        divisions: 16,
        parts: 4,
        seam: TransitionSeam.sideA))!;
    final p = r.parts.first; // M1 → A → M2
    final marks = {for (final m in p.pattern.marks) m.label: m.at};
    final a = marks['A']!, p1 = marks['1']!, p5 = marks['5']!;
    final dev = math.acos(((p1 - a).x * (p5 - a).x + (p1 - a).y * (p5 - a).y) /
        (p1 - a).magnitude /
        (p5 - a).magnitude);
    const m = 20000;
    var sum = 0.0;
    List<double> dir(int j) {
      final f = math.pi / 2 * j / m;
      final x = 150 * math.cos(f) - 300, y = 150 * math.sin(f) - 200;
      const z = 350.0;
      final l = math.sqrt(x * x + y * y + z * z);
      return [x / l, y / l, z / l];
    }

    var prev = dir(0);
    for (var j = 1; j <= m; j++) {
      final cur = dir(j);
      sum += math.acos((prev[0] * cur[0] + prev[1] * cur[1] + prev[2] * cur[2])
          .clamp(-1.0, 1.0));
      prev = cur;
    }
    expect(dev, closeTo(sum, 1e-6));
  });

  test('części: kwadrat — 4 identyczne; prostokąt — ćwiartki lustrzane', () {
    final sq = computeTransition(const TransitionInput(
        sideAMm: 600,
        sideBMm: 600,
        diameterMm: 300,
        heightMm: 400,
        parts: 4,
        seam: TransitionSeam.sideB))!;
    expect(sq.parts, hasLength(4));
    for (final p in sq.parts.skip(1)) {
      expect(p.sameAs, 0);
      expect(p.mirrored, isFalse);
    }
    // Prostokąt 800 × 500: ćwiartka M1–A–M2 ma połówki boków 250 i 400,
    // następna (M2–B–M3) 400 i 250 — lustro; trzecia to obrót o 180°.
    final rect = computeTransition(const TransitionInput(
        sideAMm: 800,
        sideBMm: 500,
        diameterMm: 300,
        heightMm: 400,
        parts: 4,
        seam: TransitionSeam.sideB))!;
    expect(rect.parts[0].sameAs, isNull);
    expect(rect.parts[1].sameAs, 0);
    expect(rect.parts[1].mirrored, isTrue);
    expect(rect.parts[2].sameAs, 0);
    expect(rect.parts[2].mirrored, isFalse);
    expect(rect.parts[1].pattern.widthMm,
        closeTo(rect.parts[0].pattern.widthMm, 1e-6));
    // Połówki współosiowego prostokąta są przystające (obrót o 180°).
    final half = computeTransition(const TransitionInput(
        sideAMm: 800,
        sideBMm: 500,
        diameterMm: 300,
        heightMm: 400,
        parts: 2,
        seam: TransitionSeam.sideA))!;
    expect(half.parts[1].sameAs, 0);
    // Z przesunięciem w X połówki są różne.
    final shifted = computeTransition(const TransitionInput(
        sideAMm: 800,
        sideBMm: 500,
        diameterMm: 300,
        heightMm: 400,
        offsetXMm: 100,
        parts: 2,
        seam: TransitionSeam.sideA))!;
    expect(shifted.parts[1].sameAs, isNull);
  });

  test('szew w narożu przy 12 podziałach — punkt szwu wstawiony (S1)', () {
    final r = computeTransition(const TransitionInput(
        sideAMm: 600,
        sideBMm: 400,
        diameterMm: 300,
        heightMm: 350,
        divisions: 12,
        seam: TransitionSeam.corner))!;
    final p = r.parts.single;
    expect(p.trueLines.first.label, 'C–S1');
    expect(p.trueLines.last.label, 'C–S1');
    // Szew po tworzącej pod 225°: |C − (150·cos 225°, 150·sin 225°, 350)|.
    final c45 = 150 * math.cos(math.pi / 4);
    expect(
        p.trueLines.first.lengthMm,
        closeTo(
            math.sqrt(
                math.pow(300 - c45, 2) + math.pow(200 - c45, 2) + 350 * 350),
            1e-6));
    expect(p.bottomEdgeMm, closeTo(2 * (600 + 400), 1e-9));
  });

  test('przesunięcie: wynik skończony, koło wystające sygnalizowane', () {
    const i = TransitionInput(
        sideAMm: 600,
        sideBMm: 400,
        diameterMm: 300,
        heightMm: 350,
        offsetXMm: 200);
    expect(i.circleOverhangs, isTrue);
    final r = computeTransition(i)!;
    expect(r.parts.single.pattern.widthMm.isFinite, isTrue);
    expect(
        const TransitionInput(
                sideAMm: 600, sideBMm: 400, diameterMm: 300, heightMm: 350)
            .circleOverhangs,
        isFalse);
  });

  test('walidacja', () {
    List<TransitionProblem> p(TransitionInput i) => i.problems;
    expect(
        p(const TransitionInput(
            sideAMm: 0, sideBMm: 400, diameterMm: 300, heightMm: 350)),
        contains(TransitionProblem.sideA));
    expect(
        p(const TransitionInput(
            sideAMm: 600, sideBMm: 400, diameterMm: 300, heightMm: -1)),
        contains(TransitionProblem.height));
    expect(
        p(const TransitionInput(
            sideAMm: 600,
            sideBMm: 400,
            diameterMm: 300,
            heightMm: 350,
            thicknessMm: 150)),
        contains(TransitionProblem.thickness));
    expect(
        p(const TransitionInput(
            sideAMm: 600,
            sideBMm: 400,
            diameterMm: 300,
            heightMm: 350,
            parts: 3)),
        contains(TransitionProblem.parts));
    expect(
        p(const TransitionInput(
            sideAMm: 600, sideBMm: 400, diameterMm: double.nan, heightMm: 350)),
        contains(TransitionProblem.diameter));
    expect(
        computeTransition(const TransitionInput(
            sideAMm: 600, sideBMm: 400, diameterMm: 300, heightMm: 0)),
        isNull);
  });
}
