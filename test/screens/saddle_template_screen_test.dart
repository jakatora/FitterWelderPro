import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/saddle_template_screen.dart';

Widget app({AppLanguage language = AppLanguage.pl, double scale = 1}) =>
    AppLanguageScope(
        controller: AppLanguageController(language),
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const SaddleTemplateScreen()));
Finder get export => find.byWidgetPredicate((w) => w is FilledButton);
Finder get listScroll => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;
Future<void> showExport(WidgetTester tester) async {
  await tester.scrollUntilVisible(export, 250, scrollable: listScroll);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'programmatic invalid diameter cannot leave an exportable old template',
      (tester) async {
    await tester.pumpWidget(app());
    final field = tester.widget<TextField>(find.byType(TextField).first);
    await showExport(tester);
    expect(tester.widget<FilledButton>(export).onPressed, isNotNull);
    field.controller!.text = 'NaN';
    await tester.pumpAndSettle();
    expect(export, findsNothing);
  });
  testWidgets('out-of-range diameter blocks template and export',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField).first, '2001');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('2000'), 200,
        scrollable: listScroll);
    await tester.pumpAndSettle();
    expect(export, findsNothing);
    expect(find.textContaining('2000'), findsOneWidget);
  });
  testWidgets('large profile keeps preview but disables oversized PDF',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField).at(0), '2000');
    await tester.enterText(find.byType(TextField).at(1), '2000');
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(15);
    await tester.pumpAndSettle();
    await showExport(tester);
    expect(tester.widget<FilledButton>(export).onPressed, isNull);
    expect(find.textContaining('100 kartek'), findsOneWidget);
  });
  for (final language in AppLanguage.values) {
    testWidgets('small phone with large text remains usable in $language',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(language: language, scale: 2));
      await showExport(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
