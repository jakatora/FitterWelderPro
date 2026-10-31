import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_store.dart';
import 'package:cut_list_app/services/ferrite_pmi_backup.dart';
import 'package:cut_list_app/services/owned_prefs.dart';
import '../support/test_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await seedGuestAccount();
  });

  test('rejects arbitrary settings, owner suffixes and unsupported values', () {
    for (final key in [
      'auth_token',
      'consent',
      'premium',
      '${FerritePmiStore.key}.owner.other'
    ]) {
      expect(
          () => FerritePmiBackup.decode(utf8.encode(jsonEncode({key: true}))),
          throwsFormatException);
    }
    for (final value in [
      {},
      [12],
      [
        ['nested']
      ]
    ]) {
      expect(
          () => FerritePmiBackup.decode(
              utf8.encode(jsonEncode({FerritePmiStore.key: value}))),
          throwsFormatException);
    }
  });

  test('retains raw damaged values and can compensate after a session change',
      () async {
    final original = {
      FerritePmiStore.key: false,
      FerritePmiStore.corruptBackupKey: ['original', 'bytes'],
      FerritePmiStore.corruptLastBackupKey: 12,
    };
    SharedPreferences.setMockInitialValues(original);
    final snapshot =
        await FerritePmiBackup.capture(await LocalRecordOwner.capture());
    await snapshot.apply({FerritePmiStore.key: '[]'});
    await seedSignedInAccount();
    final otherOwner = await OwnedPrefs.instance();
    await otherOwner.setString(FerritePmiStore.key, 'other account history');
    await expectLater(snapshot.apply({}), throwsException);
    await snapshot.rollback();
    final prefs = await SharedPreferences.getInstance();
    for (final e in original.entries) {
      expect(prefs.get(e.key), e.value);
    }
    expect(otherOwner.getString(FerritePmiStore.key), 'other account history');
  });
}
