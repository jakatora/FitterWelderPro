import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cut_list_app/assistant/offline_speech_worker.dart';
import 'package:cut_list_app/assistant/windows_offline_speech_input.dart';
import 'package:cut_list_app/assistant/windows_voice_assets.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

class FakeRecorder implements AudioRecorder {
  final audio = StreamController<Uint8List>.broadcast(sync: true);
  void Function(RecordConfig)? changed;
  RecordConfig? adjustedAtStart;
  RecordConfig? requested;
  int cancellations = 0;
  int disposals = 0;
  bool failCancel = false;
  @override
  Future<bool> hasPermission({bool request = true}) async => true;
  @override
  Future<void> setOnConfigChanged(void Function(RecordConfig)? callback) async {
    changed = callback;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    requested = config;
    if (adjustedAtStart case final adjustment?) changed?.call(adjustment);
    return audio.stream;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
    if (failCancel) throw StateError('device failure');
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCapture implements PcmCapture {
  final controller = StreamController<Uint8List>.broadcast(sync: true);
  int starts = 0;
  int stops = 0;
  bool failStop = false;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('capture stop failure');
  }
}

class FakeRecognizer implements OfflineRecognizer {
  final chunks = <List<int>>[];
  Completer<OfflineSpeechResult>? blocked;
  OfflineSpeechResult next = const OfflineSpeechResult('', isFinal: false);
  OfflineSpeechResult last = const OfflineSpeechResult('', isFinal: true);
  int finishes = 0;
  int closes = 0;
  @override
  Future<OfflineSpeechResult> accept(Uint8List pcm) async {
    chunks.add(pcm.toList());
    return blocked == null ? next : await blocked!.future;
  }

  @override
  Future<OfflineSpeechResult> finish() async {
    finishes++;
    return last;
  }

  @override
  Future<void> close() async {
    if (blocked != null) await blocked!.future;
    closes++;
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('missing model reports the selected language without starting capture',
      () async {
    final capture = FakeCapture();
    final endings = <String?>[];
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async =>
            throw const OfflineVoiceModelUnavailable());
    await input.listen(
        language: AppLanguage.en,
        onResult: (_, __) => fail('unexpected result'),
        onDone: endings.add);
    expect(endings, ['error_language_unavailable']);
    expect(capture.starts, 0);
    expect(capture.stops, 1);
    await capture.controller.close();
  });
  test('mute reports a capture stop failure and closes recognizer', () async {
    final capture = FakeCapture()..failStop = true;
    final recognizer = FakeRecognizer();
    final input = WindowsOfflineSpeechInput(supported: true,
        createCapture: () => capture, createRecognizer: (_) async => recognizer);
    await input.listen(language: AppLanguage.pl, onResult: (_, __) {}, onDone: (_) {});
    await expectLater(input.cancelForMute(), throwsStateError);
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  test('capture rejects a format adjusted before streaming starts', () async {
    final recorder = FakeRecorder()
      ..adjustedAtStart = const RecordConfig(
          encoder: AudioEncoder.pcm16bits, sampleRate: 48000, numChannels: 1);
    final capture = WindowsPcmCapture(recorder: recorder);
    final stream = await capture.start();
    final error = expectLater(stream, emitsError(isA<StateError>()));
    await error;
    await capture.stop();
    expect(recorder.requested!.sampleRate, 16000);
    expect(recorder.cancellations, 1);
    expect(recorder.disposals, 1);
    await recorder.audio.close();
  });

  test('capture forwards compatible audio and rejects later format changes',
      () async {
    final recorder = FakeRecorder();
    final capture = WindowsPcmCapture(recorder: recorder);
    final stream = await capture.start();
    final events = <Object>[];
    final subscription =
        stream.listen(events.add, onError: (Object error) => events.add(error));
    recorder.changed!(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000));
    recorder.audio.add(Uint8List.fromList([1, 2]));
    recorder.changed!(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: 48000, numChannels: 1));
    recorder.audio.add(Uint8List.fromList([3, 4]));
    expect(events.first, [1, 2]);
    expect(events.length, 2);
    expect(events.last, isA<StateError>());
    await subscription.cancel();
    await capture.stop();
    await recorder.audio.close();
  });

  test('capture still disposes recorder if native cancellation fails',
      () async {
    final recorder = FakeRecorder()..failCancel = true;
    final capture = WindowsPcmCapture(recorder: recorder);
    final stream = await capture.start();
    final subscription = stream.listen((_) {});
    await expectLater(capture.stop(), throwsStateError);
    expect(recorder.cancellations, 1);
    expect(recorder.disposals, 1);
    await subscription.cancel();
    await recorder.audio.close();
  });

