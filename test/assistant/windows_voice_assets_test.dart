import 'dart:io';

import 'package:cut_list_app/assistant/windows_voice_assets.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'missing language files disable recognition instead of switching language',
      () async {
    final directory = await Directory.systemTemp.createTemp('fwp_voice_');
    try {
      final assets = WindowsVoiceAssets(directory.path);
      expect(assets.modelPath(AppLanguage.pl),
          contains('vosk-model-small-pl-0.22'));
      expect(assets.modelPath(AppLanguage.en),
          contains('vosk-model-small-en-us-0.15'));
      expect(await assets.isAvailable(AppLanguage.pl), isFalse);
      expect(await assets.isAvailable(AppLanguage.en), isFalse);
      await expectLater(assets.open(AppLanguage.en),
          throwsA(isA<OfflineVoiceModelUnavailable>()));
    } finally {
      await directory.delete();
    }
  });

  final bundle = Platform.environment['FWP_TEST_VOICE_BUNDLE'];
  test('packaged Polish and English models can each open and close', () async {
    final assets = WindowsVoiceAssets(bundle!);
    for (final language in [AppLanguage.pl, AppLanguage.en]) {
      expect(await assets.isAvailable(language), isTrue);
      final recognizer = await assets.open(language);
      await recognizer.close();
    }
  },
      skip: bundle == null
          ? 'Requires a locally prepared Windows voice bundle'
          : false);
}
