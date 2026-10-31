import 'dart:convert';

import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/features/spool_check/spool_check_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = <(String, String, String, Future<void> Function(), Matcher)>[
    (
      HotWorkStore.key,
      HotWorkStore.corruptBackupKey,
      HotWorkStore.corruptLastBackupKey,
      () async => const HotWorkStore().upsert(
          HotWorkPermit.blank(id: 'new', now: DateTime(2026, 10, 31))
              .copyWith(location: 'New location')),
      isA<StateError>(),
    ),
    (
      ConfinedSpaceStore.key,
      ConfinedSpaceStore.corruptBackupKey,
      ConfinedSpaceStore.corruptLastBackupKey,
      () async => const ConfinedSpaceStore().upsert(
          ConfinedSpaceRecord.blank(id: 'new', now: DateTime(2026, 10, 31))
              .copyWith(location: 'New location')),
      isA<StateError>(),
    ),
    (
      SpoolCheckStore.key,
      SpoolCheckStore.corruptBackupKey,
      SpoolCheckStore.corruptLastBackupKey,
      () async => SpoolCheckStore().upsert(const SpoolCheck(
          id: 'new', date: '2026-10-31', spoolNo: 'New spool')),
      isA<SpoolCheckStoreUnavailable>(),
    ),
  ];
  final raw = jsonEncode([
    {'v': 1, 'id': 'known', 'date': '2026-10-31', 'set': 'pfiEs3'},
    {
      'v': 2,
      'id': 'future',
      'date': '2026-10-31',
      'unknown': {
        'values': [42, 'keep exactly']
      },
    },
  ]);
  for (final (key, first, last, write, failure) in cases) {
    test('$key preserves future raw before writing known records', () async {
      SharedPreferences.setMockInitialValues({key: raw});
      await write();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(first), raw);
      expect(prefs.get(last), isNull);
      final records = jsonDecode(prefs.getString(key)!) as List;
      expect(records.map((e) => e['id']), unorderedEquals(['known', 'new']));
      expect(records.every((e) => e['v'] == 1), isTrue);
    });
    test('$key refuses writing when both recovery copies are occupied',
        () async {
      SharedPreferences.setMockInitialValues({
        key: raw,
        first: 'previous original A',
        last: 'previous original B',
      });
      await expectLater(write(), throwsA(failure));
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(key), raw);
      expect(prefs.getString(first), 'previous original A');
      expect(prefs.getString(last), 'previous original B');
    });
  }
}
