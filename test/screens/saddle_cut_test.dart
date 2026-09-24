import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/saddle_cut_screen.dart';
import 'package:cut_list_app/utils/clipboard_helper.dart';

Widget _app(
        {AppLanguage language = AppLanguage.pl,
        double scale = 1,
        Brightness brightness = Brightness.light}) =>
    AppLanguageScope(
      controller: AppLanguageController(language),
      child: MaterialApp(
        theme:
            ThemeData(colorSchemeSeed: Colors.orange, brightness: brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
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

void main() {
  testWidgets(
      '45 degree axial cutback meets the header surface, not its complement',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '100', '60');
    // Body is +z; longest tips lie at z=40. At 45 degrees the
    // intersection is z=sqrt(2050)=45.27692569, hence cutback=5.27692569.
    // R - sqrt(2050)=4.72307431 measures the opposite reference.
    final table = tester.widget<Table>(find.byType(Table).first);
    final depth = (table.children[4].children[2] as Padding).child! as Text;
    expect(depth.data, '5.3');
  });

  testWidgets('100/60 reference has 10 mm maximum depth', (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '100', '60');
    expect(tester.widget<CopyOnLongPress>(_result).value, '10.0');
  });

  for (final index in [0, 1]) {
    testWidgets('editing diameter $index clears result and disables copy',
        (tester) async {
      await tester.pumpWidget(_app());
      await _calculate(tester, '100', '60');
      expect(_copy(tester).onPressed, isNotNull);
      await tester.enterText(
          find.byType(TextField).at(index), index == 0 ? '200' : '50');
      await tester.pumpAndSettle();
      expect(_result, findsNothing);
      expect(_copy(tester).onPressed, isNull);
    });
  }

  testWidgets('programmatic input change cannot export a stale profile',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '100', '60');
    tester.widget<TextField>(find.byType(TextField).first).controller!.text =
        '200';
    await tester.pumpAndSettle();
    expect(_copy(tester).onPressed, isNull);
  });

  for (final index in [0, 1]) {
    for (final value in [
      'NaN',
      'Infinity',
      '1e309',
      '0',
      '-1',
      '2000.1',
      'abc',
      ''
    ]) {
      testWidgets('diameter $index rejects ${value.isEmpty ? 'empty' : value}',
          (tester) async {
        await tester.pumpWidget(_app());
        await _calculate(
            tester, index == 0 ? value : '2000', index == 1 ? value : '60');
        expect(_result, findsNothing);
        expect(_copy(tester).onPressed, isNull);
        expect(
            tester
                .widget<TextField>(find.byType(TextField).at(index))
                .decoration!
                .errorText,
            isNotNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final branch in ['101']) {
    testWidgets('branch $branch cannot exceed header 100', (tester) async {
      await tester.pumpWidget(_app());
      await _calculate(tester, '100', branch);
      expect(_result, findsNothing);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .decoration!
              .errorText,
          isNotNull);
    });
  }

  testWidgets('equal pipe ODs use the same valid geometry as the PDF template',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '100', '100');
    expect(tester.widget<CopyOnLongPress>(_result).value, '50.0');
    expect(_copy(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2000 mm inclusive limit and decimal comma are accepted',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '2000,0', '1200,0');
    expect(tester.widget<CopyOnLongPress>(_result).value, '200.0');
    expect(_copy(tester).onPressed, isNotNull);
  });

  testWidgets('copy contains full circumference and correct depth orientation',
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
    await _calculate(tester, '100', '60');
    await _tap(
        tester, find.widgetWithIcon(IconButton, Icons.copy_all_outlined));
    expect(copied, contains('OD rury głównej: 100 mm'));
    expect(copied, contains('OD odgałęzienia: 60 mm'));
    final rows = copied!
        .split('\n')
        .where((line) => RegExp(r'^\d+°\t').hasMatch(line))
        .toList();
    expect(rows, hasLength(25));
    expect(rows.first, '0°\t0.0\t10.0');
    expect(rows[6], '90°\t47.1\t0.0');
    expect(rows[12], '180°\t94.2\t10.0');
    expect(rows[18], '270°\t141.4\t0.0');
    expect(rows.last, '360°\t188.5\t10.0');
    expect(rows.take(7).map((row) => row.split('\t').last).toList(),
        ['10.0', '9.4', '7.7', '5.3', '2.7', '0.7', '0.0']);
    for (var i = 0; i <= 6; i++) {
      expect(rows[i].split('\t').last, rows[12 - i].split('\t').last);
      expect(rows[i].split('\t').last, rows[12 + i].split('\t').last);
    }
    expect(copied, contains('90°'));
    expect(copied, contains('Bez uwzględnienia grubości ścianki'));
  });

  testWidgets(
      'guide switches between a current calculation and a labelled example',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '200', '120');
    await _tap(tester, find.text('Pokaż jak'));
    expect(find.text('Twoje obliczenie'), findsOneWidget);
    expect(
        find.textContaining('100 − √(100² − 60²) = 20.0 mm'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '300');
    await tester.pumpAndSettle();
    expect(find.text('Przykład obliczenia'), findsOneWidget);
    expect(find.textContaining('50 − √(50² − 30²) = 10.0 mm'), findsOneWidget);
  });

  testWidgets('full profile is optional and includes closing point',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '100', '60');
    expect(find.text('360°'), findsNothing);
    await _tap(tester, find.text('Pełny obwód 0–360°'));
    expect(find.text('360°'), findsOneWidget);
    expect(find.text('188.5'), findsOneWidget);
  });

  testWidgets('moving the cursor preserves the current result', (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '100', '60');
    tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!
        .selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    expect(_result, findsOneWidget);
    expect(_copy(tester).onPressed, isNotNull);
  });

  testWidgets('200/100 reference has 13.4 max and 6.9 at 45 degrees',
      (tester) async {
    await tester.pumpWidget(_app());
    await _calculate(tester, '200', '100');
    expect(tester.widget<CopyOnLongPress>(_result).value, '13.4');
    final table = tester.widget<Table>(find.byType(Table).first);
    final depth = (table.children[4].children[2] as Padding).child! as Text;
    // sqrt(8750) - sqrt(7500) = 6.938894291.
    expect(depth.data, '6.9');
  });

  testWidgets(
      'landscape large text can calculate, expand help and correct invalid input',
      (tester) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(scale: 2));
    await _calculate(tester, '100', '60');
    await _tap(tester, find.text('Pokaż jak'));
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'NaN');
    await _tap(tester, find.text('Oblicz profil'));
    expect(_copy(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final language in AppLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '$language $brightness narrow large-text results and guide do not overflow',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            _app(language: language, scale: 2, brightness: brightness));
        await _calculate(tester, '100', '60');
        await _tap(
            tester,
            find.text(language == AppLanguage.pl
                ? 'Pełny obwód 0–360°'
                : 'Full circumference 0–360°'));
        await _tap(tester,
            find.text(language == AppLanguage.pl ? 'Pokaż jak' : 'Show how'));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(TextField).first);
        await tester.enterText(find.byType(TextField).first, 'NaN');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
