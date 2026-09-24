import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/test_database.dart';

import 'package:cut_list_app/data/tungsten.dart';
import 'package:cut_list_app/database/tandem_amp_param_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/tandem_amp_param.dart';
import 'package:cut_list_app/modules/welder_tandem/tandem_calc.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';
import 'package:cut_list_app/screens/heat_tint_screen.dart';
import 'package:cut_list_app/screens/hydrotest_screen.dart';
import 'package:cut_list_app/screens/passivation_screen.dart';
import 'package:cut_list_app/services/orbital_tig.dart';
import 'package:cut_list_app/utils/rod_optimizer.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(child));
  for (var i = 0; i < 3; i++) {
    await flushTestDatabase(tester);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField labelled $label',
    );

class _ExactTandemDao extends TandemAmpParamDao {
  @override
  Future<TandemAmpParam?> getExact({
    required String position,
    required double t1Mm,
    required double t2Mm,
    required String tempo,
    required bool approved,
  }) async {
    if (!approved) return null;
    return const TandemAmpParam(
      id: 'asymmetric-reference',
      position: 'HORIZONTAL',
      t1Mm: 2,
      t2Mm: 4,
      insideAmps: 83,
      outsideAmps: 137,
      tempo: 'NORMAL',
      approved: true,
      note: null,
      createdAt: 0,
      updatedAt: 0,
    );
  }
}

void main() {
  useTestDatabase();
  group('referencyjne obliczenia spawalnicze', () {
    testWidgets('GTAW 12 V / 100 A / 100 mm/min pokazuje 0.43 kJ/mm',
        (tester) async {
      await _pumpTall(tester, const HeatInputScreen());

      await tester.tap(find.text('GTAW').first);
      await tester.pump();
      await tester.enterText(_field('Voltage'), '12');
      await tester.enterText(_field('Current'), '100');
      await tester.enterText(_field('Travel speed'), '100');
      await tester.pump();

      expect(find.text('0.43'), findsOneWidget,
          reason: '12*100*60/(100*1000)*0.60 = 0.432, shown to 2 decimals');
    });

    for (final speed in ['0', '-1']) {
      testWidgets('heat input rejects travel speed $speed', (tester) async {
        await _pumpTall(tester, const HeatInputScreen());

        await tester.enterText(_field('Travel speed'), speed);
        await tester.pump();

        expect(find.text('Value must be > 0'), findsOneWidget);
      });
    }

    test('orbital TIG returns four finite positive current levels', () {
      final estimate = estimateOrbital(odMm: 50.8, wallMm: 1.65);

      expect(estimate.levelCurrentA, hasLength(4));
      for (final amps in estimate.levelCurrentA) {
        expect(amps.isFinite, isTrue);
        expect(amps, greaterThan(0));
      }
    });

    test('tungsten current boundaries have no uncovered values', () {
      for (var amps = kTungstenSizes.first.minA.toDouble();
          amps <= kTungstenSizes.last.maxA;
          amps += 0.5) {
        final size = sizeForCurrent(amps);
        expect(size, isNotNull, reason: '$amps A must be covered');
        expect(amps, inInclusiveRange(size!.minA, size.maxA),
            reason: '$amps A must lie in the returned band');
      }
    });

    test('tandem TIG preserves inside and outside arcs', () async {
      final result = await TandemCalculator(_ExactTandemDao()).calculate(
        position: 'HORIZONTAL',
        t1Mm: 4,
        t2Mm: 2,
        tempo: 'NORMAL',
      );

      expect(result.insideA, 83);
      expect(result.outsideA, 137);
    });

    test('rod optimizer preserves pieces and never returns negative remainder',
        () {
      final result = RodOptimizer(stockLengthMm: 6000, kerfMm: 3)
          .calculateResult(const [3000, 2000, 900]);
      final bar = result.bars.single;

      expect(
        bar.piecesMm,
        unorderedEquals(const [3000.0, 2000.0, 900.0]),
      );
      expect(bar.cutsCount, 3);
      expect(result.totalKerfLoss, 9);
      expect(result.totalUsedLength, 5909);
      expect(bar.remainingLength, 91);
    });

    test('rod optimizer keeps n-1 cuts for fully consumed stock', () {
      final onePiece = BarPlan(stockLengthMm: 6000, kerfMm: 3)..addPiece(6000);
      final threePieces = BarPlan(stockLengthMm: 6000, kerfMm: 0)
        ..addPiece(2000)
        ..addPiece(2000)
        ..addPiece(2000);
      final twoPiecesWithKerf = BarPlan(stockLengthMm: 6000, kerfMm: 3)
        ..addPiece(2998.5)
        ..addPiece(2998.5);

      expect(onePiece.cutsCount, 0);
      expect(onePiece.usedLength, 6000);
      expect(onePiece.remainingLength, 0);
      expect(threePieces.cutsCount, 2);
      expect(threePieces.usedLength, 6000);
      expect(threePieces.remainingLength, 0);
      expect(twoPiecesWithKerf.cutsCount, 1);
      expect(twoPiecesWithKerf.usedLength, 6000);
      expect(twoPiecesWithKerf.remainingLength, 0);
    });

    test('rod optimizer rejects infeasible 5998 mm piece', () {
      final optimizer = RodOptimizer(stockLengthMm: 6000, kerfMm: 3);

      expect(
        () => optimizer.optimize(const [5998]),
        throwsA(isA<ArgumentError>()
            .having((error) => error.invalidValue, 'invalidValue', 5998)),
      );
      expect(
        () => optimizer.calculateResult(const [5998]),
        throwsArgumentError,
      );
    });

    test('rod optimizer rejects mixed input containing infeasible piece', () {
      final optimizer = RodOptimizer(stockLengthMm: 6000, kerfMm: 3);
      // The full stock piece is placed before the infeasible one after sorting.
      const pieces = [6000.0, 5998.0, 900.0];

      expect(
        () => optimizer.optimize(pieces),
        throwsA(isA<ArgumentError>()
            .having((error) => error.invalidValue, 'invalidValue', 5998)),
      );
      expect(() => optimizer.calculateResult(pieces), throwsArgumentError);
    });

    test('tracked rod plan keeps kerf out of its piece list', () {
      final plan = TrackedBarPlan(stockLengthMm: 6000, kerfMm: 3);

      expect(plan.addPiece(3000, segmentId: 1), isTrue);
      expect(plan.addPiece(2000, segmentId: 2), isTrue);
      expect(plan.addPiece(900, segmentId: 3), isTrue);
      expect(plan.piecesMm, const [3000.0, 2000.0, 900.0]);
      expect(plan.cutsCount, 3);
      expect(plan.usedLength, 5909);
      expect(plan.remainingLength, 91);
    });

    testWidgets('hydrotest rejects pressure beyond the screen range',
        (tester) async {
      await _pumpTall(tester, const HydrotestScreen());

      await tester.enterText(_field('Design pressure (bar)'), '2001');
      await tester.pump();

      expect(find.text('Check pressure'), findsOneWidget);
      expect(find.text('Test pressure'), findsNothing);
    });

    testWidgets('passivation is marked as a non-normative process guide',
        (tester) async {
      await _pumpTall(tester, const PassivationScreen());

      expect(find.textContaining('Process guide'), findsOneWidget);
      expect(find.textContaining('Binding parameters'), findsOneWidget);
    });

    testWidgets('heat tint is marked as indicative, with WPS binding',
        (tester) async {
      await _pumpTall(tester, const HeatTintScreen());

      expect(find.textContaining('O₂ values are indicative'), findsOneWidget);
      expect(find.textContaining('binding acceptance level'), findsOneWidget);
    });
  });
}
