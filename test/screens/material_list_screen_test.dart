// Lista materiałowa: „Kopiuj całość” i „Udostępnij” dla całej listy (wcześniej
// dało się kopiować tylko pojedyncze wiersze długim przytrzymaniem) oraz opis
// kształtek znanych tylko z rodzaju końca (projekty ze skanera).
//
// Dane: FLANGE→TEE, TEE→ELB90, TEE→FLANGE (odgałęzienie z trójnika), po
// 1000 mm rury Ø114.3 × 3.6 → RURA 3.000 m, ELB90 1, FLANGE 2, TEE 1.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/material_item.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/material_list_screen.dart';
import 'package:cut_list_app/services/heat_traceability.dart';
import 'package:cut_list_app/services/material_list_builder.dart';

const _share = MethodChannel('dev.fluttercommunity.plus/share');
const _pid = 'PRJ-BOM';

class _FakeSegmentDao extends SegmentDao {
  final List<Segment> rows;
  _FakeSegmentDao(this.rows);
  @override
  Future<List<Segment>> listForProject(String projectId) async => rows;
}

class _FakeLibraryDao extends ComponentLibraryDao {
  @override
  Future<LibraryComponent?> getById(String id) async => LibraryComponent(
        id: id,
        materialGroup: 'SS',
        type: id,
        diameterMm: 114.3,
        wallThicknessMm: 3.6,
        axisMm: id == 'FLANGE' ? null : 76.2,
        lengthMm: id == 'FLANGE' ? 60 : null,
        measurementMode: id == 'FLANGE' ? 'FACE' : null,
        diameterOutMm: null,
        createdAt: 0,
        updatedAt: 0,
      );
}

class _FakeProjectDao extends ProjectDao {
  @override
  Future<Project?> getById(String id) async => Project(
        id: id,
        name: 'Łącznik żółć',
        materialGroup: 'SS',
        diameterMm: 114.3,
        wallThicknessMm: 3.6,
        currentDiameterMm: 114.3,
        stockLengthMm: 6000,
        sawKerfMm: 3,
        gapMm: 0,
        createdAt: 0,
        updatedAt: 0,
      );
}

Segment _seg(int seq, String start, String end) => Segment(
      id: 'S$seq',
      projectId: _pid,
      seqNo: seq,
      diameterMm: 114.3,
      wallThicknessMm: 3.6,
      startKind: start == 'FLANGE' ? 'nonAxial' : 'axial',
      startLibraryId: start,
      startValueMm: 0,
      endKind: end == 'FLANGE' ? 'nonAxial' : 'axial',
      endLibraryId: end,
      endValueMm: 0,
      isoRef: 'FACE|FACE',
      isoExpr: '1000',
      isoMm: 1000,
      cutMm: 1000,
      createdAt: 0,
      updatedAt: 0,
    );

class _IdentifiedProjectDao extends ProjectDao {
  @override
  Future<Project?> getById(String id) async => Project(
        id: id,
        name: 'Łącznik żółć',
        materialGroup: 'SS',
        diameterMm: 114.3,
        wallThicknessMm: 3.6,
        currentDiameterMm: 114.3,
        stockLengthMm: 6000,
        sawKerfMm: 3,
        gapMm: 0,
        createdAt: 0,
        updatedAt: 0,
        lineNo: 'DN100-CWS-1234',
        isoNo: 'ISO-7',
        isoRev: 'B',
        client: 'Orlen',
        spec: 'A1B',
      );
}

MaterialListBuilder _builder() => MaterialListBuilder(
      _FakeSegmentDao([
        _seg(1, 'FLANGE', 'TEE'),
        _seg(2, 'TEE', 'ELB90'),
        _seg(3, 'TEE', 'FLANGE'),
      ]),
      _FakeLibraryDao(),
      _FakeProjectDao(),
    );

const _expectedPl = 'Lista materiałowa (BOM) — Łącznik żółć\n'
    'RURA - Rura Ø114.3 x 3.6 - 3.000 m netto · 1 sztanga × 6000 mm\n'
    'ELB90 - ELB90 Ø114.3 x 3.6 | A=76.2 - 1 szt.\n'
    'FLANGE - FLANGE Ø114.3 x 3.6 | FACE= 60.0 - 2 szt.\n'
    'TEE - TEE Ø114.3 x 3.6 | A=76.2 - 1 szt.\n';

