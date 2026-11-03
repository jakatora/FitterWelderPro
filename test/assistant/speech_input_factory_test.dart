import 'dart:io';

import 'package:cut_list_app/assistant/speech_input_factory_io.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/assistant/windows_offline_speech_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Windows voice is opt-in and requires the packaged library', () async {
    final folder = await Directory.systemTemp.createTemp('fwp_factory_');
    final library = File(p.join(folder.path, 'libvosk.dll'));
    try {
      expect(
          createPlatformSpeechInput(
              preview: true, isWindows: true, executableDirectory: folder.path),
          isA<SystemSpeechInput>());
      await library.writeAsBytes([0]);
      expect(
          createPlatformSpeechInput(
              preview: false,
              isWindows: true,
              executableDirectory: folder.path),
          isA<SystemSpeechInput>());
      expect(
          createPlatformSpeechInput(
              preview: true,
              isWindows: false,
              executableDirectory: folder.path),
          isA<SystemSpeechInput>());
      final input = createPlatformSpeechInput(
          preview: true, isWindows: true, executableDirectory: folder.path);
      expect(input, isA<WindowsOfflineSpeechInput>());
      expect(isLocalSpeechInput(input), isTrue);
    } finally {
      if (await library.exists()) await library.delete();
      await folder.delete();
    }
  });
}
