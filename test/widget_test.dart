import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/app.dart';

void main() {
  setUpAll(() {
    // HomeScreen instantiates the project DAO which talks to sqflite; in a
    // unit-test environment we need the FFI factory.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app shows the FITTER tile on the home menu', (tester) async {
    await tester.pumpWidget(const CutListApp());
    // Pump a few frames so the async _load() can settle without waiting for
    // every animation (pumpAndSettle would time out on the indeterminate
    // RefreshIndicator).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // FITTER is identical in both PL and EN locales so the test is robust to
    // whichever language the device defaults to.
    expect(find.text('FITTER'), findsOneWidget);
  });
}
