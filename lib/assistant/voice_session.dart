import 'dart:async';

import '../i18n/app_language.dart';
import 'speech_io.dart';

/// A user-initiated, turn-taking voice session. The caller owns consent,
/// conversation history and the actual assistant request. The output must
/// complete [SpeechOutput.speak] only after playback finishes or stops.
enum VoiceSessionPhase { idle, starting, listening, muting, muted, thinking, speaking, error }

class VoiceSession {
  VoiceSession({
    required this.input,
    required this.output,
    required this.respond,
    required this.onPhase,
    required this.onTranscript,
    this.onUnrecognized,
    this.onResponseError,
  });

  final SpeechInput input;
  final SpeechOutput output;
  final Future<String> Function(String text) respond;
  final void Function(VoiceSessionPhase phase, String? error) onPhase;
  final void Function(String text, bool isFinal) onTranscript;
  final void Function()? onUnrecognized;
  final void Function(String message)? onResponseError;
  int _epoch = 0;
  int _listenEpoch = 0;
  Future<void>? _stopping;
  Future<void>? _interrupting;
  Future<void>? _muting;
  Future<void>? _failedCaptureCleanup;
  bool _captureCleanupFailed = false;
  Timer? _retryTimer;
  bool _muteRequested = false;
  bool _captureStopped = false;
  VoiceSessionPhase _phase = VoiceSessionPhase.idle;
  AppLanguage _language = AppLanguage.pl;

  VoiceSessionPhase get phase => _phase;
  bool get microphoneMuted => _muteRequested;
  bool get canToggleMute => _phase == VoiceSessionPhase.listening ||
      _phase == VoiceSessionPhase.muted ||
      ((_phase == VoiceSessionPhase.thinking || _phase == VoiceSessionPhase.speaking) && _captureStopped);
  bool get active =>
      _phase != VoiceSessionPhase.idle && _phase != VoiceSessionPhase.error;

  void _setPhase(VoiceSessionPhase phase, [String? error]) {
    _phase = phase;
    onPhase(phase, error);
  }

  Future<void> start(AppLanguage language) async {
    final requestEpoch = _epoch;
    final stopping = _stopping;
    if (stopping != null) await stopping;
    final interrupting = _interrupting;
    if (interrupting != null) await interrupting;
    final cleanup = _failedCaptureCleanup;
    if (cleanup != null) await cleanup;
    if (requestEpoch != _epoch) return;
    if (active) return;
    if (_captureCleanupFailed) {
      await _cleanupFailedCapture(requestEpoch);
      if (requestEpoch != _epoch || _captureCleanupFailed) return;
    }
    final epoch = ++_epoch;
    _language = language;
    _muteRequested = false;
    _captureStopped = false;
    _setPhase(VoiceSessionPhase.starting);
    if (epoch != _epoch) return;
    try {
      if (!input.isSupported || !await input.initialize()) {
        if (epoch == _epoch) {
          _setPhase(VoiceSessionPhase.error, 'speech_unavailable');
        }
        return;
      }
      if (epoch != _epoch) return;
      await _listen(epoch);
    } catch (_) {
      if (epoch == _epoch) {
        _setPhase(VoiceSessionPhase.error, 'speech_unavailable');
      }
    }
  }

  /// Stop playback and return to listening without ending the conversation.
  /// This is a manual interruption, not simultaneous speech recognition.
  Future<void> interrupt() async {
    if (_phase != VoiceSessionPhase.speaking || _interrupting != null || _muteRequested) return;
    final completed = Completer<void>();
    _interrupting = completed.future;
    final epoch = ++_epoch;
    _listenEpoch++;
    _setPhase(VoiceSessionPhase.starting);
    try {
      if (epoch != _epoch) return;
      await output.stop();
      if (epoch != _epoch) return;
      await _listen(epoch);
    } catch (_) {
      if (epoch == _epoch) _setPhase(VoiceSessionPhase.error, 'speech_failed');
    } finally {
      _interrupting = null;
      completed.complete();
    }
  }

