import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'speech_io.dart';
import 'windows_offline_speech_input.dart';
import 'windows_voice_assets.dart';

const _preview = bool.fromEnvironment('FWP_WINDOWS_VOICE_PREVIEW');

// Share the Windows capture owner across screens, just as the system speech
// adapter is shared on mobile. An unconfirmed stop must survive navigation.
SpeechInput? _runtimeInput;
SpeechInput createSpeechInput() => _runtimeInput ??= createPlatformSpeechInput(
      preview: _preview,
      isWindows: Platform.isWindows,
      executableDirectory: p.dirname(Platform.resolvedExecutable),
    );

/// Preview is opt-in until a physical microphone and a packaged app are tested.
@visibleForTesting
SpeechInput createPlatformSpeechInput({
  required bool preview,
  required bool isWindows,
  required String executableDirectory,
}) {
  if (!preview || !isWindows) return SystemSpeechInput();
  final assets = WindowsVoiceAssets(executableDirectory);
  if (!File(assets.libraryPath).existsSync()) return SystemSpeechInput();
  return WindowsOfflineSpeechInput(
      createRecognizer: assets.open, supported: true);
}

bool isLocalSpeechInput(SpeechInput input) =>
    input is WindowsOfflineSpeechInput;
