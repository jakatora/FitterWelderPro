import 'dart:io';

import 'package:path/path.dart' as p;

import '../i18n/app_language.dart';
import 'offline_speech_worker.dart';

class OfflineVoiceModelUnavailable implements Exception {
  const OfflineVoiceModelUnavailable();
}

/// Paths in a Windows distribution prepared by prepare_windows_voice.ps1.
/// The English and Polish models are separate; never silently use the wrong
/// language when a distribution is missing one of them.
class WindowsVoiceAssets {
  const WindowsVoiceAssets(this.applicationDirectory);

  final String applicationDirectory;

  String get libraryPath => p.join(applicationDirectory, 'libvosk.dll');

  String modelPath(AppLanguage language) => p.join(
        applicationDirectory,
        'data',
        'offline_voice',
        language == AppLanguage.en
            ? 'vosk-model-small-en-us-0.15'
            : 'vosk-model-small-pl-0.22',
      );

  Future<bool> isAvailable(AppLanguage language) async {
    final model = modelPath(language);
    final required = [
      libraryPath,
      for (final name in [
        'libgcc_s_seh-1.dll',
        'libstdc++-6.dll',
        'libwinpthread-1.dll'
      ])
        p.join(applicationDirectory, name),
      for (final name in [
        'am/final.mdl',
        'conf/model.conf',
        'graph/Gr.fst',
        'graph/HCLr.fst',
        'ivector/final.ie'
      ])
        p.joinAll([model, ...p.split(name)]),
    ];
    final exists =
        await Future.wait(required.map((name) => File(name).exists()));
    return exists.every((value) => value);
  }

  Future<OfflineRecognizer> open(AppLanguage language) async {
    if (!await isAvailable(language)) {
      throw const OfflineVoiceModelUnavailable();
    }
    return OfflineSpeechWorker.open(
        libraryPath: libraryPath, modelPath: modelPath(language));
  }
}
