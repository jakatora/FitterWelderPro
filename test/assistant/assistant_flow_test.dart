// Przepływ „Wykonaj" na prawdziwym SQLite: tekst → (pytanie) → podsumowanie →
// „Zapisz" → rekord w weld_params → „Cofnij" usuwa. Bez „Zapisz" nic się nie
// zapisuje. Mikrofon i czytanie na głos to atrapy (bez platformy), serwer
// wyłączony (engine bez zgody) — zero połączeń.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_engine.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/weld_param.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/screens/consent_screen.dart';
import 'package:cut_list_app/screens/home_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';

import '../support/test_database.dart';
import '../test_prefs.dart';

class _FakeSpeech implements SpeechInput {
  _FakeSpeech({this.supported = true, this.granted = true});

  final bool supported;
  final bool granted;
  int listens = 0;
  AppLanguage? language;
  SpeechResultCallback? _onResult;
  void Function(String?)? _onDone;

  void emit(String text, {bool isFinal = false}) => _onResult!(text, isFinal);
  void fail(String error) {
    final done = _onDone;
    _onDone = null;
    done?.call(error);
  }

  @override
  bool get isSupported => supported;

  @override
  Future<bool> initialize() async => granted;

  @override
  Future<void> listen({
    required AppLanguage language,
    required SpeechResultCallback onResult,
    required void Function(String? error) onDone,
  }) async {
    listens++;
    this.language = language;
    _onResult = onResult;
    _onDone = onDone;
  }

  @override
  Future<void> stop() async {
    final done = _onDone;
    _onDone = null;
    done?.call(null);
  }

  @override
  Future<void> cancel() => stop();
}

class _FakeVoice implements SpeechOutput {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, AppLanguage language) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {}
}

const _spec =
    'Zapisz, że spawam stal nierdzewną, ściankę 2 mm, TIG bez drutu na 60 amperach';

final _clock = DateTime(2026, 9, 25, 14, 3);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<List<WeldParam>> _rows(WidgetTester tester) async =>
    (await tester.runAsync(() => WeldParamDao().listAll()))!;

Future<void> _clearRows(WidgetTester tester) => tester.runAsync(() async {
      final dao = WeldParamDao();
      for (final p in await dao.listAll()) {
        await dao.deleteById(p.id);
      }
    });

