// Rejestr uprawnień na prawdziwym SQLite: przeniesienie starej tożsamości
// (zero utraty danych), ciągłość z dziennika, „usuń moje dane", kontrola
// spoiny dla dziennika.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/qualification/certificate_status.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/wps/weld_range_check.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/services/welder_identity.dart';
import 'package:cut_list_app/services/welder_qualification_service.dart';

import '../support/test_database.dart';

/// Tożsamość zapisana przez wersję sprzed v21 (klucze JSON bez zmian).
String _legacyIdentityJson({
  String? wpqrNo = 'WPS-2026-014',
  String? wpqrExpiry = '2028-06-09T00:00:00.000Z',
}) =>
    jsonEncode({
      'stamp': 'JK-014',
      'wpqrNo': wpqrNo,
      'wpqrExpiry': wpqrExpiry,
      'certBody': 'udt',
      'displayName': 'Jan Kowalski',
      'email': 'jan@example.pl',
      'gdprConsentAt': '2026-06-09T14:32:00.000',
      'qualificationDeclaredAt': '2026-06-09T14:33:00.000',
    });

Future<void> _clearTables() async {
  final db = await AppDatabase.get();
  await db.delete('welder_certificates');
  await db.delete('wps_library');
  await db.delete('weld_journal');
}

WelderIdentity _identity(String stamp) => WelderIdentity(
      stamp: stamp,
      gdprConsentAt: DateTime(2026, 6, 9),
      qualificationDeclaredAt: DateTime(2026, 6, 9),
    );