  test('PCM chunks are aligned and stop flushes the final text once', () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer()
      ..last = const OfflineSpeechResult('stal nierdzewna', isFinal: true);
    final results = <String>[];
    final endings = <String?>[];
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async => recognizer);
    await input.listen(
        language: AppLanguage.pl,
        onResult: (text, done) {
          if (done) results.add(text);
        },
        onDone: endings.add);
    capture.controller.add(Uint8List.fromList([1, 2, 3]));
    await tick();
    capture.controller.add(Uint8List.fromList([4, 5, 6]));
    await tick();
    await input.stop();
    expect(recognizer.chunks, [
      [1, 2],
      [3, 4, 5, 6]
    ]);
    expect(results, ['stal nierdzewna']);
    expect(endings, [null]);
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  test('final recognition closes capture and ignores subsequent audio',
      () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer()
      ..next = const OfflineSpeechResult('otwórz', isFinal: true);
    final results = <String>[];
    final done = Completer<void>();
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async => recognizer);
    await input.listen(
        language: AppLanguage.pl,
        onResult: (text, _) => results.add(text),
        onDone: (_) => done.complete());
    capture.controller.add(Uint8List(4));
    await done.future;
    capture.controller.add(Uint8List(4));
    expect(results, ['otwórz']);
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  test('cancelling during model load never starts microphone', () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer();
    final loading = Completer<OfflineRecognizer>();
    final endings = <String?>[];
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) => loading.future);
    final starting = input.listen(
        language: AppLanguage.pl,
        onResult: (_, __) => fail('unexpected result'),
        onDone: endings.add);
    final stopped = input.cancel();
    loading.complete(recognizer);
    await Future.wait([starting, stopped]);
    expect(capture.starts, 0);
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    expect(endings, [null]);
    await capture.controller.close();
  });

  test('overload stops capture instead of retaining unbounded audio', () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer()
      ..blocked = Completer<OfflineSpeechResult>();
    final done = Completer<String?>();
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async => recognizer);
    await input.listen(
        language: AppLanguage.pl,
        onResult: (_, __) => fail('unexpected result'),
        onDone: done.complete);
    capture.controller.add(Uint8List(32000));
    capture.controller.add(Uint8List(64001));
    recognizer.blocked!.complete(const OfflineSpeechResult('', isFinal: false));
    expect(await done.future, 'speech_overloaded');
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  test('microphone stream failure stops capture and releases recognizer',
      () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer();
    final done = Completer<String?>();
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async => recognizer);
    await input.listen(
        language: AppLanguage.pl,
        onResult: (_, __) => fail('unexpected result'),
        onDone: done.complete);
    capture.controller.addError(StateError('device disconnected'));
    expect(await done.future, 'speech_failed');
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  test('cancel during recognition suppresses late text', () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer()
      ..blocked = Completer<OfflineSpeechResult>();
    final results = <String>[];
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async => recognizer);
    await input.listen(
        language: AppLanguage.pl,
        onResult: (text, _) => results.add(text),
        onDone: (_) {});
    capture.controller.add(Uint8List(4));
    final stopped = input.cancel();
    recognizer.blocked!.complete(
        const OfflineSpeechResult('spóźniona wiadomość', isFinal: true));
    await stopped;
    expect(results, isEmpty);
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  test('cancel during graceful stop suppresses late results', () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer()
      ..blocked = Completer<OfflineSpeechResult>();
    final results = <String>[];
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (_) async => recognizer);
    await input.listen(
        language: AppLanguage.pl,
        onResult: (text, _) => results.add(text),
        onDone: (_) {});
    capture.controller.add(Uint8List(4));
    final stopping = input.stop();
    final cancelling = input.cancel();
    recognizer.blocked!.complete(
        const OfflineSpeechResult('spóźniona wiadomość', isFinal: true));
    await Future.wait([stopping, cancelling]);
    expect(results, isEmpty);
    expect(recognizer.finishes, 0);
    expect(capture.stops, 1);
    expect(recognizer.closes, 1);
    await capture.controller.close();
  });

  final dll = Platform.environment['FWP_TEST_VOSK_DLL'];
  final model = Platform.environment['FWP_TEST_VOSK_MODEL'];
  final pcmPath = Platform.environment['FWP_TEST_VOSK_PCM'];
  final language = Platform.environment['FWP_TEST_VOSK_LANG'] == 'en'
      ? AppLanguage.en
      : AppLanguage.pl;
  test('recorded PCM flows through the adapter and real recognizer', () async {
    final capture = FakeCapture();
    final input = WindowsOfflineSpeechInput(
        supported: true,
        createCapture: () => capture,
        createRecognizer: (selected) {
          expect(selected, language);
          return OfflineSpeechWorker.open(libraryPath: dll!, modelPath: model!);
        });
    final finalResults = <String>[];
    final endings = <String?>[];
    await input.listen(
        language: language,
        onResult: (text, finalResult) {
          if (finalResult) finalResults.add(text);
        },
        onDone: endings.add);
    final audio = await File(pcmPath!).readAsBytes();
    for (var pos = 0; pos < audio.length; pos += 8000) {
      capture.controller.add(Uint8List.sublistView(
          audio, pos, (pos + 8000).clamp(0, audio.length)));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await input.stop();
    expect(finalResults, [
      Platform.environment['FWP_TEST_VOSK_EXPECTED'] ?? 'otwórz listę cięć'
    ]);
    expect(endings, [null]);
    expect(capture.stops, 1);
    await capture.controller.close();
  },
      skip: dll == null || model == null || pcmPath == null
          ? 'Requires locally supplied Vosk DLL, Polish model and PCM fixture'
          : false);
}
