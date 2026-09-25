// Zdjęcie numeru wytopu prosto z aparatu.
//
// Na starej wersji heat dodawało się tylko z galerii / plików (FilePicker),
// a `image_picker` leżał w pubspec nieużywany. Teraz: „Aparat / Galeria” na
// telefonie, sam plik na Windows / web; zdjęcie trafia do
// <documents>/heat_photos (objęte kopią). Picker to atrapa.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cut_list_app/database/component_heat_dao.dart';
import 'package:cut_list_app/database/heat_photo_dao.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/heat_photos_screen.dart';
import 'package:cut_list_app/screens/project_components_screen.dart';
import 'package:cut_list_app/services/heat_photo_capture.dart';
import 'package:cut_list_app/services/heat_photo_storage.dart';
import 'package:cut_list_app/widgets/heat_photo_source_buttons.dart';

import '../support/test_database.dart';

class _FakePicker implements HeatPhotoPicker {
  _FakePicker(this.result);

  String? result;
  String? lost;
  Object? error;
  final List<HeatPhotoSource> asked = [];

  @override
  Future<String?> pick(HeatPhotoSource source) async {
    asked.add(source);
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<String?> retrieveLost() async {
    final l = lost;
    lost = null;
    return l;
  }
}

const _projectId = 'heat-cam-proj';

Project _project() => Project(
      id: _projectId,
      name: 'Heat aparat',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 0,
      createdAt: 1,
      updatedAt: 1,
    );

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useTestDatabase();

  late Directory sandbox;
  late Directory heatDir;
  late File cameraShot;
  late _FakePicker picker;
  final originalPicker = HeatPhotoPicker.instance;

  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('fwp_heat_cam_');
    heatDir = Directory(p.join(sandbox.path, 'documents', 'heat_photos'));
    final cache = Directory(p.join(sandbox.path, 'cache'));
    await cache.create(recursive: true);
    cameraShot = File(p.join(cache.path, 'image_picker_cam.jpg'));
    await cameraShot.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    await ProjectDao().insert(_project());
    await SegmentDao().insert({
      'id': 'heat-cam-s1',
      'project_id': _projectId,
      'seq_no': 1,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'start_kind': 'logical',
      'start_library_id': null,
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'OPEN|OPEN',
      'iso_expr': '1000',
      'iso_mm': 1000.0,
      'cut_mm': 1000.0,
      'created_at': 1,
      'updated_at': 1,
    });
  });

  tearDownAll(() async {
    debugHeatPhotosDirectoryOverride = null;
    HeatPhotoPicker.instance = originalPicker;
    // Best-effort: na Windows plik wyświetlanego zdjęcia bywa jeszcze
    // otwarty przez dekoder obrazu, a katalog tymczasowy i tak sprząta system.
    try {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  setUp(() {
    debugHeatPhotosDirectoryOverride = heatDir;
    picker = _FakePicker(cameraShot.path);
    HeatPhotoPicker.instance = picker;
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(screen));
  }

  group('ekran „Heat numbers”', () {
    testWidgets('telefon: Aparat / Galeria, zdjęcie z aparatu trafia do '
        'heat_photos i do bazy', (tester) async {
      await pumpScreen(tester, const HeatPhotosScreen(projectId: _projectId));
      await _pumpUntil(
          tester, () => find.byType(FloatingActionButton).evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final camera = find.byKey(const ValueKey('heat-photo-source-camera'));
      final gallery = find.byKey(const ValueKey('heat-photo-source-gallery'));
      expect(camera, findsOneWidget);
      expect(gallery, findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(tester.getSize(camera).height, greaterThanOrEqualTo(64));
      expect(tester.getSize(gallery).height, greaterThanOrEqualTo(64));

      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(picker.asked, [HeatPhotoSource.camera]);
      expect(find.text('Add HEAT number (optional)'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'HEAT 4471-B');
      await tester.tap(find.text('Save'));
      await _pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);

      final rows = await tester
          .runAsync(() => HeatPhotoDao().listForProject(_projectId));
      final row = rows!.firstWhere((r) => r.note == 'HEAT 4471-B');
      expect(p.isWithin(heatDir.path, row.imagePath), isTrue,
          reason: 'kopia w heat_photos, nie ścieżka z cache pickera');
      expect(await tester.runAsync(() => File(row.imagePath).readAsBytes()),
          <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    });

    testWidgets('Windows: bez arkusza, od razu wybór pliku', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        picker.result = null; // użytkownik zamknął okno wyboru
        await pumpScreen(tester, const HeatPhotosScreen(projectId: _projectId));
        await _pumpUntil(tester,
            () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(picker.asked, [HeatPhotoSource.files]);
        expect(find.byKey(const ValueKey('heat-photo-source-camera')),
            findsNothing);
        expect(find.text('Add HEAT number (optional)'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android zabił aplikację przy aparacie: zdjęcie wraca po '
        'ponownym otwarciu', (tester) async {
      picker.lost = cameraShot.path;
      await pumpScreen(tester, const HeatPhotosScreen(projectId: _projectId));
      await _pumpUntil(tester,
          () => find.text('Add HEAT number (optional)').evaluate().isNotEmpty);
      expect(find.text('Add HEAT number (optional)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('brak zgody na aparat: komunikat, nic nie zapisane',
        (tester) async {
      picker.error = PlatformException(code: 'camera_access_denied');
      await pumpScreen(tester, const HeatPhotosScreen(projectId: _projectId));
      await _pumpUntil(tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('heat-photo-source-camera')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No camera permission'), findsOneWidget);
      expect(find.text('Add HEAT number (optional)'), findsNothing);
    });
  });

  group('„Komponenty / Heat” — okno „Dodaj HEAT”', () {
    testWidgets('Aparat w oknie: heat z kopią zdjęcia w heat_photos',
        (tester) async {
      await pumpScreen(
          tester, const ProjectComponentsScreen(projectId: _projectId));
      await _pumpUntil(tester,
          () => find.textContaining('S001_END').evaluate().isNotEmpty);

      await tester.tap(find.byTooltip('Add heat').last);
      await tester.pumpAndSettle();

      final camera = find.byKey(const ValueKey('heat-photo-source-camera'));
      expect(camera, findsOneWidget);
      expect(find.byKey(const ValueKey('heat-photo-source-gallery')),
          findsOneWidget);
      expect(tester.getSize(camera).height, greaterThanOrEqualTo(64));

      await tester.enterText(
          find.widgetWithText(TextField, 'Heat number'), 'H-77821');
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(picker.asked, [HeatPhotoSource.camera]);
      expect(find.textContaining('image_picker_cam.jpg'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await _pumpUntil(
          tester, () => find.textContaining('Heat: 1').evaluate().isNotEmpty);

      final heats = await tester.runAsync(() => ComponentHeatDao()
          .listForComponent(projectId: _projectId, componentKey: 'S001_END'));
      final heat = heats!.single;
      expect(heat.heatNo, 'H-77821');
      expect(p.isWithin(heatDir.path, heat.imagePath!), isTrue);
    });
  });

  testWidgets('HeatPhotoSourceButtons: Galeria oddaje ścieżkę', (tester) async {
    String? got;
    await tester.pumpWidget(_wrap(Scaffold(
      body: HeatPhotoSourceButtons(onPicked: (path) => got = path),
    )));
    await tester.tap(find.byKey(const ValueKey('heat-photo-source-gallery')));
    await tester.pump();
    expect(picker.asked, [HeatPhotoSource.gallery]);
    expect(got, cameraShot.path);
  });
}
