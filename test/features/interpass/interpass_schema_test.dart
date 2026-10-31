import 'dart:convert';

import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_account.dart';

void main() {
  useGuestAccount();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final version in <Object?>[3, 0, -1, '2', true, null]) {
    test('unknown interpass schema $version is rejected', () {
      expect(() => interpassLogFromJson({'v': version, 'welds': []}),
          throwsFormatException);
    });
  }
  test('both supported versions and legacy remain readable', () {
    for (final version in [1, 2, 1.0, 2.0]) {
      expect(interpassLogFromJson({'v': version, 'welds': []}).lossy, isFalse);
    }
    expect(interpassLogFromJson({'welds': []}).lossy, isFalse);
  });
  final weld = InterpassWeld(
    id: 'known',
    weldNo: 'S-1',
    limits: InterpassLimits.celsius(preheatMinC: 100, interpassMaxC: 250),
    readings: const [
      InterpassReading(
          pass: 1, temp: InterpassTemp.c(120), at: 1000, recordedAt: 1000),
    ],
    createdAt: 1,
    updatedAt: 1,
  );
  final raw = jsonEncode({
    ...interpassLogToJson([weld]),
    'v': 3,
    'future': {
      'keep': [42, 'original']
    }
  });
  test('future log is backed up intact and is not evaluated', () async {
    SharedPreferences.setMockInitialValues({InterpassStore.key: raw});
    final report = await const InterpassStore().load();
    expect(report.welds, isEmpty);
    expect(report.corrupt, isTrue);
    expect(report.backupFailed, isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(InterpassStore.key), raw);
    expect(prefs.getString(InterpassStore.corruptBackupKey), raw);
  });
  test('writing a new weld preserves the complete future log first', () async {
    SharedPreferences.setMockInitialValues({InterpassStore.key: raw});
    final replacement = InterpassWeld.fromJson(
        {...weld.toJson(), 'id': 'new', 'weldNo': 'New weld'})!;
    await const InterpassStore().upsert(replacement);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(InterpassStore.corruptBackupKey), raw);
    final parsed =
        interpassLogFromJson(jsonDecode(prefs.getString(InterpassStore.key)!));
    expect(parsed.lossy, isFalse);
    expect(parsed.welds.map((w) => w.id), ['new']);
  });
  test('occupied recovery slots block writing without losing any original',
      () async {
    final copies = {
      for (final key in InterpassStore.corruptBackupKeys)
        key: 'previous original $key',
    };
    SharedPreferences.setMockInitialValues(
        {InterpassStore.key: raw, ...copies});
    await expectLater(const InterpassStore().upsert(weld),
        throwsA(isA<InterpassStoreUnavailable>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(InterpassStore.key), raw);
    for (final entry in copies.entries) {
      expect(prefs.getString(entry.key), entry.value);
    }
    final report = await const InterpassStore().load();
    expect(report.corrupt, isTrue);
    expect(report.backupFailed, isTrue);
  });
  test('assistant cannot replace a weld inside an unknown schema', () async {
    SharedPreferences.setMockInitialValues({InterpassStore.key: raw});
    expect(
        await const InterpassStore().replaceIfUnchanged(
            weld, weld.copyWith(weldNo: 'Changed by assistant')),
        isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(InterpassStore.key), raw);
    expect(prefs.getString(InterpassStore.corruptBackupKey), raw);
  });
}
