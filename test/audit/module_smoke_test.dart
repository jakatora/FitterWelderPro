import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/l10n/app_localizations.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/database/db.dart' as production_db;
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/models/job_listing.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/screens/chat_screen.dart';
import 'package:cut_list_app/screens/component_library_screen.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/screens/coupon_log_screen.dart';
import 'package:cut_list_app/screens/cut_list_summary_screen.dart';
import 'package:cut_list_app/screens/dn_mm_screen.dart';
import 'package:cut_list_app/screens/elbow_takeout_screen.dart';
import 'package:cut_list_app/screens/fitter_menu_screen.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';
import 'package:cut_list_app/screens/heat_photos_screen.dart';
import 'package:cut_list_app/screens/heat_tint_screen.dart';
import 'package:cut_list_app/screens/help_screen.dart';
import 'package:cut_list_app/screens/home_screen.dart';
import 'package:cut_list_app/screens/hydrotest_screen.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/screens/iso_scanner_screen.dart';
import 'package:cut_list_app/screens/job_add_screen.dart';
import 'package:cut_list_app/screens/jobs_screen.dart';
import 'package:cut_list_app/screens/legal_screen.dart';
import 'package:cut_list_app/screens/material_list_screen.dart';
import 'package:cut_list_app/screens/new_cut_list_project_screen.dart';
import 'package:cut_list_app/screens/new_project_screen.dart';
import 'package:cut_list_app/screens/onboarding_name_screen.dart';
import 'package:cut_list_app/screens/orbital_tig_screen.dart';
import 'package:cut_list_app/screens/passivation_screen.dart';
import 'package:cut_list_app/screens/pipe_route_calculator_screen.dart';
import 'package:cut_list_app/screens/pipe_schedule_screen.dart';
import 'package:cut_list_app/screens/pipe_slope_screen.dart';
import 'package:cut_list_app/screens/pre_weld_checklist_screen.dart';
import 'package:cut_list_app/screens/premium_screen.dart';
import 'package:cut_list_app/screens/profile_screen.dart';
import 'package:cut_list_app/screens/project_components_screen.dart';
import 'package:cut_list_app/screens/projects_screen.dart';
import 'package:cut_list_app/screens/quick_converter_screen.dart';
import 'package:cut_list_app/screens/register_screen.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';
import 'package:cut_list_app/screens/saddle_cut_screen.dart';
import 'package:cut_list_app/screens/saddle_template_screen.dart';
import 'package:cut_list_app/screens/sanitary_tube_screen.dart';
import 'package:cut_list_app/screens/scan_review_screen.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/screens/support_config_screen.dart';
import 'package:cut_list_app/screens/tungsten_screen.dart';
import 'package:cut_list_app/screens/tutor_screen.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart';
import 'package:cut_list_app/screens/welder_identity_setup_screen.dart';
import 'package:cut_list_app/screens/welder_menu_screen.dart';
import 'package:cut_list_app/screens/welder_pipes_screen.dart';
import 'package:cut_list_app/screens/welder_tanks_screen.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/features/qualification/certificate_edit_page.dart';
import 'package:cut_list_app/features/qualification/certificate_register_page.dart';
import 'package:cut_list_app/features/wps/wps_edit_page.dart';
import 'package:cut_list_app/features/wps/wps_library_page.dart';
import 'package:cut_list_app/features/filler/filler_selector_page.dart';
import 'package:cut_list_app/features/pwht/pwht_planner_page.dart';
import 'package:cut_list_app/features/iso5817/iso5817_page.dart';
import 'package:cut_list_app/features/weld_symbols/weld_symbols_page.dart';
import 'package:cut_list_app/features/mitre_bend/mitre_bend_page.dart';
import 'package:cut_list_app/features/progress/progress_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_page.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/features/cooling_time/cooling_time_page.dart';
import 'package:cut_list_app/features/distortion/distortion_page.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_exposure_page.dart';
import 'package:cut_list_app/features/fillet_strength/fillet_strength_page.dart';
import 'package:cut_list_app/features/flange_check/flange_check_page.dart';
import 'package:cut_list_app/features/glossary/glossary_page.dart';
import 'package:cut_list_app/features/hardness/hardness_page.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_page.dart';
import 'package:cut_list_app/features/piecework/piecework_page.dart';
import 'package:cut_list_app/features/power_source/power_source_page.dart';
import 'package:cut_list_app/features/qualification_range/qualification_range_page.dart';
import 'package:cut_list_app/features/shade/shade_page.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_page.dart';
import 'package:cut_list_app/features/weld_defects/weld_defects_page.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_page.dart';
import 'package:cut_list_app/features/weather_check/weather_check_page.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/features/hot_work/hot_work_edit_page.dart';
import 'package:cut_list_app/features/hot_work/hot_work_page.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_page.dart';
import 'package:cut_list_app/features/interpass/interpass_weld_page.dart';
import 'package:cut_list_app/features/instruments/instrument_edit_page.dart';
import 'package:cut_list_app/features/instruments/instrument_register_page.dart';
import 'package:cut_list_app/features/quotes/hourly_rate_page.dart';
import 'package:cut_list_app/features/quotes/quote_edit_page.dart';
import 'package:cut_list_app/features/quotes/quote_joint_page.dart';
import 'package:cut_list_app/features/quotes/quote_list_page.dart';
import 'package:cut_list_app/features/quotes/quote_settings_page.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/services/quote_settings.dart';
import 'package:cut_list_app/modules/welder_pipe/ui/welder_pipe_param_edit_screen.dart';
import 'package:cut_list_app/modules/welder_pipe/ui/welder_pipe_params_list_screen.dart';
import 'package:cut_list_app/modules/welder_tandem/ui/tandem_calculator_screen.dart';
import 'package:cut_list_app/modules/welder_tandem/ui/tandem_library_screen.dart';
import 'package:cut_list_app/modules/welder_tandem/ui/tandem_menu_screen.dart';
import 'package:cut_list_app/modules/welder_tandem/ui/tandem_my_params_screen.dart';

