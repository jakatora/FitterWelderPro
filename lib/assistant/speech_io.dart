// Mowa na wejściu i na wyjściu asystenta — za cienkimi abstrakcjami, żeby
// ekran dało się testować bez platformy (testy wstrzykują atrapy).
//
// Rozpoznawanie mowy robi SYSTEM telefonu (pakiet `speech_to_text`: Android
// SpeechRecognizer / iOS SFSpeechRecognizer). Tekst trafia do aplikacji; sam
// system może przetwarzać dźwięk na serwerach dostawcy (Google / Apple) —
// tego aplikacja nie kontroluje, informuje o tym tekst przy mikrofonie.
//
// Mikrofon włącza się WYŁĄCZNIE po jawnym naciśnięciu przycisku. Odczyt
// odpowiedzi głosem (`flutter_tts`) jest ustawieniem użytkownika, domyślnie
// wyłączonym, i milknie, gdy aplikacja schodzi w tło.

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../i18n/app_language.dart';

/// Wynik rozpoznawania: bieżąca transkrypcja i czy to już wersja końcowa.
typedef SpeechResultCallback = void Function(String text, bool isFinal);

abstract class SpeechInput {
  /// Czy na tej platformie w ogóle pokazywać mikrofon. Web i Windows: nie —
  /// tam `speech_to_text` jest w wersji beta / zależy od przeglądarki.
  bool get isSupported;

  /// Przygotowuje rozpoznawanie; na Androidzie/iOS system pyta tu o zgodę na
  /// mikrofon i rozpoznawanie mowy. `false` = brak zgody albo brak usługi.
  Future<bool> initialize();

  /// Zaczyna słuchać. [onDone] woła się zawsze, gdy nasłuch się skończy
  /// (koniec mowy, stop, błąd) — [error] niepusty przy błędzie.
  Future<void> listen({
    required AppLanguage language,
    required SpeechResultCallback onResult,
    required void Function(String? error) onDone,
  });

  Future<void> stop();
  Future<void> cancel();
}

/// Identyfikator języka dla rozpoznawania mowy.
String speechLocaleFor(AppLanguage lang) =>
    lang == AppLanguage.en ? 'en_US' : 'pl_PL';

class SystemSpeechInput implements SpeechInput {
  SystemSpeechInput();

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  void Function(String? error)? _onDone;

  @override
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<bool> initialize() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (SpeechRecognitionError e) => _finish(e.errorMsg),
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            _finish(null);
          }
        },
      );
    } catch (e) {
      debugPrint('SystemSpeechInput.initialize: $e');
      _ready = false;
    }
    return _ready;
  }

  void _finish(String? error) {
    final cb = _onDone;
    _onDone = null;
    cb?.call(error);
  }

  @override
  Future<void> listen({
    required AppLanguage language,
    required SpeechResultCallback onResult,
    required void Function(String? error) onDone,
  }) async {
    _onDone = onDone;
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) =>
            onResult(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: speechLocaleFor(language),
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 5),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _finish(e.toString());
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    _finish(null);
  }
}

abstract class SpeechOutput {
  Future<void> speak(String text, AppLanguage language);
  Future<void> stop();
}

class SystemSpeechOutput implements SpeechOutput {
  FlutterTts? _tts;

  @override
  Future<void> speak(String text, AppLanguage language) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage(language == AppLanguage.en ? 'en-US' : 'pl-PL');
      await tts.speak(text);
    } catch (e) {
      debugPrint('SystemSpeechOutput.speak: $e');
    }
  }

  @override
  Future<void> stop() async {
    final tts = _tts;
    if (tts == null) return; // nigdy nie mówiliśmy — nie ruszamy platformy
    try {
      await tts.stop();
    } catch (_) {}
  }
}
