import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/assistant/voice_session.dart';
import 'package:cut_list_app/i18n/app_language.dart';

class FakeInput implements SpeechInput {
  final results = <SpeechResultCallback>[];
  final done = <void Function(String?)>[];
  Completer<bool>? initialization;
  Completer<void>? cancelWait;
  Completer<void>? listenWait;
  int cancels = 0;
  bool failCancel = false;
  bool failListen = false;
  @override
  bool get isSupported => true;
  @override
  Future<bool> initialize() async =>
      await (initialization?.future ?? Future.value(true));
  @override
  Future<void> listen(
      {required AppLanguage language,
      required SpeechResultCallback onResult,
      required void Function(String?) onDone}) async {
    results.add(onResult);
    done.add(onDone);
    await listenWait?.future;
    if (failListen) throw StateError('recognizer failed to start');
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await cancelWait?.future;
    if (failCancel) throw StateError('capture failed to stop');
  }

  @override
  Future<void> stop() async {}
}

class FakeOutput implements SpeechOutput {
  final spoken = <String>[];
  Object? failure;
  Completer<void>? playback;
  int stops = 0;
  Completer<void>? stopWait;
  @override
  Future<void> speak(String text, AppLanguage language) async {
    if (failure != null) throw failure!;
    spoken.add(text);
    await playback?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopWait?.future;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeInput input;
  late FakeOutput output;
  late Completer<String> reply;
  late VoiceSession session;
  late List<String> requests;
  setUp(() {
    input = FakeInput();
    output = FakeOutput()..playback = Completer<void>();
    reply = Completer<String>();
    requests = [];
    session = VoiceSession(
        input: input,
        output: output,
        respond: (text) {
          requests.add(text);
          return reply.future;
        },
        onPhase: (_, __) {},
        onTranscript: (_, __) {});
  });

  test('microphone is shown as starting until listening is ready', () async {
    input.listenWait = Completer<void>();
    final starting = session.start(AppLanguage.pl);
    await flush();
    expect(input.results, hasLength(1));
    expect(session.phase, VoiceSessionPhase.starting);
    input.listenWait!.complete();
    await starting;
    expect(session.phase, VoiceSessionPhase.listening);
    await session.stop();
  });

  test('fatal recognition error closes capture before a new session starts', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    input.done.single('recognizer_error');
    await flush();
    expect(session.phase, VoiceSessionPhase.error);
    expect(input.cancels, 1);

    final restarting = session.start(AppLanguage.pl);
    await flush();
    expect(input.results, hasLength(1));
    input.cancelWait!.complete();
    await restarting;
    expect(input.results, hasLength(2));
    expect(session.phase, VoiceSessionPhase.listening);
    await session.stop();
  });

  test('recognizer start failure also closes capture', () async {
    input.failListen = true;
    await session.start(AppLanguage.pl);
    await flush();
    expect(session.phase, VoiceSessionPhase.error);
    expect(input.cancels, 1);
    expect(requests, isEmpty);
  });

