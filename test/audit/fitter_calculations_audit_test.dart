import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/screens/pipe_slope_screen.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';
import 'package:cut_list_app/services/bar_nesting.dart';
import 'package:cut_list_app/services/cut_calculator.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/services/saddle_template.dart';
import 'package:cut_list_app/services/scan_to_project.dart';
import 'package:cut_list_app/services/unit_parser.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

AiScanResult _dn100Scan({
  required String schedule,
  List<AiComponent> components = const [],
  List<AiSegment> segments = const [],
}) =>
    AiScanResult(
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-P-1001',
        material: 'A312 TP316L',
        schedule: schedule,
      ),
      components: components,
      segments: segments,
      sizeNotation: 'DN',
    );

AiComponent _component(String id, String type) => AiComponent(
      id: id,
      type: type,
      confidence: AiConfidence.high,
    );

AiSegment _segment(String id, String from, String to, double dimensionMm) =>
    AiSegment(
      id: id,
      fromId: from,
      toId: to,
      dimensionMm: dimensionMm,
      confidence: AiConfidence.high,
    );

Finder _editableWithValue(String value) => find.byWidgetPredicate(
      (widget) => widget is EditableText && widget.controller.text == value,
      description: 'editable text with value $value',
    );

Finder _textFieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'text field with label $label',
    );

Future<void> _calculate(WidgetTester tester) async {
  final button = find.text('CALCULATE');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('referencyjne obliczenia monterskie', () {
    test('1 in = 25.4 mm, a 1 1/2 in = 38.1 mm', () {
      expect(UnitParser.parseToMm('1 in'), closeTo(25.4, 1e-9));
      expect(UnitParser.parseToMm('1 1/2 in'), closeTo(38.1, 1e-9));
    });

    test('kolano 90° LR DN100 ma take-out 152 mm', () {
      final elbow = kElbowTakeouts.singleWhere((entry) => entry.dn == 100);

      expect(elbow.lr90, 152);
    });

    test('odcinek 1200 mm między dwoma kolanami ma CUT 896 mm', () {
      final cut = calculateCutOffsets(
        isoMm: 1200,
        startOffsetMm: 152,
        endOffsetMm: 152,
      );
      final prefabCut = PrefabEngine.cutLengthMm(
        isoValueMm: 1200,
        ref: DimRef.centreToCentre,
        leftCteMm: 152,
        rightCteMm: 152,
      );

      expect(cut, 896);
      expect(prefabCut, 896);
    });

    test('kolano–kołnierz nie daje CUT przed potwierdzeniem referencji', () {
      final plan = planFromScan(_dn100Scan(
        schedule: 'Sch 40',
        components: [
          _component('e1', 'elbow90'),
          _component('f1', 'flange'),
        ],
        segments: [_segment('s1', 'e1', 'f1', 1000)],
      ));
      final segment = plan.segments.single;

      expect(segment.needsDimRefConfirmation, isTrue);
      expect(segment.cutMm, isNull);
      expect(plan.has(ScanIssueCode.dimensionReferenceUnknown), isTrue);
    });

    test('DN100 Sch40 daje OD 114.3 mm i ściankę 6.02 mm', () {
      final plan = planFromScan(_dn100Scan(schedule: 'Sch 40'));

      expect(plan.project.diameterMm, closeTo(114.3, 1e-9));
      expect(plan.project.wallThicknessMm, closeTo(6.02, 1e-9));
    });

    test('nieznany schedule pozostawia grubość pustą', () {
      final plan = planFromScan(_dn100Scan(schedule: '40S'));

      expect(plan.project.wallThicknessMm, isNull);
      expect(plan.has(ScanIssueCode.missingWallThickness), isTrue);
    });

    test('suma cięć i rzazów nie przekracza długości pręta', () {
      const stockLengthMm = 6000.0;
      const sawKerfMm = 3.0;
      final plans = nestCutsToBars(
        cutsMm: const [2400, 1800, 1200, 900],
        stockLengthMm: stockLengthMm,
        sawKerfMm: sawKerfMm,
      );

      for (final plan in plans) {
        final piecesLength =
            plan.piecesMm.fold<double>(0, (sum, piece) => sum + piece);
        final consumed = piecesLength + plan.cutsCount * sawKerfMm;
        expect(consumed, lessThanOrEqualTo(stockLengthMm + 1e-9));
        expect(plan.remainingMm, closeTo(stockLengthMm - consumed, 1e-9));
      }
    });

    test('saddle jest symetryczny, skończony i nieujemny', () {
      final template = SaddleTemplate(
        headerOdMm: 200,
        branchOdMm: 100,
        angleDeg: 45,
      );
      final last = template.points.length - 1;

      for (var i = 0; i < template.points.length; i++) {
        final depth = template.points[i].depthMm;
        expect(depth.isFinite, isTrue, reason: 'punkt $i');
        expect(depth, greaterThanOrEqualTo(0), reason: 'punkt $i');
        expect(
          depth,
          closeTo(template.points[last - i].depthMm, 1e-9),
          reason: 'symetria punktów $i i ${last - i}',
        );
      }
    });

    testWidgets('rolling offset 300/400 mm daje true offset 500 mm',
        (tester) async {
      await tester.pumpWidget(_app(const RollingOffsetScreen()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '300');
      await tester.enterText(fields.at(1), '400');
      await _calculate(tester);

      final trueOffset = tester.widget<TextField>(
        _textFieldWithLabel('True Offset = √(Rise²+Spread²)'),
      );
      expect(trueOffset.controller!.text, '500.0');
    });

    testWidgets('spadek 1% na 10 m daje 100 mm', (tester) async {
      await tester.pumpWidget(_app(const PipeSlopeScreen()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10000');
      await tester.enterText(fields.at(1), '1');
      await _calculate(tester);

      expect(_editableWithValue('100.0'), findsOneWidget);
    });
  });
}
