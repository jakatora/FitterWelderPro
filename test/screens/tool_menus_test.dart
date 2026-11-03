import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_menu_screen.dart';
import 'package:cut_list_app/screens/dn_mm_screen.dart';
import 'package:cut_list_app/screens/welder_menu_screen.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:cut_list_app/widgets/tool_tiles.dart';
import '../test_prefs.dart';

Future<void> pumpMenu(WidgetTester tester, Widget screen,
    {Size size = const Size(420, 4000),
    AppLanguage lang = AppLanguage.pl}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = AppLanguageController(lang);
  addTearDown(controller.dispose);
  await tester.pumpWidget(AppLanguageScope(
      controller: controller,
      child: MaterialApp(theme: buildAppTheme(), home: screen)));
  await tester.pumpAndSettle();
}

Future<void> openGroup(WidgetTester tester, ToolGroup group) async {
  final button = find.byKey(ValueKey('tool-group-${group.name}'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(seedFreshInstall);
  for (final (name, screen, section) in [
    ('monter', const FitterMenuScreen(), ToolSection.fitter),
    ('spawacz', const WelderMenuScreen(), ToolSection.welder),
  ]) {
    testWidgets('$name: grupy otwierają komplet właściwych narzędzi i powrót',
        (tester) async {
      await pumpMenu(tester, screen);
      expect(find.byType(ToolRow), findsNothing);
      for (final group in groupsOf(section)) {
        expect(
            find.byKey(ValueKey('tool-group-${group.name}')), findsOneWidget);
        await openGroup(tester, group);
        final tools = toolsInGroup(group);
        expect(find.byType(ToolRow), findsNWidgets(tools.length));
        for (final tool in tools) {
          final row = find.byKey(ValueKey('tool-row-${tool.id}'));
          expect(row, findsOneWidget, reason: tool.id);
          expect(tester.getSize(row).height, greaterThanOrEqualTo(56),
              reason: tool.id);
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ToolRow), findsNothing);
      }
    });
  }

  testWidgets('nazwy grup w języku angielskim', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(), lang: AppLanguage.en);
    expect(find.text('Elbows and fittings'), findsOneWidget);
    await openGroup(tester, ToolGroup.elbowsFittings);
    expect(find.text('Elbows and fittings'), findsOneWidget);
  });

  testWidgets('menu spawacza pokazuje grupy, a checklistę w grupie kontroli',
      (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    expect(find.text('SPRÓBUJ TEGO'), findsNothing);
    expect(find.byKey(const ValueKey('tool-row-pre_weld_checklist')), findsNothing);
    await openGroup(tester, ToolGroup.inspection);
    expect(find.byKey(const ValueKey('tool-row-pre_weld_checklist')), findsOneWidget);
  });

  testWidgets('zdjęcia grup mają źródło i licencję dostępne w aplikacji',
      (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    expect(find.byKey(const ValueKey('tool-group-photo-cutProjects')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-elbowsFittings')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-branches')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-routeSlope')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-tables')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-supportsFlanges')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tool-photo-credits')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ghasemimoshref'), findsOneWidget);
    expect(find.textContaining('Belle Tong'), findsOneWidget);
    expect(find.textContaining('Christopher.S.rcbc'), findsOneWidget);
    expect(find.textContaining('Alf van Beem'), findsOneWidget);
    expect(find.textContaining('Rhetos'), findsOneWidget);
    expect(find.textContaining('Merakistarsllp'), findsOneWidget);
    expect(find.textContaining('CC BY-SA 4.0'), findsOneWidget);
    expect(find.textContaining('CC0 1.0'), findsOneWidget);
    expect(find.textContaining('Martink'), findsOneWidget);
    expect(find.textContaining('https://creativecommons.org/licenses/by-sa/3.0/'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spawacz widzi zdjęcie i jego źródło', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen(), size: const Size(360, 740));
    expect(find.byKey(const ValueKey('tool-group-photo-weldParams')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-weldCalculators')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-inspection')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-stainlessFinish')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-photo-costing')), findsOneWidget);
    final credits = find.byKey(const Key('tool-photo-credits'));
    await tester.ensureVisible(credits);
    await tester.pumpAndSettle();
    await tester.tap(credits);
    await tester.pumpAndSettle();
    expect(find.textContaining('Christopher.S.rcbc'), findsOneWidget);
    expect(find.textContaining('PEO ACWA'), findsOneWidget);
    expect(find.textContaining('Jorge Franganillo'), findsOneWidget);
    expect(find.textContaining('Dithira Hettiarachchi'), findsOneWidget);
    expect(find.textContaining('Flattrackers and Caferacers'), findsOneWidget);
    expect(find.textContaining('Santeri Viinamäki'), findsOneWidget);
    expect(find.textContaining('Ruslan468'), findsOneWidget);
    expect(find.textContaining('SylvIba'), findsOneWidget);
    expect(find.textContaining('Newfoundlandguy'), findsOneWidget);
    expect(find.textContaining('Rm at Dutch Wikipedia'), findsOneWidget);
    expect(find.textContaining('RomanM82'), findsOneWidget);
    expect(find.textContaining('Samuel R. Beyers'), findsOneWidget);
    expect(find.textContaining('Smigler'), findsOneWidget);
    expect(find.textContaining('Taylor 49'), findsOneWidget);
    expect(find.textContaining('File:Narrow_clearance_tools.jpg'), findsOneWidget);
    expect(find.textContaining('https://creativecommons.org/licenses/by/3.0/'), findsOneWidget);
    expect(find.textContaining('https://creativecommons.org/licenses/by-sa/4.0/'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('na wąskim ekranie można przewinąć zdjęcia i otworzyć ostatnią grupę', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(), size: const Size(320, 640));
    await openGroup(tester, ToolGroup.supportsFlanges);
    expect(find.byType(ToolRow), findsNWidgets(toolsInGroup(ToolGroup.supportsFlanges).length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('zdjęcia konkretnych narzędzi, ikona dla pozostałych i źródło', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(), size: const Size(320, 720));
    await openGroup(tester, ToolGroup.cutProjects);
    expect(find.byKey(const ValueKey('tool-photo-cut_list')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-photo-iso_notebook')), findsNothing);
    expect(find.byKey(const ValueKey('tool-row-iso_notebook')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Lista cięć')).dx,
        tester.getTopLeft(find.text('Zeszyt ISO')).dx);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final credits = find.byKey(const Key('tool-photo-credits'));
    await tester.ensureVisible(credits);
    await tester.tap(credits);
    await tester.pumpAndSettle();
    expect(find.textContaining('TECNIC Bioprocess Solutions'), findsOneWidget);
    expect(find.textContaining('https://unsplash.com/photos/a-man-operates-industrial-machinery-in-a-workshop-ZJzv93F6F1U'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zdjęcia są przypisane właściwym narzędziom w grupach', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    for (final (group, tool) in [
      (ToolGroup.elbowsFittings, 'elbow_takeouts'),
      (ToolGroup.elbowsFittings, 'reducer'),
      (ToolGroup.elbowsFittings, 'mitre_bend'),
      (ToolGroup.elbowsFittings, 'tube_bending'),
      (ToolGroup.routeSlope, 'pipe_slope'),
      (ToolGroup.routeSlope, 'slope_cut'),
      (ToolGroup.routeSlope, 'thermal_expansion'),
      (ToolGroup.routeSlope, 'pipe_route'),
      (ToolGroup.tables, 'dn_mm'),
      (ToolGroup.supportsFlanges, 'flange_check'),
      (ToolGroup.supportsFlanges, 'bolt_torque'),
      (ToolGroup.supportsFlanges, 'bolt_kit'),
    ]) {
      await openGroup(tester, group);
      final row = find.byKey(ValueKey('tool-row-$tool'));
      final photo = find.descendant(of: row, matching: find.byKey(ValueKey('tool-photo-$tool')));
      expect(photo, findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('zdjęcie narzędzia widać również w skrócie na ekranie głównym',
      (tester) async {
    await pumpMenu(
      tester,
      Scaffold(body: ToolCompactTile(tool: toolById('mitre_bend')!)),
      size: const Size(320, 640),
    );
    expect(find.byKey(const ValueKey('tool-tile-photo-mitre_bend')),
        findsOneWidget);
    expect(find.text('Segmentowe kolana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan badań spoin ma zdjęcie kontroli', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.inspection);
    final row = find.byKey(const ValueKey('tool-row-ndt_plan'));
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('tool-photo-ndt_plan'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarcze i szlifierki mają zdjęcie narzędzia', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.inspection);
    final row = find.byKey(const ValueKey('tool-row-grinding'));
    await tester.ensureVisible(row);
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('tool-photo-grinding'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zawiesia mają zdjęcie w grupie kontroli i dokumentacji', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.inspection);
    final row = find.byKey(const ValueKey('tool-row-rigging'));
    await tester.ensureVisible(row);
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('tool-photo-rigging'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtr przyłbicy ma zdjęcie w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-photo-shade')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spawanie orbitalne ma zdjęcie głowicy w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-photo-orbital_tig')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dobór spoiwa ma zdjęcie elektrod w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-photo-filler_selector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('elektroda wolframowa ma zdjęcie w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-photo-tungsten')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('podpory rur mają zdjęcie w swojej grupie', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    await openGroup(tester, ToolGroup.supportsFlanges);
    expect(find.byKey(const ValueKey('tool-photo-pipe_supports')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skrót filtra przyłbicy pokazuje to samo zdjęcie', (tester) async {
    await pumpMenu(tester,
        Scaffold(body: ToolCompactTile(tool: toolById('shade')!)),
        size: const Size(320, 640));
    expect(find.byKey(const ValueKey('tool-tile-photo-shade')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('długie nazwy i duży tekst mieszczą się przy zdjęciu', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppLanguageController(AppLanguage.pl);
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppLanguageScope(
      controller: controller,
      child: MaterialApp(theme: buildAppTheme(), home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 700), textScaler: TextScaler.linear(1.6)),
        child: const FitterMenuScreen(),
      )),
    ));
    await tester.pumpAndSettle();
    await openGroup(tester, ToolGroup.cutProjects);
    expect(find.byKey(const ValueKey('tool-photo-cut_list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('przytrzymanie narzędzia w grupie przypina je', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    await openGroup(tester, ToolGroup.tables);
    final row = find.byKey(const ValueKey('tool-row-dn_mm'));
    await tester.ensureVisible(row);
    await tester.longPress(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: row, matching: find.byIcon(Icons.push_pin)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('otwarcie narzędzia i powrót do właściwej grupy', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(), size: const Size(360, 740));
    await openGroup(tester, ToolGroup.tables);
    final row = find.byKey(const ValueKey('tool-row-dn_mm'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(DnMmScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool-row-dn_mm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet: narzędzia w grupie są w dwóch kolumnach',
      (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(),
        size: const Size(1200, 3000));
    await openGroup(tester, ToolGroup.cutProjects);
    final a =
        tester.getTopLeft(find.byKey(const ValueKey('tool-row-cut_list')));
    final b =
        tester.getTopLeft(find.byKey(const ValueKey('tool-row-iso_notebook')));
    expect(a.dy, b.dy);
    expect(b.dx, greaterThan(a.dx));
  });
}
