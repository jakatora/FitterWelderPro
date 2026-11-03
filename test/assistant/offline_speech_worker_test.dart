import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cut_list_app/assistant/offline_speech_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unavailable library fails without hanging', () async {
    await expectLater(
      OfflineSpeechWorker.open(
          libraryPath: 'missing-fwp-vosk.dll', modelPath: 'missing'),
      throwsA(isA<StateError>()),
    );
  });

  final dll = Platform.environment['FWP_TEST_VOSK_DLL'];
  final model = Platform.environment['FWP_TEST_VOSK_MODEL'];
  final pcmPath = Platform.environment['FWP_TEST_VOSK_PCM'];
  test('missing model fails without hanging', () async {
    await expectLater(
      OfflineSpeechWorker.open(
          libraryPath: dll!, modelPath: 'missing-fwp-model'),
      throwsA(isA<StateError>()),
    );
  }, skip: dll == null ? 'Requires locally supplied Vosk DLL' : false);

  test('close waits for an active audio chunk and rejects later input',
      () async {
    final worker =
        await OfflineSpeechWorker.open(libraryPath: dll!, modelPath: model!);
    final result = worker.accept(Uint8List(32000));
    final close = worker.close();
    expect(() => worker.accept(Uint8List(2)), throwsStateError);
    await result;
    await close;
    await worker.close();
    expect(() => worker.accept(Uint8List(2)), throwsStateError);
  },
      skip: dll == null || model == null
          ? 'Requires locally supplied Vosk DLL and model'
          : false);

  test('real model processes streamed PCM off the UI isolate and closes',
      () async {
    final worker =
        await OfflineSpeechWorker.open(libraryPath: dll!, modelPath: model!);
    final audio = await File(pcmPath!).readAsBytes();
    expect(() => worker.accept(Uint8List(0)), throwsArgumentError);
    expect(() => worker.accept(Uint8List(3)), throwsArgumentError);
    expect(() => worker.accept(Uint8List(32002)), throwsArgumentError);
    var ticks = 0;
    final timer =
        Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
    final words = <String>[];
    try {
      for (var pos = 0; pos < audio.length; pos += 8000) {
        final end = (pos + 8000).clamp(0, audio.length);
        final pending = worker.accept(Uint8List.sublistView(audio, pos, end));
        expect(() => worker.accept(Uint8List(2)), throwsStateError);
        final result = await pending;
        if (result.isFinal && result.text.isNotEmpty) words.add(result.text);
      }
      final last = await worker.finish();
      expect(last.isFinal, isTrue);
      if (last.text.isNotEmpty) words.add(last.text);
      expect(
          words.join(' '),
          Platform.environment['FWP_TEST_VOSK_EXPECTED'] ??
              'otwórz listę cięć');
      expect(ticks, greaterThan(0));
    } finally {
      timer.cancel();
      await worker.close();
      await worker.close();
    }
    expect(() => worker.accept(Uint8List(2)), throwsStateError);
  },
      skip: dll == null || model == null || pcmPath == null
          ? 'Requires locally supplied Vosk DLL, Polish model and PCM fixture'
          : false);
}
