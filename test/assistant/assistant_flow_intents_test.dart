// Przepływy asystenta na prawdziwym SQLite (bez serwera, atrapy mowy):
//   • odmowa odpowiedzi na pytanie NIE kasuje polecenia;
//   • pytanie w „Wykonaj" → tryb „Odpowiedz" (nie zapis);
//   • „Odpowiedz" bez zgody → pomoc offline lokalnie, nic nie wysłane;
//   • historia do /ai/chat: ≤ 6 wpisów, bez bieżącego pytania;
//   • „jaki prąd mam zapisany…" → odczyt „Moich parametrów" (bez zapisu);
//   • „dopisz spoinę…" → podsumowanie → „Zapisz" → wpis w dzienniku ze
//     stemplem; bez „Zapisz" nic; zajęty numer → pytanie o inny.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_engine.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/weld_param.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';

import '../support/test_database.dart';
import '../test_prefs.dart';

class _FakeSpeech implements SpeechInput {
  @override
  bool get isSupported => true;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<void> listen({
    required AppLanguage language,
    required SpeechResultCallback onResult,
    required void Function(String? error) onDone,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _FakeVoice implements SpeechOutput {
  @override
  Future<void> speak(String text, AppLanguage language) async {}
  @override
  Future<void> stop() async {}
}

final _clock = DateTime(2026, 9, 25, 14, 3);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  AssistantChatSender? chatSender,
  AssistantMode mode = AssistantMode.act,
  String stamp = 'JK-07',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(
      home: AiChatScreen(
        initialMode: mode,
        speechInput: _FakeSpeech(),
        speechOutput: _FakeVoice(),
        engine: AssistantEngine(remoteAllowed: () async => false),
        chatSender: chatSender,
        now: () => _clock,
        welderStamp: () async => stamp,
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _command(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('assistant-command')), text);
  await tester.tap(find.byKey(const Key('assistant-go')));
  await _settle(tester);
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(
      find.byKey(const Key('assistant-question-input')), text);
  await tester.tap(find.byKey(const Key('assistant-send')));
  await _settle(tester);
}

Future<List<WeldParam>> _params(WidgetTester tester) async =>
    (await tester.runAsync(() => WeldParamDao().listAll()))!;

Future<List<WeldEntry>> _journal(WidgetTester tester, String project) async =>
    (await tester.runAsync(() => WeldJournalDao().listAll()))!
        .where((e) => e.projectName == project)
        .toList();

Future<void> _clearParams(WidgetTester tester) => tester.runAsync(() async {
      final dao = WeldParamDao();
      for (final p in await dao.listAll()) {
        await dao.deleteById(p.id);
      }
    });

ChatMessage _live(String t) =>
    ChatMessage(role: ChatRole.assistant, text: t, kind: AiReplyKind.live);

void main() {
  useTestDatabase();

  setUp(() {
    seedFreshInstall();
    AssistantHistoryStore.instance.resetForTest();
  });

  testWidgets('odmowa odpowiedzi („sześćset") nie kasuje polecenia',
      (tester) async {
    await _clearParams(tester);
    await _pump(tester);
    await _command(tester, 'Zapisz nierdzewka TIG bez drutu 60 A');
    expect(find.text('Jaka grubość ścianki w mm?'), findsOneWidget);

    await _command(tester, 'sześćset');
    // Pytanie zostaje, komunikat o zakresie, nic nie zapisano.
    expect(find.text('Jaka grubość ścianki w mm?'), findsOneWidget);
    expect(find.textContaining('0,3–50 mm'), findsOneWidget);
    expect(find.textContaining('Polecenie zostaje'), findsOneWidget);
    expect(find.text('Sprawdź i zapisz'), findsNothing);

    await _command(tester, '2 mm');
    expect(find.text('Sprawdź i zapisz'), findsOneWidget);
    expect(find.text('60 A'), findsOneWidget);
    expect(find.text('2 mm'), findsOneWidget);
    // „Popraw" oddaje polecenie bez odrzuconej odpowiedzi.
    await tester.tap(find.byKey(const Key('assistant-edit')));
    await _settle(tester);
    final field = tester
        .widget<TextField>(find.byKey(const Key('assistant-command')));
    expect(field.controller!.text,
        'Zapisz nierdzewka TIG bez drutu 60 A, 2 mm');
    expect(await _params(tester), isEmpty);
  });

  testWidgets('pytanie w „Wykonaj" → tryb „Odpowiedz", bez zapisu',
      (tester) async {
    seedOnboardedUser();
    await _clearParams(tester);
    final asked = <String>[];
    await _pump(tester, chatSender: (t, h) async {
      asked.add(t);
      return _live('Około 60–70 A.');
    });
    await _command(tester, 'jaki prąd na TIG nierdzewka 2 mm');
    expect(asked, ['jaki prąd na TIG nierdzewka 2 mm']);
    expect(find.text('Około 60–70 A.'), findsOneWidget);
    expect(find.text('Sprawdź i zapisz'), findsNothing);
    expect(await _params(tester), isEmpty);
  });

  testWidgets('„Odpowiedz" bez zgody → pomoc offline lokalnie, nic nie wysłane',
      (tester) async {
    var sent = 0;
    await _pump(tester, mode: AssistantMode.answer, chatSender: (t, h) async {
      sent++;
      return _live('x');
    });
    await _ask(tester, 'ciężar rury');
    expect(find.byType(ConsentScreen), findsOneWidget);
    // Odmowa zgody (wyjście z ekranu zgody).
    Navigator.of(tester.element(find.byType(ConsentScreen))).pop();
    await _settle(tester);
    expect(sent, 0);
    expect(find.textContaining('Tryb offline'), findsOneWidget);
  });

  testWidgets('historia do /ai/chat: ≤ 6 wpisów, bez bieżącego pytania',
      (tester) async {
    seedOnboardedUser();
    final histories = <List<ChatMessage>>[];
    await _pump(tester, mode: AssistantMode.answer, chatSender: (t, h) async {
      histories.add(h);
      return _live('odp: $t');
    });
    for (var i = 1; i <= 5; i++) {
      await _ask(tester, 'pytanie $i');
    }
    expect(histories.first, isEmpty, reason: 'bez powitania');
    for (var i = 0; i < histories.length; i++) {
      final h = histories[i];
      expect(h.length, lessThanOrEqualTo(kChatHistoryMax));
      expect(h.map((m) => m.text), isNot(contains('pytanie ${i + 1}')));
    }
    expect(histories.last.map((m) => m.text), [
      'pytanie 2', 'odp: pytanie 2', //
      'pytanie 3', 'odp: pytanie 3', //
      'pytanie 4', 'odp: pytanie 4',
    ]);
  });

  testWidgets('„jaki prąd mam zapisany…" → odczyt Moich parametrów',
      (tester) async {
    await _clearParams(tester);
    await tester.runAsync(() => WeldParamDao().insert(const WeldParam(
          id: 'p1',
          method: 'TIG_AUTOGEN',
          baseMaterial: 'SS',
          welderModel: null,
          diameterMm: 0,
          wallThicknessMm: 2,
          electrodeMm: 0,
          torchGasLpm: 0,
          nozzleType: null,
          nozzleSize: null,
          purgeLpm: 0,
          amps: 62,
          outletHoles: null,
          tempo: null,
          note: null,
          createdAt: 1,
          updatedAt: 1,
        )));
    await _pump(tester);
    await _command(tester, 'jaki prąd mam zapisany na nierdzewkę 2 mm');
    expect(find.byKey(const Key('assistant-query-results')), findsOneWidget);
    expect(find.text('TIG bez drutu · SS · t 2 mm · 62 A'), findsOneWidget);
    expect(find.text('Sprawdź i zapisz'), findsNothing);
    expect((await _params(tester)).single.id, 'p1');

    await _command(tester, 'jaki prąd mam zapisany na duplex');
    expect(find.textContaining('Nic nie znalazłem'), findsOneWidget);
  });

  testWidgets('„dopisz spoinę…" → podsumowanie → Zapisz → dziennik ze stemplem',
      (tester) async {
    await _pump(tester);
    await _command(tester, 'dopisz spoinę 12 projekt Asystent A WPS 141-01');
    expect(find.byKey(const Key('assistant-journal-summary')), findsOneWidget);
    expect(find.text('JK-07'), findsOneWidget);
    expect(await _journal(tester, 'Asystent A'), isEmpty);

    await tester.tap(find.byKey(const Key('assistant-journal-save')));
    await _settle(tester);
    final rows = await _journal(tester, 'Asystent A');
    final e = rows.single;
    expect(e.weldNo, '12');
    expect(e.welder, 'JK-07');
    expect(e.wpsRef, '141-01');
    expect(e.status, WeldStatus.pending);
    expect(e.date, '2026-09-25');
    expect(find.textContaining('Dopisano do dziennika'), findsOneWidget);
    final h = AssistantHistoryStore.instance.entries.single;
    expect(h.kind, kIntentAddWeldJournalEntry);
    expect(h.recordId, e.id);

    // Ten sam numer w tym projekcie → nic nie zapisane, pytanie o inny numer.
    await _command(tester, 'dopisz spoinę 12 projekt Asystent A');
    expect(find.textContaining('jest już w projekcie'), findsOneWidget);
    expect(find.text('Jaki numer spoiny?'), findsOneWidget);
    await _command(tester, '13');
    expect(find.byKey(const Key('assistant-journal-summary')), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    // „Popraw" → nic nie zapisano.
    final edit = find.byKey(const Key('assistant-journal-edit'));
    await tester.ensureVisible(edit);
    await _settle(tester);
    expect(edit.hitTestable(), findsOneWidget);
    await tester.tap(edit);
    await _settle(tester);
    expect(find.byKey(const Key('assistant-journal-summary')), findsNothing);
    expect((await _journal(tester, 'Asystent A')).length, 1);
  });

  testWidgets('dziennik: brak projektu → pytanie; „ten sam" = ostatni projekt',
      (tester) async {
    seedFreshInstall(extra: {'weld_journal.last_project_v1': 'Asystent B'});
    await _pump(tester);
    await _command(tester, 'dopisz spoinę 20 do dziennika');
    expect(find.textContaining('Do którego projektu?'), findsOneWidget);
    expect(find.textContaining('Asystent B'), findsOneWidget);
    await _command(tester, 'ten sam');
    expect(find.byKey(const Key('assistant-journal-summary')), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-journal-save')));
    await _settle(tester);
    expect((await _journal(tester, 'Asystent B')).single.weldNo, '20');
  });
}