  test('stop during recognition error cleanup leaves the session idle', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    input.done.single('recognizer_error');
    await flush();
    final stopping = session.stop();
    input.cancelWait!.complete();
    await stopping;
    expect(session.phase, VoiceSessionPhase.idle);
    expect(input.cancels, 1);
  });

  test('failed capture cleanup blocks restart until a successful stop', () async {
    await session.start(AppLanguage.pl);
    input.failCancel = true;
    input.done.single('recognizer_error');
    await flush();
    await session.start(AppLanguage.pl);
    expect(session.phase, VoiceSessionPhase.error);
    expect(input.results, hasLength(1));
    input.failCancel = false;
    await session.stop();
    await session.start(AppLanguage.pl);
    expect(session.phase, VoiceSessionPhase.listening);
    expect(input.results, hasLength(2));
    await session.stop();
  });

  test('stop cancels a restart waiting for failed-capture cleanup', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    input.done.single('recognizer_error');
    await flush();
    final restarting = session.start(AppLanguage.pl);
    final stopping = session.stop();
    input.cancelWait!.complete();
    await Future.wait([restarting, stopping]);
    expect(session.phase, VoiceSessionPhase.idle);
    expect(input.results, hasLength(1));
  });

  test('stop during a cleanup retry prevents a new microphone session', () async {
    await session.start(AppLanguage.pl);
    input.failCancel = true;
    input.done.single('recognizer_error');
    await flush();
    input.failCancel = false;
    input.cancelWait = Completer<void>();
    final restarting = session.start(AppLanguage.pl);
    await flush();
    expect(session.phase, VoiceSessionPhase.starting);
    final stopping = session.stop();
    input.cancelWait!.complete();
    await Future.wait([restarting, stopping]);
    expect(input.results, hasLength(1));
    expect(session.phase, VoiceSessionPhase.idle);
    expect(input.cancels, 2);
  });

  test('repeat prompt waits for capture to stop and never submits the partial result', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    input.results.single('niepełne pytanie', false);
    input.done.single('error_no_match');
    await flush();
    expect(output.spoken, isEmpty);
    expect(requests, isEmpty);
    input.cancelWait!.complete();
    await flush();
    expect(output.spoken, ['Nie zrozumiałem wypowiedzi. Powiedz jeszcze raz.']);
    expect(session.phase, VoiceSessionPhase.speaking);
    expect(input.results, hasLength(1));
    output.playback!.complete();
    await flush();
    expect(input.results, hasLength(2));
    expect(session.phase, VoiceSessionPhase.listening);
    await session.stop();
  });

  test('stopping while capture closes suppresses a pending repeat prompt', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    input.results.single('fragment', false);
    input.done.single('error_no_match');
    await flush();
    final stopped = session.stop();
    input.cancelWait!.complete();
    await stopped;
    await flush();
    expect(output.spoken, isEmpty);
    expect(requests, isEmpty);
    expect(session.phase, VoiceSessionPhase.idle);
  });

  test('a final result before listen returns is not overwritten by listening', () async {
    input.listenWait = Completer<void>();
    final starting = session.start(AppLanguage.pl);
    await flush();
    input.results.single('pytanie', true);
    await flush();
    expect(session.phase, VoiceSessionPhase.thinking);
    input.listenWait!.complete();
    await starting;
    expect(session.phase, VoiceSessionPhase.thinking);
    await session.stop();
  });

  test('mute discards late speech and resumes the same conversation', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    final muting = session.mute();
    expect(session.phase, VoiceSessionPhase.muting);
    input.results.single('spóźnione pytanie', true);
    await session.unmute();
    expect(input.results, hasLength(1));
    input.cancelWait!.complete();
    await muting;
    expect(session.phase, VoiceSessionPhase.muted);
    expect(requests, isEmpty);
    await session.unmute();
    expect(session.phase, VoiceSessionPhase.listening);
    expect(input.results, hasLength(2));
    input.results.last('nowe pytanie', true);
    await flush();
    expect(requests, ['nowe pytanie']);
    await session.stop();
  });

  test('mute while the assistant thinks keeps capture off after it speaks', () async {
    await session.start(AppLanguage.pl);
    input.results.single('pytanie', true);
    await flush();
    expect(session.phase, VoiceSessionPhase.thinking);
    expect(session.canToggleMute, isTrue);
    await session.mute();
    expect(session.microphoneMuted, isTrue);
    reply.complete('odpowiedź');
    await flush();
    expect(session.phase, VoiceSessionPhase.speaking);
    output.playback!.complete();
    await flush();
    expect(session.phase, VoiceSessionPhase.muted);
    expect(input.results, hasLength(1));
    await session.unmute();
    expect(session.phase, VoiceSessionPhase.listening);
    expect(input.results, hasLength(2));
    await session.stop();
  });

  test('mute while speaking can be undone before playback ends', () async {
    await session.start(AppLanguage.pl);
    input.results.single('pytanie', true);
    await flush();
    reply.complete('odpowiedź');
    await flush();
    await session.mute();
    expect(session.microphoneMuted, isTrue);
    await session.interrupt();
    expect(output.stops, 0);
    await session.unmute();
    expect(session.microphoneMuted, isFalse);
    output.playback!.complete();
    await flush();
    expect(session.phase, VoiceSessionPhase.listening);
    expect(input.results, hasLength(2));
    await session.stop();
  });

  test('cannot claim muted while stopping the preceding capture is pending', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    input.results.single('pytanie', true);
    await flush();
    expect(session.phase, VoiceSessionPhase.thinking);
    expect(session.canToggleMute, isFalse);
    await session.mute();
    expect(session.microphoneMuted, isFalse);
    input.cancelWait!.complete();
    await flush();
    expect(session.canToggleMute, isTrue);
    await session.stop();
  });

  test('mute failure is reported instead of claiming microphone is muted', () async {
    await session.start(AppLanguage.pl);
    input.failCancel = true;
    await session.mute();
    expect(session.phase, VoiceSessionPhase.error);
    expect(requests, isEmpty);
    input.failCancel = false;
    await session.stop();
  });

  test('stop while microphone is muting prevents restart', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    final muting = session.mute();
    final stopping = session.stop();
    input.cancelWait!.complete();
    await muting;
    await stopping;
    await session.unmute();
    expect(session.phase, VoiceSessionPhase.idle);
    expect(input.results, hasLength(1));
    expect(input.cancels, 1);
  });

  test('one final result sends once, waits for speech, then listens again',
      () async {
    await session.start(AppLanguage.pl);
    expect(session.phase, VoiceSessionPhase.listening);
    input.results[0]('częściowe', false);
    input.results[0]('pytanie', true);
    input.results[0]('powtórzenie', true);
    input.done[0](null);
    await flush();
    expect(requests, ['pytanie']);
    expect(session.phase, VoiceSessionPhase.thinking);
    reply.complete('odpowiedź');
    await flush();
    expect(session.phase, VoiceSessionPhase.speaking);
    expect(output.spoken, ['odpowiedź']);
    expect(input.results, hasLength(1));
    output.playback!.complete();
    await flush();
    expect(input.results, hasLength(2));
    expect(session.phase, VoiceSessionPhase.listening);
    await session.stop();
  });

  test('stopping while model responds prevents playback and restart', () async {
    await session.start(AppLanguage.pl);
    input.results[0]('pytanie', true);
    await flush();
    await session.stop();
    reply.complete('spóźniona odpowiedź');
    await flush();
    expect(session.phase, VoiceSessionPhase.idle);
    expect(output.spoken, isEmpty);
    expect(input.results, hasLength(1));
  });

  test('stop during playback blocks restart even if completion arrives later',
      () async {
    await session.start(AppLanguage.pl);
    input.results[0]('pytanie', true);
    await flush();
    reply.complete('odpowiedź');
    await flush();
    await session.stop();
    output.playback!.complete();
    await flush();
    expect(session.phase, VoiceSessionPhase.idle);
    expect(input.results, hasLength(1));
    expect(output.stops, 1);
  });

  test('manual interruption stops speech and listens once even after late playback completion', () async {
    await session.start(AppLanguage.pl);
    input.results[0]('pytanie', true);
    await flush();
    reply.complete('długa odpowiedź');
    await flush();
    expect(session.phase, VoiceSessionPhase.speaking);
    await session.interrupt();
    expect(output.stops, 1);
    expect(session.phase, VoiceSessionPhase.listening);
    expect(input.results, hasLength(2));
    output.playback!.complete();
    await flush();
    expect(input.results, hasLength(2));
    await session.stop();
  });

  test('ending during interruption prevents the microphone restarting', () async {
    await session.start(AppLanguage.pl);
    input.results[0]('pytanie', true);
    await flush();
    reply.complete('odpowiedź');
    await flush();
    output.stopWait = Completer<void>();
    final interrupted = session.interrupt();
    final stopping = session.stop();
    output.stopWait!.complete();
    await interrupted;
    await stopping;
    expect(session.phase, VoiceSessionPhase.idle);
    expect(input.results, hasLength(1));
  });

  test('stop while initializing prevents microphone from starting', () async {
    input.initialization = Completer<bool>();
    final starting = session.start(AppLanguage.pl);
    await session.stop();
    input.initialization!.complete(true);
    await starting;
    expect(input.results, isEmpty);
    expect(session.phase, VoiceSessionPhase.idle);
  });

  test('restart waits until cancellation of previous microphone ends', () async {
    await session.start(AppLanguage.pl);
    input.cancelWait = Completer<void>();
    final stopping = session.stop();
    final starting = session.start(AppLanguage.pl);
    await flush();
    expect(input.results, hasLength(1));
    input.cancelWait!.complete();
    await stopping;
    await starting;
    expect(input.results, hasLength(2));
    expect(session.phase, VoiceSessionPhase.listening);
    await session.stop();
  });

  test('response failure is spoken once and listening resumes without retrying', () async {
    final errors = <String>[];
    session = VoiceSession(input: input, output: output,
        respond: (text) { requests.add(text); return reply.future; },
        onPhase: (_, __) {}, onTranscript: (_, __) {}, onResponseError: errors.add);
    await session.start(AppLanguage.pl);
    input.results.single('Otwórz kalkulator', true);
    await flush();
    reply.completeError(StateError('unexpected failure'));
    await flush();
    expect(requests, ['Otwórz kalkulator']);
    expect(errors, ['Nie udało się przygotować odpowiedzi. Sprawdź stan aplikacji przed ponowieniem.']);
    expect(output.spoken, errors);
    expect(session.phase, VoiceSessionPhase.speaking);
    output.playback!.complete();
    await flush();
    expect(input.results, hasLength(2));
    expect(session.phase, VoiceSessionPhase.listening);
    expect(requests, hasLength(1));
    await session.stop();
  });

  test('late response failure after stopping does not speak or restart', () async {
    final errors = <String>[];
    session = VoiceSession(input: input, output: output,
        respond: (text) { requests.add(text); return reply.future; },
        onPhase: (_, __) {}, onTranscript: (_, __) {}, onResponseError: errors.add);
    await session.start(AppLanguage.en);
    input.results.single('Open the calculator', true);
    await flush();
    await session.stop();
    reply.completeError(StateError('late failure'));
    await flush();
    expect(errors, isEmpty);
    expect(output.spoken, isEmpty);
    expect(input.results, hasLength(1));
    expect(session.phase, VoiceSessionPhase.idle);
  });

  test('recognition failure stops the session without sending', () async {
    await session.start(AppLanguage.pl);
    input.done[0]('error_network');
    input.results[0]('spóźnione', true);
    await flush();
    expect(session.phase, VoiceSessionPhase.error);
    expect(requests, isEmpty);
  });

  test('missing voice language stops the session before reopening microphone', () async {
    String? error;
    output.failure = const SpeechLanguageUnavailable();
    session = VoiceSession(
      input: input,
      output: output,
      respond: (_) async => 'Odpowiedź',
      onPhase: (_, reason) { if (reason != null) error = reason; },
      onTranscript: (_, __) {},
    );
    await session.start(AppLanguage.pl);
    input.results.single('Jak spawać?', true);
    await flush();
    expect(session.phase, VoiceSessionPhase.error);
    expect(error, 'voice_language_unavailable');
    expect(input.results, hasLength(1));
    await session.stop();
  });

  for (final code in [null, 'error_no_match', 'error_speech_timeout']) {
    testWidgets('speech pause retries safely: $code', (tester) async {
      await session.start(AppLanguage.pl);
      input.done[0](code);
      await tester.pump(const Duration(milliseconds: 499));
      expect(input.results, hasLength(1));
      expect(session.phase, VoiceSessionPhase.starting);
      await tester.pump(const Duration(milliseconds: 1));
      expect(input.results, hasLength(2));
      expect(session.phase, VoiceSessionPhase.listening);
      expect(requests, isEmpty);
      await session.stop();
    });
  }

  testWidgets('stop cancels a scheduled silent retry', (tester) async {
    await session.start(AppLanguage.pl);
    input.done[0]('error_no_match');
    await session.stop();
    await tester.pump(const Duration(seconds: 1));
    expect(input.results, hasLength(1));
    expect(session.phase, VoiceSessionPhase.idle);
  });
}
