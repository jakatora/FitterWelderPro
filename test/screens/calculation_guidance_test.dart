import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pipe_slope_screen.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';

Widget app(Widget screen,
        {AppLanguage language = AppLanguage.pl,
        double scale = 1,
        Brightness brightness = Brightness.light}) =>
    AppLanguageScope(
      controller: AppLanguageController(language),
      child: MaterialApp(
        theme:
            ThemeData(colorSchemeSeed: Colors.orange, brightness: brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!),
        home: screen,
      ),
    );

Finder field(String label, {required bool readOnly}) =>
    find.byWidgetPredicate((w) =>
        w is TextField &&
        w.decoration?.labelText == label &&
        w.readOnly == readOnly);

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  final target = field(label, readOnly: false);
  expect(target, findsOneWidget, reason: '$label must be editable');
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

String result(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label, readOnly: true)).controller!.text;

void main() {
  testWidgets('rise-to-length accepts rise and computes the horizontal length',
      (tester) async {
    await tester.pumpWidget(app(const PipeSlopeScreen()));
    await tap(tester, find.text('Wznios → Długość'));
    await enter(tester, 'Wznios (Rise)', '100');
    await enter(tester, 'Nachylenie', '1');
    await tap(tester, find.text('OBLICZ'));
    expect(result(tester, 'Długość rury'), '10000.0');
  });

  testWidgets(
      'changing a slope input clears the old result and disables copying it',
      (tester) async {
    await tester.pumpWidget(app(const PipeSlopeScreen()));
    await enter(tester, 'Długość rury', '10000');
    await enter(tester, 'Nachylenie', '1');
    await tap(tester, find.text('OBLICZ'));
    expect(result(tester, 'Wznios (Rise)'), '100.0');
    await enter(tester, 'Nachylenie', '2');
    expect(result(tester, 'Wznios (Rise)'), isEmpty);
    final copy = find.descendant(
        of: field('Wznios (Rise)', readOnly: true),
        matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(copy).onPressed, isNull);
  });

  for (final bad in ['NaN', 'Infinity', '1e309', '-1', '0']) {
    testWidgets('slope rejects non-finite or non-positive length $bad',
        (tester) async {
      await tester.pumpWidget(app(const PipeSlopeScreen()));
      await enter(tester, 'Długość rury', bad);
      await enter(tester, 'Nachylenie', '1');
      await tap(tester, find.text('OBLICZ'));
      expect(result(tester, 'Wznios (Rise)'), isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  }

  testWidgets(
      'slope guide uses submitted values, then becomes an example after edits',
      (tester) async {
    await tester.pumpWidget(app(const PipeSlopeScreen()));
    await enter(tester, 'Długość rury', '10000');
    await enter(tester, 'Nachylenie', '1');
    await tap(tester, find.text('OBLICZ'));
    await tap(tester, find.text('Pokaż jak'));
    expect(find.textContaining('10000 × 1 / 100 = 100.0 mm'), findsOneWidget);
    await enter(tester, 'Nachylenie', '2');
    expect(find.textContaining('10000 × 1 / 100 = 100.0 mm'), findsNothing);
    expect(find.text('Przykład obliczenia'), findsOneWidget);
  });

  testWidgets(
      'slope percent mode accepts both inputs and changing mode clears computed outputs',
      (tester) async {
    await tester.pumpWidget(app(const PipeSlopeScreen()));
    await tap(tester, find.text('Wyznacz %'));
    await enter(tester, 'Długość rury', '10000');
    await enter(tester, 'Wznios (Rise)', '200');
    await tap(tester, find.text('OBLICZ'));
    expect(result(tester, 'Nachylenie'), '2.000');
    await tap(tester, find.text('Długość → Wznios'));
    expect(result(tester, 'Wznios (Rise)'), isEmpty);
    expect(result(tester, 'Kąt nachylenia'), isEmpty);
  });

  testWidgets(
      'rolling guide explains actual offset and does not retain it after input changes',
      (tester) async {
    await tester.pumpWidget(app(const RollingOffsetScreen()));
    await enter(tester, 'Rise (odchylenie pionowe)', '600');
    await enter(tester, 'Spread (odchylenie boczne)', '800');
    await tap(tester, find.text('OBLICZ'));
    await tap(tester, find.text('Pokaż jak'));
    expect(find.textContaining('√(600² + 800²) = 1000.0 mm'), findsOneWidget);
    expect(
        find.textContaining('1000.0 / sin(45°) = 1414.2 mm'), findsOneWidget);
    expect(find.textContaining('nie jest długością cięcia'), findsWidgets);
    await enter(tester, 'Rise (odchylenie pionowe)', '900');
    expect(find.textContaining('√(600² + 800²) = 1000.0 mm'), findsNothing);
    expect(find.text('Przykład obliczenia'), findsOneWidget);
    expect(result(tester, 'Travel = True Offset × Multiplier'), isEmpty);
  });

  for (final digits in [200, 310]) {
    testWidgets('rolling rejects overflow from $digits-digit dimensions',
        (tester) async {
      await tester.pumpWidget(app(const RollingOffsetScreen()));
      await enter(tester, 'Rise (odchylenie pionowe)', '9' * digits);
      await enter(tester, 'Spread (odchylenie boczne)', '400');
      await tap(tester, find.text('OBLICZ'));
      expect(result(tester, 'Travel = True Offset × Multiplier'), isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  }

  testWidgets('rolling English guide fits narrow display with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        app(const RollingOffsetScreen(), language: AppLanguage.en, scale: 1.8));
    await tap(tester, find.text('Show how'));
    await tester.ensureVisible(find.text('Worked example'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'English guide fits a narrow screen at 1.8 text scale in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(const PipeSlopeScreen(),
          language: AppLanguage.en, scale: 1.8, brightness: brightness));
      await tap(tester, find.text('Show how'));
      await tester.ensureVisible(find.text('Worked example'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('horizontal'), findsWidgets);
    });
  }
}
