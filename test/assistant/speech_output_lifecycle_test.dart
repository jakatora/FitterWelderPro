import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  Completer<void>? language;
  Completer<void>? playback;
  Completer<Object?>? voices;
  Completer<void>? stopping;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    language = null;
    playback = null;
    voices = null;
    stopping = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setLanguage') await language?.future;
      if (call.method == 'speak') await playback?.future;
      if (call.method == 'stop') await stopping?.future;
      if (call.method == 'getVoices' && voices != null) return voices!.future;
      return 1;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('stop during language setup prevents delayed speech', () async {
    language = Completer<void>();
    final output = SystemSpeechOutput();
    final pending = output.speak('Private answer', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'setLanguage'), isTrue);
    await output.stop();
    language!.complete();
    await pending;
    expect(calls.where((c) => c.method == 'speak'), isEmpty);
    expect(calls.where((c) => c.method == 'stop'), isEmpty);
  });
  test('a newer reply supersedes speech waiting for language setup', () async {
    language = Completer<void>();
    final output = SystemSpeechOutput();
    final first = output.speak('Old answer', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    final second = output.speak('Current answer', AppLanguage.en);
    await Future<void>.delayed(Duration.zero);
    language!.complete();
    await Future.wait([first, second]);
    expect(calls.where((c) => c.method == 'speak').map((c) => c.arguments),
        ['Current answer']);
    await output.stop();
  });

  test('conversation output waits for native playback to finish', () async {
    playback = Completer<void>();
    final output = CompletionSpeechOutput(SystemSpeechOutput());
    var finished = false;
    final pending =
        output.speak('Witaj', AppLanguage.pl).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(
        calls.any(
            (c) => c.method == 'awaitSpeakCompletion' && c.arguments == true),
        isTrue);
    expect(calls.any((c) => c.method == 'speak'), isTrue);
    expect(finished, isFalse);
    playback!.complete();
    await pending;
    expect(finished, isTrue);
    await output.stop();
    expect(calls.where((c) => c.method == 'stop'), isEmpty);
  });

  test('missing language stops voice playback and reports the cause', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'setLanguage' ? 0 : 1;
    });
    final output = CompletionSpeechOutput(SystemSpeechOutput());
    await expectLater(output.speak('Witaj', AppLanguage.pl),
        throwsA(isA<SpeechLanguageUnavailable>()));
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
  });

  test('Windows detects missing Polish voice even if the plugin reports success', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    voices = Completer<Object?>()..complete([
      {'name': 'English', 'locale': 'en-US'},
    ]);
    final output = CompletionSpeechOutput(SystemSpeechOutput());
    await expectLater(output.speak('Witaj', AppLanguage.pl),
        throwsA(isA<SpeechLanguageUnavailable>()));
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
  });

  test('a British English voice is available and used when US English is absent', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    voices = Completer<Object?>()..complete([
      {'name': 'Online US', 'locale': 'en-US', 'network_required': '1'},
      {'name': 'British', 'locale': 'en-GB', 'quality': 'high'},
      {'name': 'Polski', 'locale': 'pl-PL'},
    ]);
    final output = SystemSpeechOutput();
    final choices = await output.availableVoices(AppLanguage.en);
    expect(choices, [{'name': 'British', 'locale': 'en-GB'}]);
    await output.speakUntilDone('Hello', AppLanguage.en);
    expect(calls.singleWhere((c) => c.method == 'setLanguage').arguments, 'en-GB');
    expect(calls.singleWhere((c) => c.method == 'setVoice').arguments, choices.single);
    expect(calls.singleWhere((c) => c.method == 'speak').arguments, 'Hello');
    await output.stop();
  });

  test('a removed preferred voice falls back to an installed voice', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    voices = Completer<Object?>()..complete([
      {'name': 'Current', 'locale': 'en-GB', 'quality': 'high'},
    ]);
    final output = SystemSpeechOutput();
    await output.setPreferredVoice(AppLanguage.en,
        {'name': 'Removed', 'locale': 'en-US'});
    await output.speakUntilDone('Hello', AppLanguage.en);
    expect(calls.singleWhere((c) => c.method == 'setVoice').arguments,
        {'name': 'Current', 'locale': 'en-GB'});
    expect(calls.singleWhere((c) => c.method == 'speak').arguments, 'Hello');
    await output.stop();
  });

  test('a rejected synthesis request is reported to a voice conversation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'speak' ? 0 : 1;
    });
    final output = CompletionSpeechOutput(SystemSpeechOutput());
    await expectLater(output.speak('Witaj', AppLanguage.pl),
        throwsA(isA<StateError>()));
  });

  test('stopping during playback stops the native synthesizer', () async {
    playback = Completer<void>();
    final output = CompletionSpeechOutput(SystemSpeechOutput());
    final pending = output.speak('Witaj', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'speak'), isTrue);
    await output.stop();
    expect(calls.where((c) => c.method == 'stop'), hasLength(1));
    playback!.complete();
    await pending;
  });

  test('previous speech stops before changing completion mode', () async {
    final output = SystemSpeechOutput();
    await output.speak('Pierwsza odpowiedź', AppLanguage.pl);
    calls.clear();
    playback = Completer<void>();
    final pending = output.speakUntilDone('Druga odpowiedź', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    final stopIndex = calls.indexWhere((call) => call.method == 'stop');
    final modeIndex = calls.indexWhere((call) =>
        call.method == 'awaitSpeakCompletion' && call.arguments == true);
    expect(stopIndex, greaterThanOrEqualTo(0));
    expect(modeIndex, greaterThan(stopIndex));
    playback!.complete();
    await pending;
  });

  test('new speech waits for an in-progress stop', () async {
    final output = SystemSpeechOutput();
    await output.speak('Pierwsza', AppLanguage.pl);
    calls.clear();
    stopping = Completer<void>();
    final stop = output.stop();
    await Future<void>.delayed(Duration.zero);
    final next = output.speakUntilDone('Druga', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), ['stop']);
    stopping!.complete();
    await Future.wait([stop, next]);
    expect(calls.any((c) => c.method == 'speak'), isTrue);
  });

  test('prefers an installed high quality voice in the requested language', () {
    final result = chooseEnhancedVoice([
      {
        'name': 'Sieciowy',
        'locale': 'pl-PL',
        'quality': 'very high',
        'network_required': '1'
      },
      {
        'name': 'Brakujący',
        'locale': 'pl-PL',
        'quality': 'very high',
        'features': 'notInstalled'
      },
      {'name': 'English', 'locale': 'en-US', 'quality': 'premium'},
      {
        'name': 'Polski',
        'locale': 'pl-PL',
        'quality': 'enhanced',
        'identifier': 'pl-voice'
      },
    ], AppLanguage.pl);
    expect(result,
        {'name': 'Polski', 'locale': 'pl-PL', 'identifier': 'pl-voice'});
    expect(
        chooseEnhancedVoice([
          {'name': 'default', 'locale': 'pl-PL', 'quality': 'default'}
        ], AppLanguage.pl),
        isNull);
  });

  test('selects the enhanced voice before speaking', () async {
    voices = Completer<Object?>()
      ..complete([
        {
          'name': 'Polski HD',
          'locale': 'pl-PL',
          'quality': 'high',
          'network_required': '0'
        },
      ]);
    final output = SystemSpeechOutput();
    await output.speak('Witaj', AppLanguage.pl);
    final selected = calls.singleWhere((call) => call.method == 'setVoice');
    expect(selected.arguments, {'name': 'Polski HD', 'locale': 'pl-PL'});
    expect(calls.indexOf(selected),
        lessThan(calls.indexWhere((c) => c.method == 'speak')));
    await output.stop();
  });

  test('voice choices are local, installed and specific to each language', () async {
    voices = Completer<Object?>()..complete([
      {'name': 'Polski', 'locale': 'pl-PL', 'identifier': 'pl1'},
      {'name': 'Polski', 'locale': 'pl-PL', 'identifier': 'pl1'},
      {'name': 'Online', 'locale': 'pl-PL', 'network_required': '1'},
      {'name': 'English', 'locale': 'en-US'},
    ]);
    final output = SystemSpeechOutput();
    final choices = await output.availableVoices(AppLanguage.pl);
    expect(choices, [{'name': 'Polski', 'locale': 'pl-PL', 'identifier': 'pl1'}]);
    expect(await output.setPreferredVoice(AppLanguage.pl, choices.single), isTrue);
    expect(await output.preferredVoice(AppLanguage.en), isNull);
    await output.speak('Witaj', AppLanguage.pl);
    expect(calls.singleWhere((c) => c.method == 'setVoice').arguments, choices.single);
    await output.stop();
    expect(await output.setPreferredVoice(AppLanguage.pl, null), isTrue);
    expect(await output.preferredVoice(AppLanguage.pl), isNull);
  });

  test('stop during voice discovery prevents playback', () async {
    voices = Completer<Object?>();
    final output = SystemSpeechOutput();
    final pending = output.speak('Prywatna odpowiedź', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    await output.stop();
    voices!.complete([
      {'name': 'Polski HD', 'locale': 'pl-PL', 'quality': 'high'}
    ]);
    await pending;
    expect(calls.where((c) => c.method == 'setVoice' || c.method == 'speak'),
        isEmpty);
  });

  test('unavailable voice list falls back to the system voice', () async {
    voices = Completer<Object?>();
    final output = SystemSpeechOutput();
    final pending = output.speak('Witaj', AppLanguage.pl);
    await Future<void>.delayed(Duration.zero);
    voices!.completeError(PlatformException(code: 'unsupported'));
    await pending;
    expect(calls.where((c) => c.method == 'setVoice'), isEmpty);
    expect(calls.where((c) => c.method == 'speak').single.arguments, 'Witaj');
    await output.stop();
  });
}