void main() {
  final shareCalls = <MethodCall>[];
  final clipboard = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    shareCalls.clear();
    clipboard.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_share, (call) async {
      shareCalls.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_share, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpScreen(WidgetTester tester, AppLanguage lang) async {
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
        home: MaterialListScreen(projectId: _pid, builder: _builder()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('„Kopiuj całość” kopiuje całą listę z nazwą projektu',
      (tester) async {
    await pumpScreen(tester, AppLanguage.pl);
    expect(find.text('TEE'), findsOneWidget);

    await tester.tap(find.byTooltip('Kopiuj całość'));
    await tester.pumpAndSettle();

    expect(clipboard, [_expectedPl]);
    expect(find.text('Skopiowano listę materiałową (4 poz.)'), findsOneWidget);
  });

  testWidgets('„Udostępnij” otwiera arkusz systemowy z całą listą',
      (tester) async {
    await pumpScreen(tester, AppLanguage.pl);

    await tester.tap(find.byTooltip('Udostępnij'));
    await tester.pumpAndSettle();

    expect(shareCalls, hasLength(1));
    expect(shareCalls.single.method, 'share');
    final args = (shareCalls.single.arguments as Map).cast<String, Object?>();
    expect(args['text'], _expectedPl);
    expect(args['subject'], 'Lista materiałowa (BOM) — Łącznik żółć');
  });

  testWidgets('pusta lista: przyciski wyłączone', (tester) async {
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: MaterialListScreen(
          projectId: _pid,
          builder: MaterialListBuilder(
              _FakeSegmentDao(const []), _FakeLibraryDao(), _FakeProjectDao()),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final copy = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.copy_all_outlined),
      matching: find.byType(IconButton),
    ));
    expect(copy.onPressed, isNull);
    final share = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.share_outlined),
      matching: find.byType(IconButton),
    ));
    expect(share.onPressed, isNull);
  });

  testWidgets(
      'v22: nagłówek z linią / ISO / rewizją / klientem na ekranie i w kopii',
      (tester) async {
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: MaterialListScreen(
          projectId: _pid,
          builder: MaterialListBuilder(
            _FakeSegmentDao([_seg(1, 'FLANGE', 'TEE')]),
            _FakeLibraryDao(),
            _IdentifiedProjectDao(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const line =
        'Linia: DN100-CWS-1234 · ISO: ISO-7 rew. B · Klient: Orlen · Klasa: A1B';
    expect(find.text(line), findsOneWidget);

    await tester.tap(find.byTooltip('Kopiuj całość'));
    await tester.pumpAndSettle();
    expect(clipboard.single.split('\n').take(2).toList(),
        ['Lista materiałowa (BOM) — Łącznik żółć', line]);
  });

  test('BOM rury: sztangi z rzazem jak lista cięć, nie sama suma netto',
      () async {
    // 3000 + 2999 z rzazem 3: 3000 + 3 + 2999 = 6002 > 6000 → 2 sztangi,
    // choć netto to tylko 5,999 m (stary BOM: „5.999 m” = jedna sztanga).
    Segment cut(int seq, double mm) => Segment(
          id: 'c$seq',
          projectId: _pid,
          seqNo: seq,
          diameterMm: 114.3,
          wallThicknessMm: 3.6,
          startKind: 'logical',
          startLibraryId: null,
          startValueMm: 0,
          endKind: 'logical',
          endLibraryId: null,
          endValueMm: 0,
          isoRef: 'OPEN|OPEN',
          isoExpr: '$mm',
          isoMm: mm,
          cutMm: mm,
          createdAt: 0,
          updatedAt: 0,
        );
    final items = await MaterialListBuilder(
      _FakeSegmentDao([cut(1, 3000), cut(2, 2999)]),
      _FakeLibraryDao(),
      _FakeProjectDao(),
    ).buildForProject(_pid);
    final pipe = items.single;
    expect(pipe.totalLengthMm, 5999);
    expect(pipe.bars, 2);
    expect(bomQuantityText(pipe, english: false),
        '5.999 m netto · 2 sztangi × 6000 mm');
    expect(bomQuantityText(pipe, english: true), '5.999 m net · 2 bars × 6000 mm');
  });

  test('buildBomText: numery wytopów pod pozycjami', () {
    expect(
      buildBomText(
        items: const [],
        projectName: 'X',
        english: false,
        heatRows: const [
          HeatReportRow(
              segments: 'S01', place: 'Rura Ø114.3 × 3.60', heats: 'A1, A2'),
        ],
      ),
      'Lista materiałowa (BOM) — X\n'
      '\n'
      'Numery wytopów:\n'
      'S01 · Rura Ø114.3 × 3.60: A1, A2\n',
    );
  });

  test('buildBomText: pusta identyfikacja nie dodaje linii', () {
    expect(
      buildBomText(
        items: const [],
        projectName: 'X',
        english: false,
        identity: ProjectIdentity.empty,
      ),
      'Lista materiałowa (BOM) — X\n',
    );
  });

  group('opis kształtek bez wpisu biblioteki', () {
    final axial = MaterialItem(
      category: 'FITTING_AXIAL',
      description: 'fallback',
      quantity: 3,
      endKind: 'axial',
      diameterMm: 114.3,
      takeoutMm: 152.4,
    );
    final body = MaterialItem(
      category: 'FITTING_BODY',
      description: 'fallback',
      quantity: 1,
      endKind: 'nonAxial',
      diameterMm: 114.3,
    );
    final missing = MaterialItem(
      category: 'FITTING_AXIAL',
      description: 'fallback',
      quantity: 2,
      endKind: 'axial',
      diameterMm: 60.3,
      takeoutMm: 76.2,
      libraryEntryMissing: true,
    );

    test('PL', () {
      expect(
        bomLine(axial, english: false),
        'KSZT. - Kształtka osiowa (kolano / trójnik) Ø114.3 · do osi 152.4 mm '
        '— typ nieznany (projekt ze skanu), sprawdź rysunek - 3 szt.',
      );
      expect(
        bomLine(body, english: false),
        'KSZT. - Kształtka z korpusem (kołnierz / zawór / redukcja) Ø114.3 '
        '— typ nieznany (projekt ze skanu), sprawdź rysunek - 1 szt.',
      );
      expect(
        bomLine(missing, english: false),
        'KSZT. - Kształtka osiowa (kolano / trójnik) Ø60.3 · do osi 76.2 mm '
        '— usunięta z biblioteki komponentów - 2 szt.',
      );
    });

    test('EN', () {
      expect(
        bomLine(axial, english: true),
        'FITTING - Axial fitting (elbow / tee) Ø114.3 · C-E 152.4 mm — type '
        'unknown (scanned project), check the drawing - 3 pcs',
      );
      expect(
        bomLine(body, english: true),
        'FITTING - Fitting with body (flange / valve / reducer) Ø114.3 — type '
        'unknown (scanned project), check the drawing - 1 pc',
      );
    });
  });
}
