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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Cancellation for a mute control must report failure to stop capture.
abstract interface class MicrophoneMute {
  Future<void> cancelForMute();
}

/// Identyfikator języka dla rozpoznawania mowy.
String speechLocaleFor(AppLanguage lang) =>
    lang == AppLanguage.en ? 'en_US' : 'pl_PL';

class SystemSpeechInput implements SpeechInput, MicrophoneMute {
  factory SystemSpeechInput() => _shared;
  SystemSpeechInput._();
  static final _shared = SystemSpeechInput._();

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
    if (_onDone != null) await cancel();
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
    _finish(null);
  }

  @override
  Future<void> cancelForMute() async {
    try {
      await _stt.cancel();
    } finally {
      _finish(null);
    }
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

/// The platform could not select an installed voice for the requested language.
class SpeechLanguageUnavailable implements Exception {
  const SpeechLanguageUnavailable();
}

/// Adapter for a voice session that must wait until native playback finishes.
class CompletionSpeechOutput implements SpeechOutput {
  CompletionSpeechOutput(this._system);
  final SystemSpeechOutput _system;

  @override
  Future<void> speak(String text, AppLanguage language) =>
      _system.speakUntilDone(text, language);

  @override
  Future<void> stop() => _system.stopForConversation();
}

/// Prefer an installed, high-quality voice for the requested locale when the
/// platform reports enough information to identify one. Otherwise leave the
/// system default alone. Network-only Android voices are deliberately excluded.
bool _voiceLocaleMatches(String locale, AppLanguage language) {
  final normalized = locale.toLowerCase().replaceAll('_', '-');
  return language == AppLanguage.en
      ? normalized == 'en' || normalized.startsWith('en-')
      : normalized == 'pl' || normalized.startsWith('pl-');
}

bool _voiceIsInstalledLocally(Map raw) =>
    raw['network_required'] != true && raw['network_required'] != '1' &&
    !(raw['features'] is String &&
        (raw['features'] as String).toLowerCase().contains('notinstalled'));

@visibleForTesting
Map<String, String>? chooseEnhancedVoice(Object? voices, AppLanguage language) {
  if (voices is! List) return null;
  const scores = {'high': 2, 'very high': 3, 'enhanced': 2, 'premium': 3};
  Map<String, String>? best;
  var bestScore = 0;
  for (final raw in voices) {
    if (raw is! Map) continue;
    final name = raw['name'];
    final locale = raw['locale'];
    if (name is! String ||
        name.isEmpty ||
        locale is! String ||
        !_voiceLocaleMatches(locale, language)) {
      continue;
    }
    if (!_voiceIsInstalledLocally(raw)) continue;
    final quality = raw['quality'];
    final score = quality is String ? (scores[quality.toLowerCase()] ?? 0) : 0;
    if (score <= bestScore) continue;
    bestScore = score;
    best = {'name': name, 'locale': locale};
    if (raw['identifier'] is String &&
        (raw['identifier'] as String).isNotEmpty) {
      best['identifier'] = raw['identifier'] as String;
    }
  }
  return best;
}

class SystemSpeechOutput implements SpeechOutput {
  factory SystemSpeechOutput() => _shared;
  SystemSpeechOutput._();
  static final _shared = SystemSpeechOutput._();
  FlutterTts? _tts;
  int _speechEpoch = 0;
  bool _playbackMayBeActive = false;
  Future<void>? _stoppingPlayback;

  String _voicePreferenceKey(AppLanguage language) =>
      'assistant_voice_${language == AppLanguage.en ? 'en' : 'pl'}_v1';

  /// Installed local voices for the language currently used by the app.
  Future<List<Map<String, String>>> availableVoices(
      AppLanguage language) async {
    final rawVoices = await (_tts ??= FlutterTts()).getVoices;
    if (rawVoices is! List) return [];
    final voices = <Map<String, String>>[];
    final seen = <String>{};
    for (final raw in rawVoices) {
      if (raw is! Map) continue;
      final name = raw['name'];
      final locale = raw['locale'];
      if (name is! String ||
          name.isEmpty ||
          locale is! String ||
          !_voiceLocaleMatches(locale, language) ||
          !_voiceIsInstalledLocally(raw)) {
        continue;
      }
      final id = raw['identifier'];
      final voice = <String, String>{'name': name, 'locale': locale};
      if (id is String && id.isNotEmpty) voice['identifier'] = id;
      if (seen.add('$locale\u0000$name\u0000${voice['identifier'] ?? ''}')) {
        voices.add(voice);
      }
    }
    return voices;
  }

  Future<Map<String, String>?> preferredVoice(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_voicePreferenceKey(language));
    if (json == null) return null;
    try {
      final raw = jsonDecode(json);
      if (raw is! Map || raw['name'] is! String || raw['locale'] is! String) {
        return null;
      }
      return {
        'name': raw['name'] as String,
        'locale': raw['locale'] as String,
        if (raw['identifier'] is String)
          'identifier': raw['identifier'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> setPreferredVoice(
      AppLanguage language, Map<String, String>? voice) async {
    final prefs = await SharedPreferences.getInstance();
    return voice == null
        ? prefs.remove(_voicePreferenceKey(language))
        : prefs.setString(_voicePreferenceKey(language), jsonEncode(voice));
  }

  Future<void> _stopPlayback(FlutterTts tts) async {
    final pending = _stoppingPlayback;
    if (pending != null) {
      await pending;
      return;
    }
    if (!_playbackMayBeActive) return;
    final stopped = tts.stop().then<void>((result) {
      if (result == 0) throw StateError('Speech output did not stop');
    });
    _stoppingPlayback = stopped;
    try {
      await stopped;
      _playbackMayBeActive = false;
    } finally {
      _stoppingPlayback = null;
    }
  }

  @override
  Future<void> speak(String text, AppLanguage language) async {
    await _speak(text, language, waitForCompletion: false);
  }

  /// Used by voice conversations, which must not reopen the microphone while
  /// the synthesizer is still speaking. Normal read-aloud stays nonblocking.
  Future<void> speakUntilDone(String text, AppLanguage language) async {
    await _speak(text, language, waitForCompletion: true);
  }

  Future<void> previewVoice(Map<String, String> voice, AppLanguage language) =>
      _speak(
        language == AppLanguage.en
            ? 'Hello, I am your assistant.'
            : 'Dzień dobry, jestem Twoim asystentem.',
        language,
        waitForCompletion: true,
        preview: voice,
      );

  Future<void> _speak(String text, AppLanguage language,
      {required bool waitForCompletion, Map<String, String>? preview}) async {
    final epoch = ++_speechEpoch;
    var priorPlaybackStopped = false;
    var playbackAttempted = false;
    try {
      final tts = _tts ??= FlutterTts();
      // Stop an earlier utterance before switching completion mode. On
      // Windows the native stop() uses the current mode to resolve speak().
      await _stopPlayback(tts);
      priorPlaybackStopped = true;
      if (epoch != _speechEpoch) return;
      await tts.awaitSpeakCompletion(waitForCompletion);
      if (epoch != _speechEpoch) return;
      Object? knownVoices;
      try {
        knownVoices = await tts.getVoices;
      } catch (_) {
        // Fall back to the platform's language result if discovery fails.
      }
      if (epoch != _speechEpoch) return;
      var localeToUse = language == AppLanguage.en ? 'en-US' : 'pl-PL';
      if (knownVoices is List) {
        final availableLocales = knownVoices.whereType<Map>()
            .where(_voiceIsInstalledLocally)
            .map((voice) => voice['locale'])
            .whereType<String>()
            .where((locale) => _voiceLocaleMatches(locale, language))
            .toList();
        if (availableLocales.isNotEmpty) {
          final standardLocale = localeToUse.toLowerCase();
          localeToUse = availableLocales.firstWhere(
            (locale) => locale.toLowerCase().replaceAll('_', '-') == standardLocale,
            orElse: () => availableLocales.first,
          );
        }
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        if (knownVoices is List) {
          final hasReportedLocale = knownVoices.whereType<Map>()
              .any((voice) => voice['locale'] is String);
          final locales = knownVoices
              .whereType<Map>()
              .where(_voiceIsInstalledLocally)
              .map((voice) => voice['locale'])
              .whereType<String>()
              .map((locale) => locale.toLowerCase().replaceAll('_', '-'))
              .toList();
          if ((knownVoices.isEmpty || hasReportedLocale) &&
              !locales.any((locale) => _voiceLocaleMatches(locale, language))) {
            throw const SpeechLanguageUnavailable();
          }
        }
      }
      final languageResult = await tts.setLanguage(localeToUse);
      if (epoch != _speechEpoch) return;
      if (languageResult == 0) throw const SpeechLanguageUnavailable();
      if (preview != null) {
        final result = await tts.setVoice(preview);
        if (result == 0) throw StateError('Voice unavailable');
      } else {
        try {
          final voices = knownVoices ?? await tts.getVoices;
          Map<String, String>? preferred;
          try {
            preferred = await preferredVoice(language);
          } catch (_) {
            // A preferences failure must not disable automatic voice selection.
          }
          final available = voices is List ? voices : const [];
          final matches = available.where((raw) =>
              raw is Map &&
              raw['locale'] is String &&
              raw['name'] == preferred?['name'] &&
              raw['locale'] == preferred?['locale'] &&
              _voiceLocaleMatches(raw['locale'] as String, language) &&
              _voiceIsInstalledLocally(raw) &&
              (preferred?['identifier'] == null ||
                  raw['identifier'] == preferred?['identifier']));
          final voice = preferred != null && matches.isNotEmpty
              ? preferred
              : chooseEnhancedVoice(voices, language);
          if (epoch != _speechEpoch) return;
          if (voice != null) await tts.setVoice(voice);
        } catch (_) {
          // Some platforms do not provide voice metadata; keep the system voice.
        }
      }
      if (epoch != _speechEpoch) return;
      _playbackMayBeActive = true;
      playbackAttempted = true;
      var playbackCompleted = false;
      try {
        final result = await tts.speak(text);
        if (result == 0) throw StateError('Speech output unavailable');
        playbackCompleted = true;
      } finally {
        // Nonblocking speech can continue after speak() returns. In the
        // completion mode, however, the native call finishes with playback.
        if (waitForCompletion && playbackCompleted && epoch == _speechEpoch) {
          _playbackMayBeActive = false;
        }
      }
    } catch (e) {
      if (epoch == _speechEpoch && priorPlaybackStopped && !playbackAttempted) {
        _playbackMayBeActive = false;
      }
      debugPrint('SystemSpeechOutput.speak: $e');
      if (waitForCompletion) rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await stopForConversation();
    } catch (_) {}
  }

  /// A voice session must not restart the microphone if playback may continue.
  Future<void> stopForConversation() async {
    _speechEpoch++;
    final tts = _tts;
    if (tts == null) return;
    await _stopPlayback(tts);
  }
}
