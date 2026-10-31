import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/domain/fume/fume_inputs.dart';
import 'package:cut_list_app/features/fume/fume_input_store.dart';

class _Disk extends InMemorySharedPreferencesStore {
  _Disk() : super.empty();
  bool refuse = false;
  bool pretend = false;
  bool failRead = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (refuse) return false;
    if (pretend) return true;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (failRead) throw StateError('disk unavailable');
    return super.getAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = FumeInputStore();

  test('opóźnione ustalenie właściciela nie odwraca kolejności zmian',
      () async {
    SharedPreferences.setMockInitialValues({});
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final delayed = FumeInputStore(captureOwner: () async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return owner;
    });
    final older = delayed.save(const FumeInputs(flow: 500));
    await entered.future;
    final newer = delayed.save(const FumeInputs(flow: 900));
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([older, newer]);
    expect((await store.load()).inputs.flow, 900);
  });

  test('pozorny sukces zapisu jest wykrywany, poprzednie dane zostają',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk();
    SharedPreferencesStorePlatform.instance = disk;
    await store.save(const FumeInputs(flow: 500));
    disk.pretend = true;
    await expectLater(
        store.save(const FumeInputs(flow: 900)), throwsStateError);
    expect((await store.load()).inputs.flow, 500);
  });

  test('odmowa zapisu nie udaje trwałego zapamiętania przepływu', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk();
    SharedPreferencesStorePlatform.instance = disk;
    await store.save(const FumeInputs(flow: 500));
    disk.refuse = true;
    await expectLater(
        store.save(const FumeInputs(flow: 900)), throwsStateError);
    expect((await store.load()).inputs.flow, 500);
  });

  test('awaria odczytu nie jest oznaczana jako poprawny pusty zapis', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _Disk();
    SharedPreferencesStorePlatform.instance = disk;
    await store.save(const FumeInputs(flow: 500));
    disk.failRead = true;
    final loaded = await store.load();
    expect(loaded.readFailed, isTrue);
    expect(loaded.corrupt, isTrue);
  });
}
