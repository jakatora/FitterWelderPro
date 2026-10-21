import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/own_data/certificates_expiry_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

WelderCertificate cert(String id,
        {String? stamp = 'PW01',
        String process = '141',
        QualificationStandard standard = QualificationStandard.iso9606_1,
        DateTime? test,
        DateTime? expiry}) =>
    WelderCertificate(
        id: id,
        certNo: id,
        standard: standard,
        welderStamp: stamp,
        processes: process,
        testDate: test,
        expiryDate: expiry,
        createdAt: 1,
        updatedAt: 1);

void main() {
  useTestDatabase();
  final today = DateTime(2026, 10, 19);
  final dao = WelderCertificateDao();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'welder_identity_v1': jsonEncode({
        'stamp': 'PW01',
        'gdprConsentAt': '2026-01-01T00:00:00',
        'qualificationDeclaredAt': '2026-01-01T00:00:00',
      }),
    });
    final db = await AppDatabase.get();
    await db.delete('welder_cert_confirmations');
    await db.delete('welder_certificates');
    await db.delete('weld_journal');
  });

  Future<AnswerResult> ask(String text,
      {AppLanguage lang = AppLanguage.pl}) async {
    final h = BrainHarness(
        lang: lang,
        certificates: (asOf) =>
            readLocalCertificateEvaluations(asOf, ownerStamp: 'PW01'));
    final response = await h.say(text);
    expect(response.match?.skill.id, 'certs.expiry');
    return response.result as AnswerResult;
  }

  Future<void> confirm(String id, String date) =>
      dao.addConfirmation(CertificateConfirmation(
          id: '$id-$date',
          certificateId: id,
          date: DateTime.parse(date),
          createdAt: 1));

  test('future expiry does not hide a broken ISO confirmation chain', () async {
    await dao.upsert(cert('ISO-LATE',
        test: DateTime(2026, 1, 1), expiry: DateTime(2028, 1, 1)));
    await confirm('ISO-LATE', '2026-08-01');
    final db = await AppDatabase.get();
    final before = await db.query('welder_certificates');
    final history = await db.query('welder_cert_confirmations');
    final result = await ask('kiedy wygasa moje uprawnienie 141?');
    expect(result.answer.lines.first.value, contains('2028-01-01'));
    expect(result.answer.lines.first.value,
        contains('Termin ciągłości przekroczony'));
    expect(result.answer.lines[1].value, 'Potwierdzenie: 2026-07-01');
    expect(result.answer.lines[2].value, contains('Nie przywraca ciągłości'));
    expect(await db.query('welder_certificates'), before);
    expect(await db.query('welder_cert_confirmations'), history);
    expect(await db.query('weld_journal'), isEmpty);
  });

  test('history and stamp filtering use the existing qualification domain',
      () async {
    await dao.upsert(cert('OWNER',
        test: DateTime(2026, 1, 1), expiry: DateTime(2027, 1, 1)));
    await confirm('OWNER', '2026-06-30');
    await dao.upsert(
        cert('OTHER-PERSON', stamp: 'PW02', test: DateTime(2026, 1, 1)));
    await dao.upsert(cert('LEGACY-OWNER', stamp: null, process: '111'));
    final all =
        await readLocalCertificateEvaluations(today, ownerStamp: 'PW01');
    expect(all.map((e) => e.certificate.id).toSet(), {'OWNER', 'LEGACY-OWNER'});
    expect(
        all.singleWhere((e) => e.certificate.id == 'OWNER').continuityDeadline,
        DateTime(2026, 12, 30));
    final unknownOwner =
        await readLocalCertificateEvaluations(today, ownerStamp: null);
    expect(unknownOwner.map((e) => e.certificate.id), ['LEGACY-OWNER']);
    final result = await ask('Do kiedy ważne moje uprawnienie TIG?');
    expect(result.answer.lines[1].value, 'Potwierdzenie: 2026-12-30');
    expect(result.answer.text.pl, contains('2026-10-19'));
    expect(result.show?.toolId, 'welder_certificates');
    expect(result.show?.fields, isEmpty);
  });

  test('ASME uses only matching owner journal welds up to the assessment date',
      () async {
    await dao.upsert(cert('ASME',
        standard: QualificationStandard.asmeIx, test: DateTime(2026, 1, 1)));
    final db = await AppDatabase.get();
    for (final row in [
      {'id': 'own', 'date': '2026-06-01', 'method': 'TIG', 'welder': 'PW01'},
      {'id': 'other', 'date': '2026-09-01', 'method': 'TIG', 'welder': 'PW02'},
      {'id': 'future', 'date': '2026-12-01', 'method': 'TIG', 'welder': 'PW01'},
      {
        'id': 'wrong-process',
        'date': '2026-10-01',
        'method': 'MMA',
        'welder': 'PW01'
      },
      {
        'id': 'deleted',
        'date': '2026-10-01',
        'method': 'TIG',
        'welder': 'PW01',
        'deleted_at': 1
      },
    ]) {
      await db.insert('weld_journal', row);
    }
    final e = (await readLocalCertificateEvaluations(today, ownerStamp: 'PW01'))
        .single;
    expect(e.continuityDeadline, DateTime(2026, 12, 1));
    expect(e.lastJournalWeld, DateTime(2026, 6, 1));
    final result = await ask('When does my TIG qualification expire?',
        lang: AppLanguage.en);
    expect(result.answer.lines[1].value, 'Process use: 2026-12-01');
    expect(result.answer.lines.first.value, contains('No recorded date'));
  });

  test(
      'numeric processes are exact; missing and unknown values are not inferred',
      () async {
    await dao.upsert(cert('141-ONLY', process: '141'));
    await dao.upsert(cert('142-ONLY', process: '142'));
    final one = await ask('Kiedy wygasa moje uprawnienie 141?');
    expect(one.answer.lines, hasLength(2));
    expect(one.answer.lines.first.label.pl, contains('141-ONLY'));
    expect(one.answer.lines.first.value, contains('Niepełne dane ciągłości'));
    final family = await ask('Kiedy wygasa moje uprawnienie TIG?');
    expect(family.answer.lines, hasLength(4));
    final unknown = await ask('kiedy wygasa moje uprawnienie 999?');
    expect(unknown.answer.lines, isEmpty);
    expect(unknown.answer.text.pl, contains('Nie znalazłem'));
    await dao
        .upsert(cert('EXPIRED', process: '111', expiry: DateTime(2025, 1, 1)));
    final expired = await ask('kiedy wygasa moje uprawnienie 111?');
    expect(expired.answer.lines.first.value,
        contains('Data ważności przekroczona'));
  });

  test(
      'production reader is fresh and empty data is different from a read error',
      () async {
    final skill = CertificatesExpirySkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(),
        now: () => today);
    final u = Utterance('kiedy wygasa mój certyfikat?', lang: AppLanguage.pl);
    Future<AnswerResult> read() async =>
        await skill.run(skill.match(u, ctx)!, ctx) as AnswerResult;
    expect((await read()).answer.lines, isEmpty);
    await dao.upsert(cert('FRESH', standard: QualificationStandard.other));
    final result = await read();
    expect(result.answer.lines.first.value, contains('Brak wpisanej daty'));
    expect(result.answer.lines[1].value, 'Nieoceniana dla tej normy');
    final broken = BrainHarness(
        certificates: (_) async => throw StateError('secret-path'));
    final failed = (await broken.say('kiedy wygasa mój certyfikat?')).result
        as FailedResult;
    expect(failed.reportMissingCapability, isFalse);
    expect(failed.message.pl, isNot(contains('secret-path')));
  });
}
