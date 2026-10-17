// Rejestr narzędzi: jedno źródło dla menu montera, menu spawacza,
// wyszukiwarki, ostatnio używanych i przypiętych.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/config/feature_flags.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

import '../support/test_database.dart';
import '../test_prefs.dart';

/// „Typ ekranu" albo „FitterToolsScreen#zakładka" — tożsamość celu wpisu.
String _targetOf(ToolSpec tool, BuildContext context) {
  final w = tool.builder(context);
  if (w is FitterToolsScreen) return 'FitterToolsScreen#${w.initialTab}';
  return w.runtimeType.toString();
}

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(Builder(builder: (context) {
    captured = context;
    return const SizedBox();
  }));
  return captured;
}

void main() {
  group('integralność', () {
    test('identyfikatory są unikalne i niepuste', () {
      final ids = kToolRegistry.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.where((id) => id.trim().isEmpty), isEmpty);
    });

    test('tytuły są unikalne w obu językach i mają podtytuł', () {
      for (final lang in [
        (kToolRegistry.map((t) => t.titlePl)),
        (kToolRegistry.map((t) => t.titleEn)),
      ]) {
        expect(lang.toSet().length, lang.length);
      }
      for (final t in kToolRegistry) {
        expect(t.subtitlePl.trim(), isNotEmpty, reason: t.id);
        expect(t.subtitleEn.trim(), isNotEmpty, reason: t.id);
        expect(t.keywordsPl, isNotEmpty, reason: t.id);
        expect(t.keywordsEn, isNotEmpty, reason: t.id);
      }
    });

    test('tytuły zdaniem, nie WERSALIKAMI (skróty branżowe dozwolone)', () {
      for (final t in kToolRegistry) {
        for (final title in [t.titlePl, t.titleEn]) {
          final words = title
              .split(RegExp(r'[\s—–/↔-]+'))
              .where((w) => w.length > 3 && RegExp(r'[A-Za-z]').hasMatch(w));
          final shouting = words.where((w) => w == w.toUpperCase());
          expect(shouting, isEmpty, reason: '${t.id}: "$title"');
        }
      }
    });

    test('każda grupa należy do sekcji i ma narzędzia', () {
      for (final section in ToolSection.values) {
        expect(groupsOf(section), isNotEmpty);
        for (final g in groupsOf(section)) {
          expect(g.section, section);
          expect(toolsInGroup(g), isNotEmpty);
        }
      }
    });
  });

  group('wejścia do ekranów', () {
    testWidgets('jedno wejście na narzędzie — żadnych duplikatów celu',
        (tester) async {
      final ctx = await _context(tester);
      final targets = kToolRegistry.map((t) => _targetOf(t, ctx)).toList();
      expect(targets.toSet().length, targets.length,
          reason: 'dwa wpisy prowadzą do tego samego ekranu/zakładki');
    });

    testWidgets('wszystkie dawne kafle montera i spawacza mają swój wpis',
        (tester) async {
      final ctx = await _context(tester);
      final targets = kToolRegistry.map((t) => _targetOf(t, ctx)).toSet();
      const expected = {
        // Dawne kafle menu montera.
        'ProjectsScreen', 'DnMmScreen', 'FitterToolsScreen#0',
        'FitterToolsScreen#1', 'FitterToolsScreen#2', 'FitterToolsScreen#3',
        'FitterToolsScreen#4', 'ComponentLibraryScreen',
        'PipeRouteCalculatorScreen', 'RollingOffsetScreen', 'PipeSlopeScreen',
        'SaddleCutScreen', 'IsoNotebookScreen', 'IsoScannerScreen',
        'ElbowTakeoutScreen', 'QuickConverterScreen', 'PipeScheduleScreen',
        'SanitaryTubeScreen', 'SupportConfigScreen', 'BoltTorqueScreen',
        'SaddleTemplateScreen',
        // Trzy zakładki FitterToolsScreen, które nie miały kafla.
        'FitterToolsScreen#5', 'FitterToolsScreen#6', 'FitterToolsScreen#7',
        // Dawne kafle menu spawacza.
        'WelderPipesScreen', 'WelderTanksScreen', 'WelderToolsScreen',
        'WeldJournalScreen', 'OrbitalTigScreen', 'HeatTintScreen',
        'PreWeldChecklistScreen', 'CouponLogScreen', 'TungstenScreen',
        'PassivationScreen', 'HydrotestScreen', 'HeatInputScreen',
        // v21: rejestr uprawnień spawacza i biblioteka WPS.
        'CertificateRegisterPage', 'WpsLibraryPage',
        // Asystent (spec §6) — nowe wejście, nie dawny kafel.
        'AiChatScreen',
        // v26: wyceny spawalnicze.
        'QuoteListPage',
        'HourlyRatePage',
        // Dobór spoiwa (EN ISO + AWS).
        'FillerSelectorPage',
        // Plan PWHT (ASME B31.3 / B31.1).
        'PwhtPlannerPage',
        // Odbiór wizualny wg EN ISO 5817.
        'Iso5817Page',
        // Symbole spawalnicze (ISO 2553 / AWS A2.4).
        'WeldSymbolsPage',
        // Kolano segmentowe (lobster back).
        'MitreBendPage',
        // Postęp robót z dziennika spoin.
        'ProgressPage',
        // Ciężar stali — profile, blachy, pręty.
        'SteelWeightPage',
        // Rejestr przyrządów i kalibracji (v27).
        'InstrumentRegisterPage',
        // Czas stygnięcia t8/5 (EN 1011-2 zał. D).
        'CoolingTimePage',
        // Prace pożarowo niebezpieczne (zezwolenie, DGW).
        'HotWorkPage',
        // Elektrody zasadowe: czas na powietrzu i suszenie.
        'ElectrodeExposurePage',
        // Odbiór połączenia kołnierzowego (PCC-1).
        'FlangeCheckPage',
        // Warunki do spawania (pogoda, punkt rosy).
        'WeatherCheckPage',
        // Rozwinięcie stożka i przejść (szablon 1:1).
        'ConeLayoutPage',
        // Słownik spawalniczy PL/EN/DE/NL/NO.
        'GlossaryPage',
      };
      expect(targets, expected);
    });

    testWidgets('ekrany-sieroty nie dostają wejścia tylnymi drzwiami',
        (tester) async {
      final ctx = await _context(tester);
      final targets = kToolRegistry.map((t) => _targetOf(t, ctx)).toSet();
      for (final orphan in const [
        'TandemMenuScreen',
        'WelderPipeParamsListScreen',
        'RegisterScreen',
        'TutorScreen',
        'NewCutListProjectScreen',
      ]) {
        expect(targets.contains(orphan), isFalse, reason: orphan);
      }
    });

    test('skaner widoczny, gdy da się go użyć (darmowy tryb albo Premium)',
        () {
      expect(toolById('iso_scanner') != null, kAiScannerReachable);
      expect(
        resolveTools(['iso_scanner', 'nie-istnieje', 'dn_mm'])
            .map((t) => t.id),
        [if (kAiScannerReachable) 'iso_scanner', 'dn_mm'],
      );
      // Skaner nie publikuje niczego pod nazwiskiem — nie przechodzi przez
      // bramkę imienia i zasad czatu. Zgodę na wysyłkę zdjęcia (serwer +
      // Anthropic) pytamy przed pierwszym skanem (scan_consent_gate.dart).
      expect(kToolRegistry.firstWhere((t) => t.id == 'iso_scanner').needsAccount,
          isFalse);
    });
  });

  group('wyszukiwarka', () {
    List<String> ids(String q, [AppLanguage lang = AppLanguage.pl]) =>
        searchTools(q, lang).map((h) => h.tool.id).toList();

    test('pusty i bezsensowny tekst nic nie zwraca', () {
      expect(ids(''), isEmpty);
      expect(ids('   '), isEmpty);
      expect(ids('xyzqq'), isEmpty);
    });

    test('„kolano" — wymiary kolan na pierwszym miejscu, reszta kolan też',
        () {
      final r = ids('kolano');
      expect(r.first, 'elbow_takeouts');
      expect(r, containsAll(['elbow_cut', 'elbow_rotation']));
    });

    test('polskie znaki i wielkość liter nie mają znaczenia', () {
      expect(ids('Ciężar').first, 'pipe_weight');
      expect(ids('ciezar').first, 'pipe_weight');
      expect(ids('WYMIARY KOLAN').first, 'elbow_takeouts');
    });

    test('odmiana: „spadku", „kolanka" też trafia', () {
      expect(ids('spadku'), containsAll(['pipe_slope', 'slope_cut']));
      expect(ids('kolanka'), contains('elbow_cut'));
    });

    test('dwa różne narzędzia od spadku mają różne nazwy i oba się znajdują',
        () {
      expect(ids('spadek'), containsAll(['pipe_slope', 'slope_cut']));
      expect(toolById('pipe_slope')!.titlePl,
          isNot(toolById('slope_cut')!.titlePl));
    });

    test('żargon angielski działa także w wersji polskiej', () {
      expect(ids('takeout').first, 'elbow_takeouts');
      expect(ids('rolling').first, 'rolling_offset');
      expect(ids('saddle'), containsAll(['saddle_cut', 'saddle_template']));
    });

    test('heat input ma jedno wejście', () {
      expect(ids('heat input'), ['heat_input']);
    });

    test('zakładki bez dawnego kafla są do znalezienia', () {
      expect(ids('dylatacja').first, 'thermal_expansion');
      expect(ids('fazowanie').first, 'bevel');
      expect(ids('ciezar rury').first, 'pipe_weight');
    });

    test('każde słowo zapytania musi pasować', () {
      expect(ids('kolano pasywacja'), isEmpty);
    });

    test('po angielsku', () {
      expect(ids('elbow', AppLanguage.en).first, 'elbow_takeouts');
      expect(ids('weight', AppLanguage.en).first, 'pipe_weight');
    });
  });

  group('otwieranie', () {
    useTestDatabase();

    Future<void> openById(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1100, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      seedFreshInstall();
      late BuildContext ctx;
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        })),
      ));
      openTool(ctx, toolById(id)!);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    for (final (id, tab, label) in const [
      ('pipe_weight', 5, 'Ciężar rury'),
      ('bevel', 6, 'Fazowanie'),
      ('thermal_expansion', 7, 'Dylatacja'),
    ]) {
      testWidgets('$id otwiera od razu właściwą zakładkę ($label)',
          (tester) async {
        await openById(tester, id);
        expect(find.byType(FitterToolsScreen), findsOneWidget);
        final controller = DefaultTabController.of(
            tester.element(find.byType(TabBarView)));
        expect(controller.index, tab);
        expect(find.text(label), findsWidgets);
      });
    }
  });
}