void main() {
  useTestDatabase();

  setUp(_clearTables);

  group('przeniesienie starej tożsamości (v21)', () {
    test('numer, data i jednostka trafiają do rejestru; nic nie znika',
        () async {
      SharedPreferences.setMockInitialValues(
          {'welder_identity_v1': _legacyIdentityJson()});
      final prefs = await SharedPreferences.getInstance();
      final db = await AppDatabase.get();

      final migrated = await migrateLegacyQualification(db, prefs,
          now: DateTime(2026, 9, 24), newId: () => 'legacy-1');

      expect(migrated, isNotNull);
      final rows = await WelderCertificateDao().listAll();
      expect(rows, hasLength(1));
      final c = rows.single;
      expect(c.id, 'legacy-1');
      expect(c.certNo, 'WPS-2026-014');
      expect(c.expiryDate, DateTime(2028, 6, 9));
      expect(c.examiner, 'UDT');
      expect(c.welderStamp, 'JK-014');
      expect(c.standard, QualificationStandard.iso9606_1);
      expect(c.notes, contains('Przeniesione'));

      // Zero utraty danych: tożsamość w preferencjach dokładnie taka sama —
      // stempel (czytany przez dziennik spoin) i stare pola zostają.
      expect(prefs.getString('welder_identity_v1'), _legacyIdentityJson());
      expect(prefs.getBool(kLegacyCertMigratedPrefsKey), isTrue);
    });

    test('drugi raz nic nie dopisuje, usunięty wpis nie wraca', () async {
      SharedPreferences.setMockInitialValues(
          {'welder_identity_v1': _legacyIdentityJson()});
      final prefs = await SharedPreferences.getInstance();
      final db = await AppDatabase.get();

      await migrateLegacyQualification(db, prefs);
      expect(await migrateLegacyQualification(db, prefs), isNull);
      expect(await WelderCertificateDao().count(), 1);

      final only = (await WelderCertificateDao().listAll()).single;
      await WelderCertificateDao().delete(only.id);
      expect(await migrateLegacyQualification(db, prefs), isNull);
      expect(await WelderCertificateDao().count(), 0);
    });

    test('rejestr już niepusty (np. z kopii) — bez duplikatu', () async {
      SharedPreferences.setMockInitialValues(
          {'welder_identity_v1': _legacyIdentityJson()});
      final prefs = await SharedPreferences.getInstance();
      final db = await AppDatabase.get();
      await WelderCertificateDao().upsert(const WelderCertificate(
        id: 'restored',
        standard: QualificationStandard.iso9606_1,
        certNo: 'WPS-2026-014',
        createdAt: 1,
        updatedAt: 1,
      ));

      expect(await migrateLegacyQualification(db, prefs), isNull);
      expect((await WelderCertificateDao().listAll()).map((c) => c.id),
          ['restored']);
      expect(prefs.getBool(kLegacyCertMigratedPrefsKey), isTrue);
    });

    for (final (name, seed) in <(String, Map<String, Object>)>[
      ('brak tożsamości', <String, Object>{}),
      (
        'tożsamość bez numeru i daty',
        {'welder_identity_v1': _legacyIdentityJson(wpqrNo: null, wpqrExpiry: null)}
      ),
      ('zepsuty JSON', {'welder_identity_v1': '{nie json'}),
    ]) {
      test('nic do przeniesienia: $name', () async {
        SharedPreferences.setMockInitialValues(seed);
        final prefs = await SharedPreferences.getInstance();
        final db = await AppDatabase.get();
        expect(await migrateLegacyQualification(db, prefs), isNull);
        expect(await WelderCertificateDao().count(), 0);
        expect(prefs.getBool(kLegacyCertMigratedPrefsKey), isTrue);
      });
    }

    test('sama data bez numeru też jest przenoszona', () async {
      SharedPreferences.setMockInitialValues({
        'welder_identity_v1':
            _legacyIdentityJson(wpqrNo: '', wpqrExpiry: '2027-01-31T00:00:00.000')
      });
      final prefs = await SharedPreferences.getInstance();
      final migrated =
          await migrateLegacyQualification(await AppDatabase.get(), prefs);
      expect(migrated!.certNo, isNull);
      expect(migrated.expiryDate, DateTime(2027, 1, 31));
    });

    test('serwis przenosi przy pierwszym odczycie rejestru', () async {
      SharedPreferences.setMockInitialValues(
          {'welder_identity_v1': _legacyIdentityJson()});
      final list =
          await WelderQualificationService.instance.listCertificates();
      expect(list.single.certNo, 'WPS-2026-014');
    });
  });

  group('ciągłość z dziennika spoin (tylko odczyt)', () {
    Future<void> journal(String welder, String date, String method) async {
      final db = await AppDatabase.get();
      await db.insert('weld_journal', <String, Object?>{
        'id': '$welder-$date-$method',
        'weld_no': 'W',
        'welder': welder,
        'date': date,
        'method': method,
      });
    }

    test('czyta tylko spoiny tego spawacza, z poprawną datą', () async {
      await journal('JK-014', '2026-05-20', 'TIG');
      await journal('jk-014', '01.06.2026', 'MMA');
      await journal('AB-001', '2026-09-01', 'TIG'); // cudza
      await journal('JK-014', 'wczoraj', 'TIG'); // nieczytelna data
      final welds = await WelderQualificationService.instance
          .readJournalWelds(stamp: 'JK-014', today: DateTime(2026, 9, 24));
      expect(welds.map((w) => w.date).toList()..sort(),
          [DateTime(2026, 5, 20), DateTime(2026, 6, 1)]);
    });

    test('refresh: WPQ ASME utrzymane spoiną TIG z dziennika', () async {
      SharedPreferences.setMockInitialValues(
          {kLegacyCertMigratedPrefsKey: true});
      await WelderIdentityService.instance.save(_identity('JK-014'));
      await WelderCertificateDao().upsert(WelderCertificate(
        id: 'asme',
        standard: QualificationStandard.asmeIx,
        testDate: DateTime(2025, 12, 1),
        processes: 'GTAW',
        createdAt: 1,
        updatedAt: 1,
      ));
      await journal('JK-014', '2026-05-20', 'TIG');

      final overview = await WelderQualificationService.instance
          .refresh(now: DateTime(2026, 9, 24));
      final e = overview.evaluations.single;
      expect(e.continuityDeadline, DateTime(2026, 11, 20));
      expect(e.lastJournalWeld, DateTime(2026, 5, 20));
      expect(e.state, QualificationState.valid);
      expect(WelderQualificationService.instance.overview.value, overview);
    });
  });

  test('„Usuń moje dane" (WelderIdentityService.clear) czyści rejestr',
      () async {
    SharedPreferences.setMockInitialValues({kLegacyCertMigratedPrefsKey: true});
    await WelderIdentityService.instance.save(_identity('JK-014'));
    await WelderCertificateDao().upsert(const WelderCertificate(
      id: 'x',
      standard: QualificationStandard.iso9606_1,
      certNo: 'PL-1',
      createdAt: 1,
      updatedAt: 1,
    ));

    await WelderIdentityService.instance.clear();

    expect(await WelderCertificateDao().count(), 0);
    expect(WelderIdentityService.instance.current, isNull);
    expect(WelderQualificationService.instance.overview.value!.evaluations,
        isEmpty);
  });

  test('checkWeld: WPS z biblioteki po numerze + uprawnienia w dniu spoiny',
      () async {
    SharedPreferences.setMockInitialValues({kLegacyCertMigratedPrefsKey: true});
    await WelderIdentityService.instance.save(_identity('JK-014'));
    await WpsDao().upsert(const WpsRecord(
      id: 'wps-1',
      wpsNo: 'WPS-141-01',
      processes: '141',
      thicknessMinMm: 1.5,
      thicknessMaxMm: 6,
      createdAt: 1,
      updatedAt: 1,
    ));
    await WelderCertificateDao().upsert(WelderCertificate(
      id: 'iso',
      welderStamp: 'JK-014',
      standard: QualificationStandard.iso9606_1,
      testDate: DateTime(2026, 6, 1),
      processes: '141',
      thicknessMinMm: 1,
      thicknessMaxMm: 10,
      createdAt: 1,
      updatedAt: 1,
    ));

    final ok = await WelderQualificationService.instance.checkWeld(
      weld: WeldParameters(
        thicknessMm: WeldParameters.parseNumber('2,77'),
        process: 'TIG',
      ),
      weldDate: DateTime(2026, 9, 24),
      wpsNo: ' wps-141-01 ',
    );
    expect(ok.wps?.id, 'wps-1');
    expect(ok.wpsIssues, isEmpty);
    expect(ok.welder.covered, isTrue);
    expect(ok.hasWarnings, isFalse);

    final bad = await WelderQualificationService.instance.checkWeld(
      weld: const WeldParameters(thicknessMm: 8, process: 'TIG'),
      weldDate: DateTime(2026, 12, 15), // po terminie 6 mies. (2026-12-01)
      wpsId: 'wps-1',
    );
    expect(bad.wpsIssues.single.field, WeldCheckField.thickness);
    expect(bad.welder.covered, isFalse);
    expect(bad.hasWarnings, isTrue);
  });
}
