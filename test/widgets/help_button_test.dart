import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/help_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets(
        'help has a visible close action on narrow screens: ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(language),
        child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              appBar: AppBar(actions: const [
                HelpButton(
                    help: ScreenHelp(
                  titlePl: 'Pomoc dla listy projektów',
                  titleEn: 'Project list help',
                  bodyPl: 'Opis działania modułu.',
                  bodyEn: 'How the module works.',
                ))
              ]),
              body: const Text('Module remains open'),
            )),
      ));
      await tester
          .tap(find.byTooltip(language == AppLanguage.pl ? 'Pomoc' : 'Help'));
      await tester.pumpAndSettle();
      final title = language == AppLanguage.pl
          ? 'Pomoc dla listy projektów'
          : 'Project list help';
      expect(find.text(title), findsOneWidget);
      final close = find.byTooltip(
          language == AppLanguage.pl ? 'Zamknij pomoc' : 'Close help');
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
      expect(find.text('Module remains open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
