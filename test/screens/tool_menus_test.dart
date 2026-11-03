import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_menu_screen.dart';
import 'package:cut_list_app/screens/dn_mm_screen.dart';
import 'package:cut_list_app/screens/welder_menu_screen.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:cut_list_app/widgets/tool_tiles.dart';
import 'package:cut_list_app/widgets/industrial_artwork.dart';
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

  testWidgets('każda grupa montera ma grafikę bez fotografii',
      (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    expect(find.byKey(const ValueKey('tool-group-artwork-cutProjects')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-elbowsFittings')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-branches')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-routeSlope')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-tables')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-supportsFlanges')), findsOneWidget);
    expect(find.byKey(const Key('tool-photo-credits')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('każda grupa spawacza ma grafikę bez fotografii', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen(), size: const Size(360, 740));
    expect(find.byKey(const ValueKey('tool-group-artwork-weldParams')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-weldCalculators')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-inspection')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-stainlessFinish')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-group-artwork-costing')), findsOneWidget);
    expect(find.byKey(const Key('tool-photo-credits')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('na wąskim ekranie można przewinąć grafiki i otworzyć ostatnią grupę', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(), size: const Size(320, 640));
    await openGroup(tester, ToolGroup.supportsFlanges);
    expect(find.byType(ToolRow), findsNWidgets(toolsInGroup(ToolGroup.supportsFlanges).length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('grafiki narzędzi są wyrównane', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen(), size: const Size(320, 720));
    await openGroup(tester, ToolGroup.cutProjects);
    expect(find.byKey(const ValueKey('tool-artwork-cut_list')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-artwork-iso_notebook')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-row-iso_notebook')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Lista cięć')).dx,
        tester.getTopLeft(find.text('Zeszyt ISO')).dx);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grafiki są przypisane właściwym narzędziom w grupach', (tester) async {
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
      final photo = find.descendant(of: row, matching: find.byKey(ValueKey('tool-artwork-$tool')));
      expect(photo, findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('narzędzia kolan mają odrębne grafiki odpowiadające zadaniom', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    await openGroup(tester, ToolGroup.elbowsFittings);
    for (final (id, kind) in [
      ('elbow_takeouts', IndustrialArtworkKind.elbowMeasure),
      ('elbow_cut', IndustrialArtworkKind.elbowCut),
      ('elbow_rotation', IndustrialArtworkKind.elbowRotate),
      ('insert', IndustrialArtworkKind.insert),
      ('reducer', IndustrialArtworkKind.reducer),
      ('mitre_bend', IndustrialArtworkKind.mitre),
      ('tube_bending', IndustrialArtworkKind.bender),
      ('cone_layout', IndustrialArtworkKind.cone),
    ]) {
      final finder = find.byKey(ValueKey('tool-artwork-$id'));
      expect(finder, findsOneWidget);
      expect(tester.widget<IndustrialArtwork>(finder).kind, kind, reason: id);
    }
  });

  testWidgets('odgałęzienia i trasy mają grafiki dopasowane do narzędzi', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    for (final (group, expected) in [
      (ToolGroup.branches, {
        'saddle_cut': IndustrialArtworkKind.saddle,
        'saddle_template': IndustrialArtworkKind.saddleTemplate,
      }),
      (ToolGroup.routeSlope, {
        'pipe_route': IndustrialArtworkKind.route,
        'rolling_offset': IndustrialArtworkKind.rollingOffset,
        'pipe_slope': IndustrialArtworkKind.pipeSlope,
        'slope_cut': IndustrialArtworkKind.slopeCut,
        'thermal_expansion': IndustrialArtworkKind.expansion,
      }),
    ]) {
      await openGroup(tester, group);
      for (final entry in expected.entries) {
        final finder = find.byKey(ValueKey('tool-artwork-${entry.key}'));
        expect(finder, findsOneWidget);
        expect(tester.widget<IndustrialArtwork>(finder).kind, entry.value);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('tabele, podpory i kołnierze mają grafiki dopasowane do zadań', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    for (final (group, expected) in [
      (ToolGroup.tables, {
        'dn_mm': IndustrialArtworkKind.pipeDiameter,
        'wall_thickness': IndustrialArtworkKind.pipeWall,
        'pipe_weight': IndustrialArtworkKind.pipeWeight,
        'steel_weight': IndustrialArtworkKind.steelProfiles,
        'sanitary_tube': IndustrialArtworkKind.sanitaryPipe,
        'unit_converter': IndustrialArtworkKind.unitConversion,
        'glossary': IndustrialArtworkKind.dictionary,
      }),
      (ToolGroup.supportsFlanges, {
        'pipe_supports': IndustrialArtworkKind.pipeSupport,
        'bolt_torque': IndustrialArtworkKind.torque,
        'flange_check': IndustrialArtworkKind.flangeCheck,
        'bolt_kit': IndustrialArtworkKind.boltKit,
      }),
    ]) {
      await openGroup(tester, group);
      for (final entry in expected.entries) {
        final finder = find.byKey(ValueKey('tool-artwork-${entry.key}'));
        expect(finder, findsOneWidget);
        expect(tester.widget<IndustrialArtwork>(finder).kind, entry.value);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('grafikę narzędzia widać również w skrócie na ekranie głównym',
      (tester) async {
    await pumpMenu(
      tester,
      Scaffold(body: ToolCompactTile(tool: toolById('mitre_bend')!)),
      size: const Size(320, 640),
    );
    expect(find.byKey(const ValueKey('tool-tile-artwork-mitre_bend')),
        findsOneWidget);
    expect(find.text('Segmentowe kolana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan badań spoin ma grafikę kontroli', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.inspection);
    final row = find.byKey(const ValueKey('tool-row-ndt_plan'));
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('tool-artwork-ndt_plan'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarcze i szlifierki mają grafikę narzędzia', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.inspection);
    final row = find.byKey(const ValueKey('tool-row-grinding'));
    await tester.ensureVisible(row);
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('tool-artwork-grinding'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zawiesia mają grafikę w grupie kontroli i dokumentacji', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.inspection);
    final row = find.byKey(const ValueKey('tool-row-rigging'));
    await tester.ensureVisible(row);
    expect(find.descendant(of: row, matching: find.byKey(const ValueKey('tool-artwork-rigging'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtr przyłbicy ma grafikę w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-artwork-shade')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narzędzia parametrów mają grafiki odpowiadające ich tematom', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    for (final (tool, expected) in [
      ('welder_tanks', IndustrialArtworkKind.tank),
      ('orbital_tig', IndustrialArtworkKind.orbital),
      ('shade', IndustrialArtworkKind.helmet),
      ('tungsten', IndustrialArtworkKind.electrode),
      ('filler_selector', IndustrialArtworkKind.filler),
      ('assistant', IndustrialArtworkKind.assistant),
    ]) {
      final finder = find.byKey(ValueKey('tool-artwork-$tool'));
      expect(finder, findsOneWidget);
      expect(tester.widget<IndustrialArtwork>(finder).kind, expected, reason: tool);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('kalkulatory spawalnicze mają rozróżnialne ilustracje', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldCalculators);
    for (final (tool, expected) in [
      ('heat_input', IndustrialArtworkKind.weldHeat),
      ('welder_calculators', IndustrialArtworkKind.gasTimer),
      ('pwht_planner', IndustrialArtworkKind.heatTreatment),
      ('fillet_strength', IndustrialArtworkKind.weldStrength),
      ('power_source', IndustrialArtworkKind.powerSource),
      ('pass_plan', IndustrialArtworkKind.weldPasses),
      ('distortion', IndustrialArtworkKind.weldDistortion),
      ('cooling_time', IndustrialArtworkKind.coolingTime),
    ]) {
      final finder = find.byKey(ValueKey('tool-artwork-$tool'));
      expect(finder, findsOneWidget);
      expect(tester.widget<IndustrialArtwork>(finder).kind, expected, reason: tool);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('spawanie orbitalne ma grafikę głowicy w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-artwork-orbital_tig')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dobór spoiwa ma grafikę elektrod w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-artwork-filler_selector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('elektroda wolframowa ma grafikę w grupie parametrów', (tester) async {
    await pumpMenu(tester, const WelderMenuScreen());
    await openGroup(tester, ToolGroup.weldParams);
    expect(find.byKey(const ValueKey('tool-artwork-tungsten')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('podpory rur mają grafikę w swojej grupie', (tester) async {
    await pumpMenu(tester, const FitterMenuScreen());
    await openGroup(tester, ToolGroup.supportsFlanges);
    expect(find.byKey(const ValueKey('tool-artwork-pipe_supports')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skrót filtra przyłbicy pokazuje to samo grafikę', (tester) async {
    await pumpMenu(tester,
        Scaffold(body: ToolCompactTile(tool: toolById('shade')!)),
        size: const Size(320, 640));
    expect(find.byKey(const ValueKey('tool-tile-artwork-shade')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('długie nazwy i duży tekst mieszczą się przy grafice', (tester) async {
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
    expect(find.byKey(const ValueKey('tool-artwork-cut_list')), findsOneWidget);
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
