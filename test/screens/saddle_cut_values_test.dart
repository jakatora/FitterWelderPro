// Niezależnie wyliczone wartości dla scenariusza audytu saddle-cut:
// odgałęzienie OD 60 mm na rurze głównej OD 114 mm, połączenie centralne 90°.
//
// R = 57, r = 30, sqrt(R^2 - r^2) = sqrt(2349) = 48.4664833
// d(a) = sqrt(3249 - 900 sin^2 a) - 48.4664833
//   0 deg -> 8.5335167   (h_max)
//  15 deg -> 8.0021933
//  30 deg -> 6.5244247   (sqrt(3024) = 54.9909083)
//  45 deg -> 4.4390937   (sqrt(2799) = 52.9055767)
//  60 deg -> 2.2681207   (sqrt(2574) = 50.7346040)
//  75 deg -> 0.6180217   (sqrt(2409.2886) = 49.0845050)
//  90 deg -> 0
// Obwód = pi * 60 = 188.4955592, krok 15 deg = 7.8539816 mm.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/saddle_cut_screen.dart';
import 'package:cut_list_app/services/saddle_geometry.dart';
import 'package:cut_list_app/utils/clipboard_helper.dart';

const _expectedDepths = <double>[
  8.5335167,
  8.0021933,
  6.5244247,
  4.4390937,
  2.2681207,
  0.6180217,
  0.0,
];

Widget _app() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.orange),
        home: const SaddleCutScreen(),
      ),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _calculate(
    WidgetTester tester, String header, String branch) async {
  await tester.enterText(find.byType(TextField).at(0), header);
  await tester.enterText(find.byType(TextField).at(1), branch);
  await _tap(tester, find.byWidgetPredicate((w) => w is FilledButton));
}

Finder get _result =>
    find.byWidgetPredicate((w) => w is CopyOnLongPress && w.label == 'h_max');

IconButton _copy(WidgetTester tester) => tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.copy_all_outlined));

String _cellText(TableRow row, int column) =>
    ((row.children[column] as Padding).child! as Text).data!;

void main() {
  group('SaddleGeometry 114/60', () {
    final geometry =
        SaddleGeometry(headerOdMm: 114, branchOdMm: 60, angleDeg: 90);

    test('h_max równe 57 - sqrt(2349)', () {
      expect(geometry.maxDepthMm, closeTo(8.5335167, 1e-3));
      expect(geometry.stripLengthMm, closeTo(188.4955592, 1e-3));
    });

    test('głębokości co 15 stopni zgadzają się z ręcznym wyliczeniem', () {
      for (var i = 0; i < _expectedDepths.length; i++) {
        final point = geometry.pointAt(i * 15.0);
        expect(point.depthMm, closeTo(_expectedDepths[i], 1e-3),
            reason: 'kąt ${i * 15}°');
        expect(point.xMm, closeTo(7.8539816 * i, 1e-3),
            reason: 'łuk ${i * 15}°');
      }
    });

    test('profil jest symetryczny względem 90 i 180 stopni', () {
      for (var deg = 0; deg <= 90; deg += 15) {
        final base = geometry.pointAt(deg.toDouble()).depthMm;
        expect(geometry.pointAt(180.0 - deg).depthMm, closeTo(base, 1e-9));
        expect(geometry.pointAt(180.0 + deg).depthMm, closeTo(base, 1e-9));
      }
    });

    test('odgałęzienie większe od rury głównej jest odrzucane', () {
      expect(
          () => SaddleGeometry(
              headerOdMm: 114, branchOdMm: 114.1, angleDeg: 90),
          throwsArgumentError);
    });
  });

  testWidgets('ekran 114/60 pokazuje h_max 8.5 i tabelę 0–90°',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '114', '60');

    expect(tester.widget<CopyOnLongPress>(_result).value, '8.5');
    expect(find.text('8.5 mm'), findsOneWidget);

    final table = tester.widget<Table>(find.byType(Table).first);
    expect(table.children, hasLength(8));
    final rows = table.children.skip(1).toList();
    expect(rows.map((r) => _cellText(r, 0)).toList(),
        ['0°', '15°', '30°', '45°', '60°', '75°', '90°']);
    expect(rows.map((r) => _cellText(r, 1)).toList(),
        ['0.0', '7.9', '15.7', '23.6', '31.4', '39.3', '47.1']);
    expect(rows.map((r) => _cellText(r, 2)).toList(),
        ['8.5', '8.0', '6.5', '4.4', '2.3', '0.6', '0.0']);
    expect(_copy(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skopiowany profil 114/60 ma pełny obwód z poprawnymi wartościami',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(_app());
    await _calculate(tester, '114', '60');
    await _tap(
        tester, find.widgetWithIcon(IconButton, Icons.copy_all_outlined));

    expect(copied, isNotNull);
    expect(copied, contains('OD rury głównej: 114 mm'));
    expect(copied, contains('OD odgałęzienia: 60 mm'));
    expect(copied, contains('h_max: 8.5 mm'));
    final rows = copied!
        .split('\n')
        .where((line) => RegExp(r'^\d+°\t').hasMatch(line))
        .toList();
    expect(rows, hasLength(25));
    expect(rows[0], '0°\t0.0\t8.5');
    expect(rows[3], '45°\t23.6\t4.4');
    expect(rows[6], '90°\t47.1\t0.0');
    expect(rows[12], '180°\t94.2\t8.5');
    expect(rows[18], '270°\t141.4\t0.0');
    expect(rows[24], '360°\t188.5\t8.5');
    for (var i = 0; i <= 6; i++) {
      final depth = rows[i].split('\t').last;
      expect(rows[12 - i].split('\t').last, depth);
      expect(rows[12 + i].split('\t').last, depth);
    }
  });

  for (final branch in ['114,1', '115']) {
    testWidgets('odgałęzienie $branch na rurze 114 nie daje wyniku',
        (tester) async {
      await tester.pumpWidget(_app());
      await _calculate(tester, '114', branch);
      expect(_result, findsNothing);
      expect(_copy(tester).onPressed, isNull);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .decoration!
              .errorText,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
