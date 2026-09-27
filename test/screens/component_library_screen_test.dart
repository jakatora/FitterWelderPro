// Ekran biblioteki komponentów: poprawianie, usuwanie z ochroną, filtr.
//
// Było: lista tylko do odczytu (kopiowanie), dialog dodawania kończył się
// „Nie udało się zapisać (możliwy duplikat)” przy poprawionej redukcji, a
// pomoc obiecywała edycję dotknięciem, usuwanie przesunięciem i filtr —
// żadnej z tych rzeczy nie było.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/screens/component_library_screen.dart';
import 'package:cut_list_app/widgets/help_button.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

LibraryComponent _reducer({double length = 0}) => LibraryComponent(
      id: 'red',
      materialGroup: 'SS',
      type: 'REDUCER',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      axisMm: null,
      lengthMm: length,
      measurementMode: 'FACE',
      diameterOutMm: 60.3,
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 120 && !done(); i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

  setUp(() async {
    final db = await AppDatabase.get();
    await db.delete('component_library');
    await db.delete('segments');
  });

  test('pomoc opisuje to, co jest: kosz zamiast przesunięcia', () {
    final pl = kHelpComponentLibrary.stepsPl.map((s) => s.text).join('\n');
    expect(pl, isNot(contains('Przesuń w lewo')));
    expect(pl, contains('kosza'));
    expect(pl, contains('wyszukiwania'));
  });

  test('filtr: typ i średnica z przecinkiem', () {
    final red = _reducer();
    expect(libraryEntryMatches(red, 'reducer 114,3'), isTrue);
    expect(libraryEntryMatches(red, 'elb'), isFalse);
    expect(libraryEntryMatches(red, ''), isTrue);
  });

  testWidgets('dotknięcie wpisu → poprawka H redukcji zapisuje się',
      (tester) async {
    await tester.runAsync(() => ComponentLibraryDao().insert(_reducer()));
    await tester.pumpWidget(_wrap(const ComponentLibraryScreen()));
    await _pumpUntil(tester,
        () => find.byKey(const ValueKey('library-red')).evaluate().isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('library-red')));
    await tester.pumpAndSettle();
    expect(find.text('Edit component'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lib-length')), '102');
    await tester.tap(find.text('Save'));
    await _pumpUntil(tester, () => find.byType(ComponentEditDialog).evaluate().isEmpty);

    final back = await tester.runAsync(() => ComponentLibraryDao().getById('red'));
    expect(back!.lengthMm, 102);
  });

  testWidgets('dodanie tej samej redukcji: zamiast błędu — popraw istniejący',
      (tester) async {
    await tester.runAsync(() => ComponentLibraryDao().insert(_reducer()));
    await tester.pumpWidget(_wrap(const ComponentLibraryScreen()));
    await _pumpUntil(tester,
        () => find.byKey(const ValueKey('library-red')).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip('Add component'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ELB90 (axial)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REDUCER (length H)').last);
    await tester.pumpAndSettle();
    // Wpisane odwrotnie (mały koniec pierwszy) — to ta sama kształtka.
    await tester.enterText(find.byKey(const ValueKey('lib-diameter')), '60,3');
    await tester.enterText(find.byKey(const ValueKey('lib-diameter-out')), '114,3');
    await tester.enterText(find.byKey(const ValueKey('lib-wall')), '3,05');
    await tester.enterText(find.byKey(const ValueKey('lib-length')), '102');
    await tester.tap(find.text('Save'));
    await _pumpUntil(tester,
        () => find.byKey(const ValueKey('lib-overwrite')).evaluate().isNotEmpty);

    await tester.ensureVisible(find.byKey(const ValueKey('lib-overwrite')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lib-overwrite')));
    await _pumpUntil(tester, () => find.byType(ComponentEditDialog).evaluate().isEmpty);

    final all = await tester.runAsync(() => ComponentLibraryDao().listAll());
    expect(all, hasLength(1), reason: 'nie powstał drugi wpis');
    expect(all!.single.id, 'red');
    expect(all.single.lengthMm, 102);
    expect(all.single.diameterMm, 114.3, reason: 'duży koniec pierwszy');
    expect(all.single.diameterOutMm, 60.3);
  });

  testWidgets('wpisu użytego w segmencie nie da się usunąć', (tester) async {
    await tester.runAsync(() async {
      await ComponentLibraryDao().insert(_reducer(length: 102));
      final db = await AppDatabase.get();
      await db.insert('segments', {
        'id': 'seg-red',
        'project_id': 'p-lib',
        'seq_no': 4,
        'diameter_mm': 114.3,
        'wall_thickness_mm': 3.05,
        'start_kind': 'logical',
        'start_library_id': null,
        'start_value_mm': 0.0,
        'end_kind': 'nonAxial',
        'end_library_id': 'red',
        'end_value_mm': 102.0,
        'iso_ref': 'OPEN|FACE_FAR',
        'iso_expr': '1000',
        'iso_mm': 1000.0,
        'cut_mm': 898.0,
        'created_at': 1,
        'updated_at': 1,
      });
    });
    await tester.pumpWidget(_wrap(const ComponentLibraryScreen()));
    await _pumpUntil(tester,
        () => find.byKey(const ValueKey('library-red')).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await _pumpUntil(
        tester, () => find.text('The entry is in use').evaluate().isNotEmpty);
    expect(find.textContaining('S04'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final still = await tester.runAsync(() => ComponentLibraryDao().getById('red'));
    expect(still, isNotNull);
  });
}