Future<void> _pump(
  WidgetTester tester, {
  _FakeSpeech? speech,
  _FakeVoice? voice,
  AssistantChatSender? chatSender,
  AssistantMode mode = AssistantMode.act,
  bool wide = false,
}) async {
  tester.view.physicalSize =
      wide ? const Size(1200, 2600) : const Size(1080, 2400);
  tester.view.devicePixelRatio = wide ? 1.0 : 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(
      home: AiChatScreen(
        initialMode: mode,
        speechInput: speech ?? _FakeSpeech(),
        speechOutput: voice ?? _FakeVoice(),
        engine: AssistantEngine(remoteAllowed: () async => false),
        chatSender: chatSender,
        now: () => _clock,
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _command(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('assistant-command')), text);
  await tester.ensureVisible(find.byKey(const Key('assistant-go')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('assistant-go')));
  await _settle(tester);
}

void main() {
  useTestDatabase();

  setUp(() {
    seedFreshInstall();
    AssistantHistoryStore.instance.resetForTest();
  });

  testWidgets('lokalne DN40 i kontynuacja nie wysyłają pytania na serwer',
      (tester) async {
    var requests = 0;
    await _pump(tester, chatSender: (text, history) async {
      requests++;
      return ChatMessage(role: ChatRole.assistant, text: 'REMOTE');
    });
    await _command(tester, 'Jaka jest średnica rury DN40?');
    expect(find.byKey(const Key('assistant-local-answer')), findsOneWidget);
    expect(find.textContaining('48,3'), findsWidgets);
    expect(find.byKey(const Key('assistant-mode-act')), findsOneWidget);
    expect(requests, 0);
    await _command(tester, 'a dla DN50?');
    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await _settle(tester);
    expect(find.textContaining('60,3'), findsWidgets);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets('odpowiedź DN40 otwiera moduł z wypełnionym filtrem',
      (tester) async {
    await _pump(tester);
    await _command(tester, 'Jaka jest średnica rury DN40?');
    await tester.ensureVisible(find.byKey(const Key('assistant-show-module')));
    await tester.tap(find.byKey(const Key('assistant-show-module')));
    await _settle(tester);
    expect(find.text('DN-MM'), findsOneWidget);
    expect(find.text('48.30'), findsOneWidget);
    expect(find.text('60.30'), findsNothing);
    await tester.pageBack();
    await _settle(tester);
    expect(find.byKey(const Key('assistant-local-answer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets('lokalne pytanie o ściankę dopytuje o DN', (tester) async {
    await _pump(tester);
    await _command(tester, 'Jaka ścianka sch 40?');
    expect(find.byKey(const Key('assistant-local-answer')), findsOneWidget);
    await _command(tester, 'DN50');
    expect(find.textContaining('3,91'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'przykład ze specyfikacji: podsumowanie → Zapisz → rekord → Cofnij usuwa',
      (tester) async {
    await _clearRows(tester);
    await _pump(tester);
    await _command(tester, _spec);

    // Podsumowanie z dokładnymi wartościami — jeszcze nic nie zapisano.
    expect(find.text('Sprawdź i zapisz'), findsOneWidget);
    expect(find.text('Stal nierdzewna (SS)'), findsOneWidget);
    expect(find.text('TIG (141)'), findsOneWidget);
    expect(find.text('bez drutu'), findsOneWidget);
    expect(find.text('2 mm'), findsOneWidget);
    expect(find.text('60 A'), findsOneWidget);
    expect(find.text('nie podano'), findsOneWidget);
    expect(await _rows(tester), isEmpty);

    await tester.tap(find.byKey(const Key('assistant-save')));
    await _settle(tester);

    final rows = await _rows(tester);
    expect(rows, hasLength(1));
    final p = rows.single;
    expect(p.method, 'TIG_AUTOGEN');
    expect(p.baseMaterial, 'SS');
    expect(p.wallThicknessMm, 2.0);
    expect(p.amps, 60.0);
    expect(p.note, startsWith('Asystent (tekst), 2026-09-25 14:03'));
    expect(find.text('Zapisano w „Parametry — rury" → Moje'), findsOneWidget);

    final history = AssistantHistoryStore.instance.entries;
    expect(history, hasLength(1));
    expect(history.single.recordId, p.id);
    expect(history.single.undone, isFalse);

    await tester.tap(find.text('Cofnij'));
    await _settle(tester);
    expect(await _rows(tester), isEmpty);
    expect(AssistantHistoryStore.instance.entries.single.undone, isTrue);

    // Historia pokazuje operację i to, że została cofnięta.
    await tester.tap(find.byTooltip('Historia operacji'));
    await _settle(tester);
    expect(find.text('Zapis parametru — cofnięty'), findsOneWidget);
    expect(find.textContaining('TIG bez drutu · SS · t 2 mm · 60 A'),
        findsOneWidget);
  });

  testWidgets('bez „Zapisz" nic się nie zapisuje; Popraw zwraca polecenie',
      (tester) async {
    await _clearRows(tester);
    await _pump(tester);
    await _command(tester, _spec);
    await tester.tap(find.byKey(const Key('assistant-edit')));
    await _settle(tester);

    expect(await _rows(tester), isEmpty);
    expect(AssistantHistoryStore.instance.entries, isEmpty);
    expect(find.text('Sprawdź i zapisz'), findsNothing);
    final field = tester.widget<TextField>(
        find.byKey(const Key('assistant-command')));
    expect(field.controller!.text, _spec);
  });

  testWidgets('brak ścianki → jedno pytanie → odpowiedź → zapis',
      (tester) async {
    await _clearRows(tester);
    await _pump(tester);
    await _command(tester, 'Zapisz nierdzewka TIG bez drutu 60 A');

    expect(find.byKey(const Key('assistant-question')), findsOneWidget);
    expect(find.text('Jaka grubość ścianki w mm?'), findsOneWidget);
    expect(find.text('Sprawdź i zapisz'), findsNothing);

    await _command(tester, 'dwa milimetry');
    expect(find.text('Sprawdź i zapisz'), findsOneWidget);
    expect(find.text('2 mm'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-save')));
    await _settle(tester);

    final rows = await _rows(tester);
    expect(rows.single.wallThicknessMm, 2.0);
    expect(rows.single.amps, 60.0);
  });

  testWidgets('prąd 5000 A → odmowa, bez podsumowania i zapisu',
      (tester) async {
    await _clearRows(tester);
    await _pump(tester);
    await _command(
        tester, 'Zapisz TIG bez drutu nierdzewka ścianka 2 mm 5000 A');

    expect(find.text('Sprawdź i zapisz'), findsNothing);
    expect(find.byKey(const Key('assistant-notice')), findsOneWidget);
    expect(find.textContaining('5–500 A'), findsOneWidget);
    expect(await _rows(tester), isEmpty);
  });

  testWidgets('nierozpoznane polecenie: podpowiedź i „Zadaj jako pytanie"',
      (tester) async {
    await _pump(tester);
    await _command(tester, 'zrób mi kawę');
    expect(find.textContaining('Nie rozpoznałem polecenia'), findsOneWidget);
    await tester.tap(find.text('Zadaj jako pytanie'));
    await _settle(tester);
    final input = tester.widget<TextField>(
        find.byKey(const Key('assistant-question-input')));
    expect(input.controller!.text, 'zrób mi kawę');
  });

  testWidgets('mikrofon: nasłuch widoczny, transkrypcja edytowalna, notatka „Głosowo"',
      (tester) async {
    await _clearRows(tester);
    final speech = _FakeSpeech();
    await _pump(tester, speech: speech);

    final mic = find.byKey(const Key('assistant-mic'));
    expect(tester.getSize(mic).width, greaterThanOrEqualTo(72));
    await tester.tap(mic);
    await _settle(tester);
    expect(speech.listens, 1);
    expect(speech.language, AppLanguage.pl);
    expect(find.byKey(const Key('assistant-listening')), findsOneWidget);

    speech.emit('Zapisz nierdzewka');
    await tester.pump();
    speech.emit('Zapisz nierdzewka TIG bez drutu ścianka 2 mm 70 A',
        isFinal: true);
    await tester.pump();
    expect(find.text('Zapisz nierdzewka TIG bez drutu ścianka 2 mm 70 A'),
        findsOneWidget);

    // Stop — stan nasłuchu znika, tekst zostaje do poprawki.
    await tester.tap(mic);
    await _settle(tester);
    expect(find.byKey(const Key('assistant-listening')), findsNothing);

    await tester.enterText(find.byKey(const Key('assistant-command')),
        'Zapisz nierdzewka TIG bez drutu ścianka 2 mm 65 A');
    await tester.ensureVisible(find.byKey(const Key('assistant-go')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('assistant-go')));
    await _settle(tester);
    expect(find.text('65 A'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-save')));
    await _settle(tester);
    final rows = await _rows(tester);
    expect(rows.single.amps, 65.0);
    expect(rows.single.note, startsWith('Głosowo, 2026-09-25 14:03'));
    expect(AssistantHistoryStore.instance.entries.single.byVoice, isTrue);
  });

  testWidgets('przerwane rozpoznawanie zachowuje transkrypcję', (tester) async {
    final speech = _FakeSpeech();
    await _pump(tester, speech: speech);
    await tester.tap(find.byKey(const Key('assistant-mic')));
    await _settle(tester);
    speech.emit('Zapisz stal czarna MAG');
    await tester.pump();
    speech.fail('error_network');
    await _settle(tester);
    expect(find.text('Zapisz stal czarna MAG'), findsOneWidget);
    expect(find.textContaining('Rozpoznawanie przerwane'), findsOneWidget);
  });

  testWidgets('brak zgody na mikrofon → komunikat, bez nasłuchu',
      (tester) async {
    final speech = _FakeSpeech(granted: false);
    await _pump(tester, speech: speech);
    await tester.tap(find.byKey(const Key('assistant-mic')));
    await _settle(tester);
    expect(speech.listens, 0);
    expect(find.textContaining('Brak dostępu do mikrofonu'), findsOneWidget);
  });

  testWidgets('platforma bez mowy → mikrofon ukryty, tekst działa',
      (tester) async {
    await _pump(tester, speech: _FakeSpeech(supported: false));
    expect(find.byKey(const Key('assistant-mic')), findsNothing);
    expect(find.byKey(const Key('assistant-command')), findsOneWidget);
  });

  testWidgets('open_tool: „Otwórz moment śrub" otwiera narzędzie bez zapisu',
      (tester) async {
    await _clearRows(tester);
    // Szeroko: pasek tytułu „Moment śrub" przepełnia się przy 432 dp — to
    // osobna usterka ekranu kalkulatora, nie asystenta.
    await _pump(tester, wide: true);
    await _command(tester, 'Otwórz moment śrub');
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
    expect(await _rows(tester), isEmpty);
    expect(AssistantHistoryStore.instance.entries, isEmpty);
  });

  group('tryb „Odpowiedz"', () {
    testWidgets('bez zgody na zasady → ekran zgody, nic nie wysłane',
        (tester) async {
      var sent = 0;
      await _pump(tester,
          mode: AssistantMode.answer,
          chatSender: (t, h) async {
            sent++;
            return ChatMessage(role: ChatRole.assistant, text: 'x');
          });
      await tester.enterText(
          find.byKey(const Key('assistant-question-input')), 'Preheat P91?');
      await tester.tap(find.byKey(const Key('assistant-send')));
      await _settle(tester);
      expect(find.byType(ConsentScreen), findsOneWidget);
      expect(sent, 0);
    });

    testWidgets('ze zgodą: odpowiedź widoczna; czytanie na głos tylko po włączeniu',
        (tester) async {
      seedOnboardedUser();
      final voice = _FakeVoice();
      await _pump(tester,
          mode: AssistantMode.answer,
          voice: voice,
          chatSender: (t, h) async => ChatMessage(
              role: ChatRole.assistant,
              text: 'Odpowiedź: $t',
              kind: AiReplyKind.live));

      await tester.enterText(
          find.byKey(const Key('assistant-question-input')), 'Preheat P91?');
      await tester.tap(find.byKey(const Key('assistant-send')));
      await _settle(tester);
      expect(find.text('Odpowiedź: Preheat P91?'), findsOneWidget);
      expect(voice.spoken, isEmpty, reason: 'domyślnie wyłączone');

      await tester.tap(find.byKey(const Key('assistant-tts-toggle')));
      await _settle(tester);
      expect(AssistantHistoryStore.instance.speakReplies, isTrue);
      await tester.enterText(
          find.byKey(const Key('assistant-question-input')), 'NACE?');
      await tester.tap(find.byKey(const Key('assistant-send')));
      await _settle(tester);
      expect(voice.spoken, ['Odpowiedź: NACE?']);
    });
  });

  testWidgets('ekran główny ma kafel ASYSTENT, który otwiera asystenta',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: HomeScreen()),
    ));
    await _settle(tester);
    expect(find.text('ASYSTENT'), findsOneWidget);
    await tester.tap(find.text('ASYSTENT'));
    await _settle(tester);
    expect(find.byType(AiChatScreen), findsOneWidget);
    // Bez Premium i bez zgody — tryb „Wykonaj" gotowy od razu.
    expect(find.byKey(const Key('assistant-command')), findsOneWidget);
  });
}