import '../../tool/audit/module_manifest.dart';

const _projectId = 'audit-smoke-project';

const _smokeQuote = WeldQuote(
  id: 'audit-smoke-quote',
  number: 'WYC/2026/001',
  title: 'Kolektor DN100',
  joints: [
    QuoteJoint(
        id: 'j1', kind: JointKind.pipeButt, odMm: 114.3, wallMm: 6.02, count: 12),
  ],
  createdAt: 0,
  updatedAt: 0,
);

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

class _OfflineHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future<HttpClientRequest>.error(
        const SocketException('audit: transport wymuszony offline'),
      );

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildAuditedScreen(String entryPoint) => switch (entryPoint) {
      'AiChatScreen' => const AiChatScreen(),
      'BoltTorqueScreen' => const BoltTorqueScreen(),
      'ChatScreen' => ChatScreen(
          loadRooms: () async =>
              throw const SocketException('audit: czat offline'),
        ),
      'ComponentLibraryScreen' => const ComponentLibraryScreen(),
      'ConsentScreen' => ConsentScreen(onAccepted: () {}),
      'CouponLogScreen' => const CouponLogScreen(),
      'CutListSummaryScreen' =>
        const CutListSummaryScreen(projectId: _projectId),
      'DnMmScreen' => const DnMmScreen(),
      'ElbowTakeoutScreen' => const ElbowTakeoutScreen(),
      'FitterMenuScreen' => const FitterMenuScreen(),
      'FitterScreen' => const FitterScreen(projectId: _projectId),
      'FitterToolsScreen' => const FitterToolsScreen(),
      'HeatInputScreen' => const HeatInputScreen(),
      'HeatPhotosScreen' => const HeatPhotosScreen(projectId: _projectId),
      'HeatTintScreen' => const HeatTintScreen(),
      'HelpScreen' => const HelpScreen(),
      'HomeScreen' => const HomeScreen(),
      'HydrotestScreen' => const HydrotestScreen(),
      'IsoNotebookScreen' => const IsoNotebookScreen(),
      'IsoScannerScreen' => const IsoScannerScreen(),
      'JobAddScreen' => const JobAddScreen(),
      'JobsScreen' => JobsScreen(
          loadListings: ({String? locationLike}) async =>
              throw const SocketException('audit: ogłoszenia offline'),
        ),
      'LegalScreen' => LegalScreen(document: privacyPolicy),
      'MaterialListScreen' => const MaterialListScreen(projectId: _projectId),
      'NewCutListProjectScreen' => const NewCutListProjectScreen(),
      'NewProjectScreen' => const NewProjectScreen(),
      'OnboardingNameScreen' => OnboardingNameScreen(onDone: () {}),
      'OrbitalTigScreen' => const OrbitalTigScreen(),
      'PassivationScreen' => const PassivationScreen(),
      'PipeRouteCalculatorScreen' => const PipeRouteCalculatorScreen(),
      'PipeScheduleScreen' => const PipeScheduleScreen(),
      'PipeSlopeScreen' => const PipeSlopeScreen(),
      'PreWeldChecklistScreen' => const PreWeldChecklistScreen(),
      'PremiumScreen' => const PremiumScreen(),
      'ProfileScreen' => const ProfileScreen(),
      'ProjectComponentsScreen' =>
        const ProjectComponentsScreen(projectId: _projectId),
      'ProjectsScreen' => const ProjectsScreen(),
      'QuickConverterScreen' => const QuickConverterScreen(),
      'RegisterScreen' => const RegisterScreen(),
      'RollingOffsetScreen' => const RollingOffsetScreen(),
      'SaddleCutScreen' => const SaddleCutScreen(),
      'SaddleTemplateScreen' => const SaddleTemplateScreen(),
      'SanitaryTubeScreen' => const SanitaryTubeScreen(),
      'ScanReviewScreen' => ScanReviewScreen(scan: AiScanResult()),
      'SegmentBuilderScreen' => const SegmentBuilderScreen(
          materialGroup: 'SS',
          currentDiameter: 114.3,
          wallThickness: 3.05,
          gapMm: 0,
        ),
      'SupportConfigScreen' => const SupportConfigScreen(),
      'TungstenScreen' => const TungstenScreen(),
      'TutorScreen' => const TutorScreen(),
      'WeldJournalScreen' => const WeldJournalScreen(),
      'WelderIdentitySetupScreen' => const WelderIdentitySetupScreen(),
      'WelderMenuScreen' => const WelderMenuScreen(),
      'WelderPipesScreen' => const WelderPipesScreen(),
      'WelderTanksScreen' => const WelderTanksScreen(),
      'WelderToolsScreen' => const WelderToolsScreen(),
      'WelderPipeParamEditScreen' => const WelderPipeParamEditScreen(),
      'WelderPipeParamsListScreen' => const WelderPipeParamsListScreen(),
      'TandemCalculatorScreen' =>
        const TandemCalculatorScreen(position: 'HORIZONTAL'),
      'TandemLibraryScreen' =>
        const TandemLibraryScreen(position: 'HORIZONTAL'),
      'TandemMenuScreen' => const TandemMenuScreen(position: 'HORIZONTAL'),
      'TandemMyParamsScreen' =>
        const TandemMyParamsScreen(position: 'HORIZONTAL'),
      'CertificateRegisterPage' => const CertificateRegisterPage(),
      'CertificateEditPage' => const CertificateEditPage(),
      'WpsLibraryPage' => const WpsLibraryPage(),
      'WpsEditPage' => const WpsEditPage(),
      'QuoteListPage' => const QuoteListPage(),
      'HourlyRatePage' => const HourlyRatePage(),
      'FillerSelectorPage' => const FillerSelectorPage(),
      'PwhtPlannerPage' => const PwhtPlannerPage(),
      'Iso5817Page' => const Iso5817Page(),
      'WeldSymbolsPage' => const WeldSymbolsPage(),
      'MitreBendPage' => const MitreBendPage(),
      'ProgressPage' => const ProgressPage(),
      'SteelWeightPage' => const SteelWeightPage(),
      'InstrumentRegisterPage' => const InstrumentRegisterPage(),
      'CoolingTimePage' => const CoolingTimePage(),
      'HotWorkPage' => const HotWorkPage(),
      'ElectrodeExposurePage' => const ElectrodeExposurePage(),
      'FlangeCheckPage' => const FlangeCheckPage(),
      'WeatherCheckPage' => const WeatherCheckPage(),
      'ConeLayoutPage' => const ConeLayoutPage(),
      'GlossaryPage' => const GlossaryPage(),
      'FilletStrengthPage' => const FilletStrengthPage(),
      'HardnessPage' => const HardnessPage(),
      'PieceworkPage' => const PieceworkPage(),
      'BoltKitPage' => const BoltKitPage(),
      'NdtPlanPage' => const NdtPlanPage(),
      'TubeBendingPage' => const TubeBendingPage(),
      'QualificationRangePage' => const QualificationRangePage(),
      'DistortionPage' => const DistortionPage(),
      'WeldDefectsPage' => const WeldDefectsPage(),
      'PowerSourcePage' => const PowerSourcePage(),
      'WelderExamPage' => const WelderExamPage(),
      'ShadePage' => const ShadePage(),
      'InterpassPage' => const InterpassPage(),
      'InterpassWeldPage' => InterpassWeldPage(
          initial: InterpassWeld.blank(
              id: 'smoke-interpass', now: DateTime(2026, 10, 18, 7))),
      'HotWorkEditPage' => HotWorkEditPage(
          initial: HotWorkPermit.blank(
              id: 'smoke-hot-work', now: DateTime(2026, 10, 17, 7))),
      'InstrumentEditPage' => const InstrumentEditPage(),
      'QuoteEditPage' =>
        QuoteEditPage(quote: _smokeQuote, settings: const QuoteSettings()),
      'QuoteJointPage' => QuoteJointPage(quote: _smokeQuote),
      'QuoteSettingsPage' =>
        const QuoteSettingsPage(settings: QuoteSettings()),
      _ => throw ArgumentError.value(entryPoint, 'entryPoint'),
    };

