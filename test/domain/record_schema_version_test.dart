import 'dart:convert';

import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/features/spool_check/spool_check_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final readers = <String, (int, bool) Function(List<Object?>)>{
    'hot work': (raw) {
      final parsed = hotWorkPermitsParse(raw);
      return (parsed.permits.length, parsed.damaged);
    },
    'confined space': (raw) {
      final parsed = confinedSpaceRecordsFromJson(raw);
      return (parsed.records.length, parsed.damaged);
    },
    'spool check': (raw) {
      final parsed = spoolChecksParse(raw);
      return (parsed.checks.length, parsed.damaged);
    },
  };
  for (final reader in readers.entries) {
    group(reader.key, () {
      final current = <String, Object?>{
        'v': 1,
        'id': 'current',
        'date': '2026-10-31',
        'set': 'pfiEs3',
      };
      test('current and legacy records remain readable', () {
        final legacy = {...current, 'id': 'legacy'}..remove('v');
        expect(reader.value([current, legacy]), (2, false));
      });
      for (final version in <Object?>[2, 0, -1, '1', true, null]) {
        test('unsupported schema $version is not evaluated as current', () {
          final future = {...current, 'id': 'future', 'v': version};
          // Keep the known record and mark the history for raw recovery.
          expect(reader.value([current, future]), (1, true));
        });
      }
    });
  }
  final stores = <(String, String, Future<(int, bool, bool)> Function())>[
    (
      HotWorkStore.key,
      HotWorkStore.corruptBackupKey,
      () async {
        final report = await const HotWorkStore().loadReport();
        return (report.permits.length, report.damaged, report.backupFailed);
      }
    ),
    (
      ConfinedSpaceStore.key,
      ConfinedSpaceStore.corruptBackupKey,
      () async {
        final report = await const ConfinedSpaceStore().load();
        return (report.records.length, report.damaged, report.backupFailed);
      }
    ),
    (
      SpoolCheckStore.key,
      SpoolCheckStore.corruptBackupKey,
      () async {
        final report = await SpoolCheckStore().loadReport();
        return (report.checks.length, report.damaged, report.backupFailed);
      }
    ),
  ];
  for (final (key, backupKey, load) in stores) {
    test('$key keeps the exact raw future record in recovery', () async {
      final current = {
        'v': 1,
        'id': 'known',
        'date': '2026-10-31',
        'set': 'pfiEs3',
      };
      final raw = jsonEncode([
        current,
        {
          ...current,
          'v': 2,
          'id': 'future',
          'newField': {
            'keep': [1, 'x']
          }
        },
      ]);
      SharedPreferences.setMockInitialValues({key: raw});
      expect(await load(), (1, true, false));
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(key), raw);
      expect(prefs.getString(backupKey), raw);
      expect(await load(), (1, true, false));
      expect(prefs.getString(backupKey), raw);
    });
  }
}