  /// Pause microphone capture without sending the current partial utterance.
  Future<void> mute() async {
    if (!canToggleMute || _muteRequested || _muting != null) return;
    if (_phase == VoiceSessionPhase.thinking || _phase == VoiceSessionPhase.speaking) {
      _muteRequested = true;
      _setPhase(_phase);
      return;
    }
    if (_phase != VoiceSessionPhase.listening) return;
    _muteRequested = true;
    final epoch = _epoch;
    final completed = Completer<void>();
    _muting = completed.future;
    _listenEpoch++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _setPhase(VoiceSessionPhase.muting);
    try {
      if (input case final MicrophoneMute source) {
        await source.cancelForMute();
      } else {
        await input.cancel();
      }
      if (epoch == _epoch && _phase == VoiceSessionPhase.muting) {
        _setPhase(VoiceSessionPhase.muted);
      }
    } catch (_) {
      if (epoch == _epoch) _setPhase(VoiceSessionPhase.error, 'speech_failed');
    } finally {
      _muting = null;
      completed.complete();
    }
  }

  /// Restart capture only after mute completed, within the same conversation.
  Future<void> unmute() async {
    if (!_muteRequested) return;
    if ((_phase == VoiceSessionPhase.thinking || _phase == VoiceSessionPhase.speaking) && _captureStopped) {
      _muteRequested = false;
      _setPhase(_phase);
      return;
    }
    if (_phase != VoiceSessionPhase.muted) return;
    _muteRequested = false;
    await _listen(_epoch);
  }

