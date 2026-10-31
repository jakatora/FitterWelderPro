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
}
