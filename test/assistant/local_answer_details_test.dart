import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/instrument_dao.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/instruments/instrument.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';

import '../support/test_database.dart';
import '../test_prefs.dart';

final now = DateTime(2026, 10, 21, 12);

class _Voice implements SpeechOutput {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, AppLanguage language) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {}
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

Future<void> say(WidgetTester t, String text) async {
  await t.scrollUntilVisible(find.byKey(const Key('assistant-command')), 200,
      scrollable: find.byType(Scrollable).first);
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.scrollUntilVisible(find.byKey(const Key('assistant-go')), 150,
      scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
}

void main() {
  useTestDatabase();
  setUp(() {
    AssistantHistoryStore.instance.resetForTest();
    seedFreshInstall(extra: {
      'assistant_speak_replies_v1': true,
      'welder_identity_v1': jsonEncode({
        'stamp': 'PW01',
        'gdprConsentAt': '2026-01-01T00:00:00',
        'qualificationDeclaredAt': '2026-01-01T00:00:00',
      }),
      kElectrodeBatchesPrefsKey: encodeBatches([
        ElectrodeBatch.takenOut(
            id: 'batch',
            electrode: ElectrodeClass.e7018,
            at: now.subtract(const Duration(hours: 2)),
            location: 'Warsztat'),
      ]),
    });
  });

  test(
      'speech includes all detail values unless a skill supplies tailored wording',
      () {
    const answer =
        AssistantAnswer(text: AssistantText('Wyniki', 'Results'), lines: [
      AnswerLine(AssistantText('Termin', 'Due date'), '2027-04-01'),
      AnswerLine(AssistantText('Wynik', 'Value'), '0 DI'),
    ]);
    expect(answer.speechText(AppLanguage.pl),
        'Wyniki\nTermin: 2027-04-01\nWynik: 0 DI');
    expect(answer.speechText(AppLanguage.en),
        'Results\nDue date: 2027-04-01\nValue: 0 DI');
    const tailored = AssistantAnswer(
        text: AssistantText.same('Intro'),
        spoken: AssistantText('48,3 milimetra', '48.3 millimetres'),
        lines: [AnswerLine(AssistantText.same('OD'), '48.3 mm')]);
    expect(tailored.speechText(AppLanguage.en), '48.3 millimetres');
  });

  for (final lang in AppLanguage.values) {
    testWidgets(
        'real chat displays and speaks own data rows in ${lang.name} on a narrow screen',
        (t) async {
      await t.runAsync(() async {
        final db = await AppDatabase.get();
        for (final table in [
          'welder_cert_confirmations',
          'welder_certificates',
          'instruments',
          'weld_journal_history',
          'weld_repairs',
          'weld_journal'
        ]) {
          await db.delete(table);
        }
        await InstrumentDao().save(const Instrument(
            id: 'gauge',
            name: 'Manometr Wika',
            dueOverride: '2027-04-01',
            createdAt: 1,
            updatedAt: 1));
        await WelderCertificateDao().upsert(WelderCertificate(
            id: 'cert',
            certNo: 'CERT-141',
            welderStamp: 'PW01',
            standard: QualificationStandard.iso9606_1,
            processes: '141',
            testDate: DateTime(2026, 5, 1),
            expiryDate: DateTime(2027, 4, 15),
            createdAt: 1,
            updatedAt: 1));
        await WeldJournalDao().insert(WeldEntry.fromRow({
          'id': 'weld',
          'weld_no': 'W-9',
          'welder': 'PW01',
          'project_name': 'Alfa',
          'date': '2026-10-21',
          'od': '60.3',
          'status': 'PENDING',
        }));
      });
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final voice = _Voice();
      await t.pumpWidget(AppLanguageScope(
          controller: AppLanguageController(lang),
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.3)),
                  child: child!),
              home: AiChatScreen(now: () => now, speechOutput: voice))));
      await settle(t);
      final en = lang == AppLanguage.en;
      final cases = en
          ? [
              ('When is calibration?', 'Manometr Wika', '2027-04-01'),
              ('When does my certificate expire?', 'CERT-141', '2027-04-15'),
              ('My last weld', 'W-9 · Alfa', '2026-10-21'),
              ('My electrode status', 'E7018', 'Remaining 2 h 00 min'),
              ('How many DI today?', 'Your DI share', '2 DI'),
            ]
          : [
              ('Kiedy kalibracja?', 'Manometr Wika', '2027-04-01'),
              ('Kiedy wygasa mój certyfikat?', 'CERT-141', '2027-04-15'),
              ('Ostatnia spoina', 'W-9 · Alfa', '2026-10-21'),
              ('Status moich elektrod', 'E7018', 'Pozostało 2 h 00 min'),
              ('Ile DI dzisiaj?', 'Twój udział DI', '2 DI'),
            ];
      for (final (query, label, value) in cases) {
        await say(t, query);
        final card = find.byKey(const Key('assistant-local-answer'));
        await t.scrollUntilVisible(card, -200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        expect(find.descendant(of: card, matching: find.textContaining(label)),
            findsWidgets,
            reason: query);
        expect(find.descendant(of: card, matching: find.textContaining(value)),
            findsWidgets,
            reason: query);
        expect(voice.spoken.last, contains(label), reason: query);
        expect(voice.spoken.last, contains(value), reason: query);
        expect(t.takeException(), isNull, reason: query);
      }
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    });
  }
}