  Future<void> _listen(int epoch) async {
    if (epoch != _epoch) return;
    if (_muteRequested) {
      _setPhase(VoiceSessionPhase.muted);
      return;
    }
    _captureStopped = false;
    final listenEpoch = ++_listenEpoch;
    var submitted = false;
    var heardPartial = false;
    bool current() => epoch == _epoch && listenEpoch == _listenEpoch;
    _setPhase(VoiceSessionPhase.starting);
    if (!current()) return;
    try {
      await input.listen(
        language: _language,
        onResult: (text, isFinal) {
          if (!current() || submitted || text.trim().isEmpty) return;
          if (_phase == VoiceSessionPhase.starting) {
            _setPhase(VoiceSessionPhase.listening);
            if (!current()) return;
          }
          onTranscript(text, isFinal);
          if (!isFinal) heardPartial = true;
          if (!current()) return;
          if (isFinal) {
            submitted = true;
            _listenEpoch++;
            unawaited(_answer(epoch, text.trim()));
          }
        },
        onDone: (error) {
          if (!current() || submitted) return;
          _listenEpoch++;
          // A pause or an empty recognition is normal in a conversation.
          // Back off so a platform reporting immediate empty results cannot
          // spin, and invalidate the timer when the user ends the session.
          if (error == null ||
              error == 'error_no_match' ||
              error == 'error_speech_timeout') {
            if (heardPartial) {
              onUnrecognized?.call();
              if (epoch == _epoch && !_muteRequested) {
                unawaited(_askToRepeat(epoch));
              }
              return;
            }
            if (epoch != _epoch || _muteRequested) return;
            _setPhase(VoiceSessionPhase.starting);
            if (epoch != _epoch || _muteRequested) return;
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(milliseconds: 500), () {
              if (epoch == _epoch) unawaited(_listen(epoch));
            });
            return;
          }
          unawaited(_cleanupFailedCapture(epoch, error: error));
        },
      );
      if (current() && _phase == VoiceSessionPhase.starting) {
        _setPhase(VoiceSessionPhase.listening);
      }
    } catch (_) {
      if (current()) {
        _listenEpoch++;
        unawaited(_cleanupFailedCapture(epoch, error: 'speech_failed'));
      }
    }
  }

  Future<void> _cleanupFailedCapture(int epoch, {String? error}) {
    final completed = Completer<void>();
    _failedCaptureCleanup = completed.future;
    _setPhase(error == null ? VoiceSessionPhase.starting : VoiceSessionPhase.error, error);
    unawaited(() async {
      try {
        if (input case final MicrophoneMute source) {
          await source.cancelForMute();
        } else {
          await input.cancel();
        }
        _captureCleanupFailed = false;
      } catch (_) {
        _captureCleanupFailed = true;
        if (epoch == _epoch) _setPhase(VoiceSessionPhase.error, 'speech_failed');
      } finally {
        _failedCaptureCleanup = null;
        completed.complete();
      }
    }());
    return completed.future;
  }

  Future<void> _cancelCaptureForStop() async {
    if (_captureCleanupFailed && input is MicrophoneMute) {
      await (input as MicrophoneMute).cancelForMute();
    } else {
      await input.cancel();
    }
    _captureCleanupFailed = false;
  }

  Future<void> _askToRepeat(int epoch) async {
    _setPhase(VoiceSessionPhase.starting);
    if (epoch != _epoch) return;
    try {
      // Some platform recognizers report an error before capture has fully
      // stopped. Never play the prompt while the microphone may be active.
      if (input case final MicrophoneMute source) {
        await source.cancelForMute();
      } else {
        await input.cancel();
      }
      if (epoch != _epoch) return;
      _captureStopped = true;
      _setPhase(VoiceSessionPhase.speaking);
      if (epoch != _epoch) return;
      await output.speak(
        _language == AppLanguage.pl
            ? 'Nie zrozumiałem wypowiedzi. Powiedz jeszcze raz.'
            : 'I did not catch that. Please say it again.',
        _language,
      );
      if (epoch == _epoch) await _listen(epoch);
    } on SpeechLanguageUnavailable {
      if (epoch == _epoch) _setPhase(VoiceSessionPhase.error, 'voice_language_unavailable');
    } catch (_) {
      if (epoch == _epoch) _setPhase(VoiceSessionPhase.error, 'speech_failed');
    }
  }

  Future<void> _answer(int epoch, String text) async {
    _setPhase(VoiceSessionPhase.thinking);
    if (epoch != _epoch) return;
    try {
      if (input case final MicrophoneMute source) {
        await source.cancelForMute();
      } else {
        await input.cancel();
      }
      if (epoch != _epoch) return;
      _captureStopped = true;
      _setPhase(VoiceSessionPhase.thinking);
      if (epoch != _epoch) return;
      String answer;
      try {
        answer = await respond(text);
      } catch (_) {
        if (epoch != _epoch) return;
        answer = _language == AppLanguage.pl
            ? 'Nie udało się przygotować odpowiedzi. Sprawdź stan aplikacji przed ponowieniem.'
            : 'Could not prepare an answer. Check the app state before trying again.';
        onResponseError?.call(answer);
      }
      if (epoch != _epoch) return;
      if (answer.trim().isEmpty) {
        _setPhase(VoiceSessionPhase.error, 'empty_answer');
        return;
      }
      _setPhase(VoiceSessionPhase.speaking);
      if (epoch != _epoch) return;
      await output.speak(answer, _language);
      if (epoch != _epoch) return;
      await _listen(epoch);
    } on SpeechLanguageUnavailable {
      if (epoch == _epoch) {
        _setPhase(VoiceSessionPhase.error, 'voice_language_unavailable');
      }
    } catch (_) {
      if (epoch == _epoch) {
        _setPhase(VoiceSessionPhase.error, 'response_failed');
      }
    }
  }

  Future<void> stop() async {
    if (_stopping != null) return _stopping;
    final stopped = Completer<void>();
    _stopping = stopped.future;
    _epoch++;
    _listenEpoch++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _muteRequested = false;
    _captureStopped = false;
    _setPhase(VoiceSessionPhase.idle);
    try {
      await Future.wait([
        if (_muting case final muting?) muting
        else if (_failedCaptureCleanup case final cleanup?) cleanup
        else _cancelCaptureForStop(),
        output.stop(),
        if (_interrupting case final interrupting?) interrupting,
      ]);
    } finally {
      _stopping = null;
      stopped.complete();
    }
  }
}
