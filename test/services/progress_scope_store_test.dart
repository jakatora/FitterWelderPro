import 'dart:async';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/progress/progress_forecast.dart';
import 'package:cut_list_app/services/progress_scope_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _UnpersistedDisk extends InMemorySharedPreferencesStore {
  _UnpersistedDisk() : super.empty();
  bool refuse = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async => !refuse;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('opóźnione konto nie przywraca starszego zakresu', () async {
    SharedPreferences.setMockInitialValues({});
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>(), release = Completer<void>();
    var calls = 0;
    final store = ProgressScopeStore(captureOwner: () async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return owner;
    });
    final older = store.save('P', 'T', const ProgressScope(total: 100));
    await entered.future;
    final newer = store.save('P', 'T', const ProgressScope(total: 200));
    final reading = store.load('P', 'T');
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([older, newer]);
    expect((await reading).total, 200);
    expect((await store.load('P', 'T')).total, 200);
  });
  for (final refuse in [true, false]) {
    test('nieutrwalony zakres jest błędem (odmowa: $refuse)', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _UnpersistedDisk()
        ..refuse = refuse;
      await expectLater(
          const ProgressScopeStore()
              .save('P', 'T', const ProgressScope(total: 100)),
          throwsStateError);
    });
  }
}
