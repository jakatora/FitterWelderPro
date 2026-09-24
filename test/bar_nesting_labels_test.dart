// Etykiety segmentów na sztangach i oznaczanie cięć dłuższych od sztangi.
//
// Operator piły dostawał listę samych długości („3293 + 2500”) i nie wiedział,
// która sztuka jest do którego segmentu. Teraz każda sztuka niesie etykietę
// segmentu (S01, S02…), a cięcie dłuższe od sztangi jest oznaczone jako
// części „S04 (1/3)”, „S04 (2/3)”… — bo wymaga dodatkowej spoiny łączącej.
//
// Wyniki optymalizacji (długości, cięcia, reszta) muszą zostać IDENTYCZNE jak
// przed zmianą — pilnuje tego test równoważności z kopią starego algorytmu.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/bar_nesting.dart';

/// Kopia algorytmu sprzed dodania etykiet (bar_nesting.dart z commita 36c20db),
/// zwraca (długości, reszta, cięcia) dla każdej sztangi.
List<(List<double>, double, int)> _referenceNesting({
  required List<double> cutsMm,
  required double stockLengthMm,
  required double sawKerfMm,
}) {
  if (stockLengthMm <= 0) return [];
  final cuts = List<double>.from(cutsMm)..sort((a, b) => b.compareTo(a));
  final plans = <(List<double>, double, int)>[];
  final expanded = <double>[];
  for (final c in cuts) {
    if (c <= 0) continue;
    if (c <= stockLengthMm) {
      expanded.add(c);
    } else {
      var remaining = c;
      while (remaining > stockLengthMm) {
        expanded.add(stockLengthMm);
        remaining -= stockLengthMm;
      }
      if (remaining > 0) expanded.add(remaining);
    }
  }
  expanded.sort((a, b) => b.compareTo(a));
  while (expanded.isNotEmpty) {
    final pieces = <double>[];
    final first = expanded.removeAt(0);
    pieces.add(first);
    double remaining = stockLengthMm - (first + sawKerfMm);
    while (true) {
      final maxPieceAllowed = remaining - sawKerfMm;
      if (maxPieceAllowed <= 0) break;
      int pickedIndex = -1;
      double pickedValue = 0;
      for (var i = 0; i < expanded.length; i++) {
        final v = expanded[i];
        if (v <= maxPieceAllowed && v > pickedValue) {
          pickedValue = v;
          pickedIndex = i;
        }
      }
      if (pickedIndex == -1) break;
      pieces.add(pickedValue);
      expanded.removeAt(pickedIndex);
      remaining -= (pickedValue + sawKerfMm);
    }
    final sumPieces = pieces.fold<double>(0, (a, b) => a + b);
    final fullyConsumed = (stockLengthMm - sumPieces).abs() < 1e-6;
    final cutsCount = fullyConsumed
        ? (pieces.length <= 1 ? 0 : pieces.length - 1)
        : pieces.length;
    var trueRemaining = stockLengthMm - sumPieces - (cutsCount * sawKerfMm);
    if (trueRemaining < 0) trueRemaining = 0;
    plans.add((pieces, trueRemaining, cutsCount));
  }
  return plans;
}

List<String?> _tags(BarPlan plan) => [for (final p in plan.pieces) p.tag];

