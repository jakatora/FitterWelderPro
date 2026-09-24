// Menu montera i spawacza: zwarta, pogrupowana lista z rejestru narzędzi.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_menu_screen.dart';
import 'package:cut_list_app/screens/welder_menu_screen.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:cut_list_app/widgets/tool_tiles.dart';

import '../test_prefs.dart';

Future<void> _pump(WidgetTester tester, Widget screen,
    {Size size = const Size(420, 4000),
    AppLanguage lang = AppLanguage.pl}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = AppLanguageController(lang);
  addTearDown(controller.dispose);
  await tester.pumpWidget(AppLanguageScope(
    controller: controller,
    child: MaterialApp(theme: buildAppTheme(), home: screen),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(seedFreshInstall);

  for (final (name, screen, section) in [
    ('monter', const FitterMenuScreen(), ToolSection.fitter),
    ('spawacz', const WelderMenuScreen(), ToolSection.welder),
  ]) {
    testWidgets('$name: każde narzędzie z sekcji jest w menu, wiersz ≥ 56 dp',
        (tester) async {
      await _pump(tester, screen);
      final tools = [for (final g in groupsOf(section)) ...toolsInGroup(g)];
      expect(find.byType(ToolRow), findsNWidgets(tools.length));
      for (final t in tools) {
        final row = find.byKey(ValueKey('tool-row-${t.id}'));
        expect(row, findsOneWidget, reason: t.id);
        expect(tester.getSize(row).height, greaterThanOrEqualTo(56),
            reason: t.id);
      }
    });

    testWidgets('$name: nagłówki grup w kolejności z rejestru', (tester) async {
      await _pump(tester, screen);
      double? lastY;
      for (final g in groupsOf(section)) {
        final header = find.text(g.titlePl.toUpperCase());
        expect(header, findsOneWidget, reason: g.name);
        final y = tester.getTopLeft(header).dy;
        if (lastY != null) expect(y, greaterThan(lastY));
        lastY = y;
      }
    });
  }

  testWidgets('monter: „Wymiary kolan" w drugiej grupie, nie na 15. miejscu',
      (tester) async {
    await _pump(tester, const FitterMenuScreen());
    final rows = find.byType(ToolRow);
    final ys = [
      for (var i = 0; i < rows.evaluate().length; i++)
        tester.getTopLeft(rows.at(i)).dy,
    ]..sort();
    final takeout =
        tester.getTopLeft(find.byKey(const ValueKey('tool-row-elbow_takeouts')));
    expect(ys.indexOf(takeout.dy), lessThan(8));
  });

  testWidgets('monter: nazwy odróżniają spadki i siodła', (tester) async {
    await _pump(tester, const FitterMenuScreen());
    expect(find.text('Spadek rury'), findsOneWidget);
    expect(find.text('Cięcie pod spadek'), findsOneWidget);
    expect(find.text('Siodło 90° — tabela'), findsOneWidget);
    expect(find.text('Szablon siodła do druku'), findsOneWidget);
    // Dawne duplikaty zniknęły.
    expect(find.text('Saddle Cut'), findsNothing);
    expect(find.text('Saddle / Coping'), findsNothing);
    expect(find.text('Spadek'), findsNothing);
    // Zakładki bez dawnego kafla są w menu.
    expect(find.text('Ciężar rury'), findsOneWidget);
    expect(find.text('Fazowanie'), findsOneWidget);
    expect(find.text('Dylatacja'), findsOneWidget);
  });

  testWidgets('spawacz: heat input ma jedno wejście', (tester) async {
    await _pump(tester, const WelderMenuScreen());
    expect(find.textContaining('Heat input'), findsOneWidget);
    expect(find.textContaining('Heat Input'), findsNothing);
  });

  testWidgets('tytuły: MONTER w PL, FITTER w EN', (tester) async {
    await _pump(tester, const FitterMenuScreen());
    expect(find.text('Monter'), findsOneWidget);
    await _pump(tester, const FitterMenuScreen(), lang: AppLanguage.en);
    expect(find.text('Fitter'), findsOneWidget);
    await _pump(tester, const WelderMenuScreen(), lang: AppLanguage.en);
    expect(find.text('Welder'), findsOneWidget);
  });

  testWidgets('długie przytrzymanie w menu przypina (pinezka przy wierszu)',
      (tester) async {
    await _pump(tester, const FitterMenuScreen());
    expect(find.byIcon(Icons.push_pin), findsNothing);
    await tester.longPress(find.byKey(const ValueKey('tool-row-dn_mm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tool-row-dn_mm')),
        matching: find.byIcon(Icons.push_pin),
      ),
      findsOneWidget,
    );
    // Domknij SnackBar.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tablet: wiersze w dwóch kolumnach', (tester) async {
    await _pump(tester, const FitterMenuScreen(), size: const Size(1200, 3000));
    final a = tester.getTopLeft(find.byKey(const ValueKey('tool-row-cut_list')));
    final b =
        tester.getTopLeft(find.byKey(const ValueKey('tool-row-iso_notebook')));
    expect(a.dy, b.dy);
    expect(b.dx, greaterThan(a.dx));
  });
}
