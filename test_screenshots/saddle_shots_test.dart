// Real-screen previews, excluded from the default suite like store_shots_test.
// flutter test test_screenshots/saddle_shots_test.dart --update-goldens
// Optionally set --dart-define=SADDLE_PREVIEW_DIR=<output directory>.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/saddle_cut_screen.dart';
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

  testWidgets('saddle PL results and worked explanation', (tester) async {
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
          home: const SaddleCutScreen()),
    ));
    await tester.enterText(find.byType(TextField).at(0), '100');
    await tester.enterText(find.byType(TextField).at(1), '60');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oblicz profil'));
    await tester.pumpAndSettle();
    final destination = Directory(const String.fromEnvironment(
            'SADDLE_PREVIEW_DIR',
            defaultValue: 'test_screenshots/shots'))
        .absolute
        .uri;
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile(destination.resolve('saddle_result_pl.png')));
    await tester.ensureVisible(find.text('Pokaż jak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokaż jak'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Twoje obliczenie'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile(destination.resolve('saddle_guide_pl.png')));
    expect(tester.takeException(), isNull);
  });
}