void main() {
  group('nestPiecesToBars — etykiety segmentów', () {
    test('każda sztuka na sztandze niesie etykietę swojego segmentu', () {
      // 6000 mm, rzaz 3: sztanga 1 = 3293 + 2500 (reszta 201),
      // sztanga 2 = 1200 (reszta 4797).
      final plans = nestPiecesToBars(
        cuts: const [
          CutRequest(1200, label: 'S03'),
          CutRequest(3293, label: 'S01'),
          CutRequest(2500, label: 'S02'),
        ],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );

      expect(plans, hasLength(2));
      expect(plans[0].piecesMm, [3293.0, 2500.0]);
      expect(_tags(plans[0]), ['S01', 'S02']);
      expect(plans[0].remainingMm, closeTo(201, 1e-9));
      expect(plans[1].piecesMm, [1200.0]);
      expect(_tags(plans[1]), ['S03']);
      expect(plans[1].remainingMm, closeTo(4797, 1e-9));
      expect(plans.every((p) => !p.hasSplitPiece), isTrue);
    });

    test('równe długości zachowują kolejność wejścia (deterministycznie)', () {
      final plans = nestPiecesToBars(
        cuts: const [
          CutRequest(1000, label: 'S01'),
          CutRequest(1000, label: 'S02'),
          CutRequest(1000, label: 'S03'),
        ],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans, hasLength(1));
      expect(_tags(plans.single), ['S01', 'S02', 'S03']);
    });

    test('odniesienie ISO segmentu przechodzi do sztuki', () {
      final plans = nestPiecesToBars(
        cuts: const [CutRequest(1500, label: 'S07', reference: '3000+525-80')],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      final piece = plans.single.pieces.single;
      expect(piece.label, 'S07');
      expect(piece.reference, '3000+525-80');
      expect(piece.part, 1);
      expect(piece.partCount, 1);
      expect(piece.isSplit, isFalse);
      expect(piece.sourceLengthMm, 1500);
    });
  });

  group('nestPiecesToBars — cięcie dłuższe niż sztanga', () {
    test('14000 mm na sztangach 6000: trzy części oznaczone 1/3, 2/3, 3/3', () {
      final plans = nestPiecesToBars(
        cuts: const [CutRequest(14000, label: 'S04')],
        stockLengthMm: 6000,
        sawKerfMm: 0,
      );

      expect(plans, hasLength(3));
      expect(plans.map((p) => p.piecesMm), [
        [6000.0],
        [6000.0],
        [2000.0],
      ]);
      expect(plans.map(_tags), [
        ['S04 (1/3)'],
        ['S04 (2/3)'],
        ['S04 (3/3)'],
      ]);
      for (final plan in plans) {
        final piece = plan.pieces.single;
        expect(piece.isSplit, isTrue);
        expect(piece.partCount, 3);
        expect(piece.sourceLengthMm, 14000);
        expect(plan.hasSplitPiece, isTrue);
      }
    });

    test('reszta podzielonego cięcia dzieli sztangę z innym odcinkiem', () {
      // 7000 → 6000 (1/2) + 1000 (2/2). Sztanga 1: 6000 bez cięć.
      // Sztanga 2: 4000 + 1000, 2 cięcia → 6000 − 5000 − 6 = 994 mm.
      final plans = nestPiecesToBars(
        cuts: const [
          CutRequest(7000, label: 'S01'),
          CutRequest(4000, label: 'S02'),
        ],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );

      expect(plans, hasLength(2));
      expect(plans[0].piecesMm, [6000.0]);
      expect(_tags(plans[0]), ['S01 (1/2)']);
      expect(plans[0].cutsCount, 0);
      expect(plans[0].remainingMm, 0);
      expect(plans[1].piecesMm, [4000.0, 1000.0]);
      expect(_tags(plans[1]), ['S02', 'S01 (2/2)']);
      expect(plans[1].cutsCount, 2);
      expect(plans[1].remainingMm, closeTo(994, 1e-9));
      expect(plans[1].hasSplitPiece, isTrue);
    });

    test('cięcie równe sztandze nie jest dzielone', () {
      final plans = nestPiecesToBars(
        cuts: const [CutRequest(6000, label: 'S01')],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(_tags(plans.single), ['S01']);
      expect(plans.single.pieces.single.isSplit, isFalse);
    });

    test('sztuka bez etykiety po podziale ma sam numer części', () {
      final plans = nestCutsToBars(
        cutsMm: const [7000],
        stockLengthMm: 6000,
        sawKerfMm: 0,
      );
      expect(plans.map(_tags), [
        ['(1/2)'],
        ['(2/2)'],
      ]);
    });
  });

  group('wyniki optymalizacji bez zmian', () {
    test('losowe listy: te same długości, cięcia i reszta co stary algorytm',
        () {
      final rnd = Random(20260924);
      for (var round = 0; round < 400; round++) {
        final stock = [6000.0, 6100.0, 12000.0, 3000.0][rnd.nextInt(4)];
        final kerf = [0.0, 1.0, 3.0, 4.5][rnd.nextInt(4)];
        final n = 1 + rnd.nextInt(14);
        final cuts = <double>[
          for (var i = 0; i < n; i++)
            switch (rnd.nextInt(6)) {
              0 => stock, // dokładnie sztanga
              1 => stock * (1 + rnd.nextDouble() * 1.5), // dłuższe
              2 => (rnd.nextInt(8) * 250).toDouble(), // powtórki, też 0
              _ => (50 + rnd.nextInt((stock - 50).toInt())).toDouble(),
            },
        ];
        final expected = _referenceNesting(
          cutsMm: cuts,
          stockLengthMm: stock,
          sawKerfMm: kerf,
        );
        final labelled = nestPiecesToBars(
          cuts: [
            for (var i = 0; i < cuts.length; i++)
              CutRequest(cuts[i], label: 'S${i + 1}'),
          ],
          stockLengthMm: stock,
          sawKerfMm: kerf,
        );
        final plain = nestCutsToBars(
          cutsMm: cuts,
          stockLengthMm: stock,
          sawKerfMm: kerf,
        );
        for (final actual in [labelled, plain]) {
          expect(actual, hasLength(expected.length), reason: 'runda $round');
          for (var b = 0; b < expected.length; b++) {
            expect(actual[b].piecesMm, expected[b].$1,
                reason: 'runda $round, sztanga $b');
            expect(actual[b].remainingMm, expected[b].$2,
                reason: 'runda $round, sztanga $b');
            expect(actual[b].cutsCount, expected[b].$3,
                reason: 'runda $round, sztanga $b');
          }
        }
        // Każda sztuka ma etykietę i poprawny numer części.
        for (final piece in labelled.expand((p) => p.pieces)) {
          expect(piece.label, isNotNull);
          expect(piece.part, inInclusiveRange(1, piece.partCount));
        }
      }
    });

    test('cięcie nieskończone/NaN jest pomijane zamiast zawieszać aplikację',
        () {
      final plans = nestCutsToBars(
        cutsMm: const [double.infinity, double.nan, 1000],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans, hasLength(1));
      expect(plans.single.piecesMm, [1000.0]);
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
