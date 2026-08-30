import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/screens/weld_journal_screen.dart';

/// A welder logs ~30 joints a shift, all on the same job, and "Projekt" used
/// to open empty every single time. One retyping slip ("Blok 4" vs "Blok4")
/// forks the status filter, the weld-number suggester and the CSV/PDF export
/// into two projects that no longer reconcile at an audit — which is why the
/// last project is remembered and why the memory is trimmed and clearable.
void main() {
  // SharedPreferences.setMockInitialValues needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a fresh install remembers nothing', () async {
    expect(await loadLastWeldProject(), '');
  });

  test('saved project comes back on the next weld', () async {
    await saveLastWeldProject('SP-001');
    expect(await loadLastWeldProject(), 'SP-001');
  });

  test('the remembered name is trimmed on the way in and out', () async {
    // A trailing space is invisible in the field but makes "SP-001 " a
    // different project to every filter and export in the app.
    await saveLastWeldProject('  SP-002  ');
    expect(await loadLastWeldProject(), 'SP-002');
  });

  test('saving an empty project CLEARS the memory', () async {
    await saveLastWeldProject('SP-003');
    expect(await loadLastWeldProject(), 'SP-003');

    // A welder who deliberately files a weld with no project is telling us the
    // old one no longer applies; pre-filling it again would put a wrong
    // project on the next joint.
    await saveLastWeldProject('');
    expect(await loadLastWeldProject(), '');
  });

  test('a whitespace-only project clears the memory too', () async {
    await saveLastWeldProject('SP-004');
    await saveLastWeldProject('   ');
    expect(await loadLastWeldProject(), '');
  });

  test('the newest project wins', () async {
    await saveLastWeldProject('SP-005');
    await saveLastWeldProject('SP-006');
    expect(await loadLastWeldProject(), 'SP-006');
  });

  test('a value stored by an older build with padding still reads clean',
      () async {
    // Defensive: the key is versioned but the value was written by whatever
    // build ran last, and a padded string must not resurface as a new project.
    SharedPreferences.setMockInitialValues({
      kLastWeldProjectPrefsKey: '  Blok 4 ',
    });
    expect(await loadLastWeldProject(), 'Blok 4');
  });
}
