// Real-screen previews, excluded from the default suite like store_shots_test.
// flutter test test_screenshots/converter_shots_test.dart --update-goldens
// Optionally set --dart-define=CONVERTER_PREVIEW_DIR=<output directory>.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/quick_converter_screen.dart';
import 'package:cut_list_app/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest =
        json.decode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    for (final family in ['Roboto', '']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
          .load();
    }
  });

  testWidgets('converter PL results and worked explanation', (tester) async {
    tester.view.physicalSize = const Size(1125, 2436);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final theme = buildAppTheme();
    // AppBar's standalone TextStyle otherwise falls back to the test Ahem font.
    final previewTheme = theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle:
          theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ));
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme,
          home: const QuickConverterScreen()),
    ));
    await tester.enterText(find.byType(TextField), '25,4');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final destination = Directory(const String.fromEnvironment(
            'CONVERTER_PREVIEW_DIR',
            defaultValue: 'test_screenshots/shots'))
        .absolute
        .uri;
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile(destination.resolve('converter_length_pl.png')));
    await tester.ensureVisible(find.text('Pokaż jak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokaż jak'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('DN jest oznaczeniem'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile(destination.resolve('converter_guide_pl.png')));
    expect(tester.takeException(), isNull);
  });
}
