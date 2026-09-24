import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/saddle_template_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    for (final family in ['Roboto', '', 'Ahem']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
          .load();
    }
  });
  testWidgets('template small-phone input and export previews', (tester) async {
    tester.view.physicalSize = const Size(1125, 2436);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
                appBarTheme: const AppBarTheme(
                    titleTextStyle:
                        TextStyle(fontFamily: 'Roboto', fontSize: 20))),
            home: const SaddleTemplateScreen())));
    await tester.pumpAndSettle();
    final destination = Directory(const String.fromEnvironment(
            'SADDLE_TEMPLATE_PREVIEW_DIR',
            defaultValue: 'test_screenshots/shots'))
        .absolute
        .uri;
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile(destination.resolve('template-input.png')));
    await tester.scrollUntilVisible(
        find.byWidgetPredicate((w) => w is FilledButton), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile(destination.resolve('template-export.png')));
    expect(tester.takeException(), isNull);
  });
}
