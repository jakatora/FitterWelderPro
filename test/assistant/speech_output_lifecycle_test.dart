import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  Completer<void>? language;
  setUp(() {
    calls.clear();
    language = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setLanguage') await language?.future;
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
}