Widget _testApp(Widget child, {double textScale = 1.3}) {
  final language = AppLanguageController(AppLanguage.pl);
  return AppLanguageScope(
    controller: language,
    child: MaterialApp(
      locale: const Locale('pl'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: appChild!,
      ),
      home: child,
    ),
  );
}

Future<void> _settleStart(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() async {
      final db = await production_db.AppDatabase.get();
      await db.rawQuery('SELECT 1');
    });
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final originalHttpOverrides = HttpOverrides.current;
  late Directory smokeDirectory;
  late String smokeDatabasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    HttpOverrides.global = _OfflineHttpOverrides();
    smokeDirectory = await Directory.systemTemp.createTemp('fwp-smoke-');
    smokeDatabasePath =
        '${smokeDirectory.path}${Platform.pathSeparator}cutlist-smoke.db';
    await production_db.AppDatabase.configureForTesting(smokeDatabasePath);

    final now = DateTime.now().millisecondsSinceEpoch;
    await ProjectDao().insert(Project(
      id: _projectId,
      name: 'Projekt audytu ekranów',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 3,
      gapMm: 0,
      createdAt: now,
      updatedAt: now,
    ));
    final fixture = await ProjectDao().getById(_projectId);
    expect(fixture?.name, 'Projekt audytu ekranów');
  });

  tearDownAll(() async {
    await production_db.AppDatabase.clearTestingConfiguration();
    await deleteDatabase(smokeDatabasePath);
    expect(await databaseExists(smokeDatabasePath), isFalse);
    if (await smokeDirectory.exists()) {
      await smokeDirectory.delete(recursive: true);
    }
    HttpOverrides.global = originalHttpOverrides;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'premium_active': false,
      'user_profile_v1':
          '{"firstName":"Jan","lastName":"Spawacz","updatedAt":1}',
    });
  });

  test('każdy wpis manifestu ma bezpieczną fabrykę ekranu', () {
    for (final entry in moduleManifest) {
      final screen = buildAuditedScreen(entry.entryPoint);
      expect(
        screen.runtimeType.toString(),
        entry.entryPoint,
        reason: '${entry.entryPoint} ma wskazywać własny typ widżetu',
      );
    }
  });

  for (final entry in moduleManifest) {
    testWidgets('${entry.entryPoint} renderuje przy skali tekstu 1,3',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_testApp(buildAuditedScreen(entry.entryPoint)));
      await _settleStart(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settleStart(tester);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('formularz rejestracji zachowuje wpisane dane po błędzie',
      (tester) async {
    await tester.pumpWidget(_testApp(const RegisterScreen()));
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'spawacz@example.com');
    await tester.enterText(fields.at(1), 'haslo-123');
    await tester.enterText(fields.at(2), 'inne-haslo');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('spawacz@example.com'), findsOneWidget);
    expect(find.text('haslo-123'), findsOneWidget);
    expect(find.text('inne-haslo'), findsOneWidget);
    expect(
      find.text('Uzupełnij pola i upewnij się, że hasła są takie same.'),
      findsOneWidget,
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('Ponów naprawdę ponawia Chat i pokazuje wynik drugiej próby',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_testApp(ChatScreen(
      loadRooms: () async {
        calls++;
        if (calls == 1) {
          throw const SocketException('audit: czat offline');
        }
        return const [
          ChatRoom(
            id: 'audit-room',
            namePl: 'Pokój po ponowieniu',
            nameEn: 'Room after retry',
            descPl: 'Połączenie wróciło',
            descEn: 'Connection restored',
          ),
        ];
      },
    )));
    await _settleStart(tester);
    expect(calls, 1);
    await tester.tap(find.text('Spróbuj ponownie'));
    await _settleStart(tester);
    expect(calls, 2);
    expect(find.text('Pokój po ponowieniu'), findsOneWidget);
  });

  testWidgets('Ponów naprawdę ponawia Jobs i pokazuje wynik drugiej próby',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_testApp(JobsScreen(
      loadListings: ({String? locationLike}) async {
        calls++;
        if (calls == 1) {
          throw const SocketException('audit: ogłoszenia offline');
        }
        return [
          JobListing(
            id: 'audit-job',
            title: 'Oferta po ponowieniu',
            company: 'Audit',
            location: 'Warsztat',
            description: 'Test retry',
            requirementsCsv: 'TIG 141',
            createdAt: DateTime(2026, 8, 30).millisecondsSinceEpoch,
          ),
        ];
      },
    )));
    await _settleStart(tester);
    expect(calls, 1);
    await tester.tap(find.text('Ponów'));
    await _settleStart(tester);
    expect(calls, 2);
    expect(find.text('Oferta po ponowieniu'), findsOneWidget);
  });

  testWidgets('ProjectsScreen nie aktualizuje stanu po zamknięciu podczas load',
      (tester) async {
    await tester.pumpWidget(_testApp(const ProjectsScreen()));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleStart(tester);
    expect(tester.takeException(), isNull);
  });

  test('ProjectsScreen chroni _load przed pierwszym setState i callback', () {
    final source = File('lib/screens/projects_screen.dart').readAsStringSync();
    final loadStart = source.indexOf('Future<void> _load() async {');
    final firstGuard = source.indexOf('if (!mounted) return;', loadStart);
    final firstSetState =
        source.indexOf('setState(() => _loading = true)', loadStart);
    expect(firstGuard, inInclusiveRange(loadStart, firstSetState));
    expect(source, contains('if (mounted) _load();'));
  });

  testWidgets('główne akcje formularzy mają etykiety semantyczne',
      (tester) async {
    const cases = <(Widget, String)>[
      (NewProjectScreen(), 'Utwórz projekt'),
      (NewCutListProjectScreen(), 'UTWÓRZ PROJEKT'),
      (WelderPipeParamEditScreen(), 'Zapisz'),
    ];
    for (final (screen, label) in cases) {
      await tester.pumpWidget(_testApp(screen));
      await tester.pump();
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(label),
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }
      final labelledAction = find.ancestor(
        of: find.text(label),
        matching:
            find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      expect(labelledAction, findsOneWidget);
      expect(
        tester.getSemantics(find.text(label)).label,
        label,
      );
    }
  });
}
