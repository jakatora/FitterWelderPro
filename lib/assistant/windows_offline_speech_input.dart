import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../i18n/app_language.dart';
import 'offline_speech_worker.dart';
import 'speech_io.dart';
import 'windows_voice_assets.dart';

abstract interface class PcmCapture {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

/// Captures 16 kHz mono PCM into memory only, never into an audio file.
class WindowsPcmCapture implements PcmCapture {
  WindowsPcmCapture({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();
  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _source;
  StreamController<Uint8List>? _output;
  bool _started = false;
  bool _disposed = false;
  bool _badFormat = false;
  bool _formatReported = false;

  void _reportFormatError() {
    final output = _output;
    if (_badFormat &&
        !_formatReported &&
        output != null &&
        output.hasListener &&
        !output.isClosed) {
      _formatReported = true;
      output.addError(StateError('Unsupported microphone format'));
    }
  }

  @override
  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone unavailable');
    }
    final output =
        StreamController<Uint8List>(sync: true, onListen: _reportFormatError);
    _output = output;
    await _recorder.setOnConfigChanged((config) {
      if (config.sampleRate != 16000 ||
          config.numChannels != 1 ||
          config.encoder != AudioEncoder.pcm16bits) {
        _badFormat = true;
        _reportFormatError();
      }
    });
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));
    _started = true;
    _source = stream.listen((data) {
      if (!_badFormat && !output.isClosed) output.add(data);
    }, onError: (Object error, StackTrace stack) {
      if (!output.isClosed) output.addError(error, stack);
    }, onDone: () {
      if (!output.isClosed) unawaited(output.close());
    });
    return output.stream;
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _source?.cancel();
    } finally {
      try {
        if (_started) await _recorder.cancel();
      } finally {
        try {
          await _recorder.dispose();
        } finally {
          final output = _output;
          if (output != null && !output.isClosed) unawaited(output.close());
        }
      }
    }
  }
}

typedef OfflineRecognizerFactory = Future<OfflineRecognizer> Function(
    AppLanguage language);
typedef PcmCaptureFactory = PcmCapture Function();

/// Windows adapter. Callers must supply verified local model/library paths.
/// It is not enabled until assets and actual microphone behavior are verified.
class WindowsOfflineSpeechInput implements SpeechInput, MicrophoneMute {
  WindowsOfflineSpeechInput({
    required this.createRecognizer,
    PcmCaptureFactory? createCapture,
    bool? supported,
  })  : createCapture = createCapture ?? WindowsPcmCapture.new,
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  final OfflineRecognizerFactory createRecognizer;
  final PcmCaptureFactory createCapture;
  final bool _supported;
  _ListeningSession? _session;
  int _generation = 0;

  @override
  bool get isSupported => _supported;
  @override
  Future<bool> initialize() async => isSupported;

  @override
  Future<void> listen({
    required AppLanguage language,
    required SpeechResultCallback onResult,
    required void Function(String? error) onDone,
  }) async {
    final generation = ++_generation;
    final previous = _session;
    if (previous != null) {
      previous.suppressResults = true;
      previous.flushing = false;
      await _end(previous, null);
    }
    if (generation != _generation) return;
    final session = _ListeningSession(createCapture(), onResult, onDone);
    _session = session;
    String? error;
    try {
      session.recognizer = await createRecognizer(language);
      if (!session.active) return;
      final stream = await session.capture.start();
      if (!session.active) return;
      session.subscription = stream.listen(
        (data) => _onAudio(session, data),
        onError: (Object _, StackTrace __) =>
            unawaited(_end(session, 'speech_failed')),
        onDone: () => unawaited(_end(session, null, flush: true)),
      );
      session.timeout = Timer(const Duration(seconds: 45),
          () => unawaited(_end(session, 'error_speech_timeout', flush: true)));
    } on OfflineVoiceModelUnavailable {
      error = 'error_language_unavailable';
    } catch (_) {
      error = 'speech_unavailable';
    } finally {
      session.started.complete();
    }
    if (error != null && session.active) await _end(session, error);
  }

  void _onAudio(_ListeningSession session, Uint8List bytes) {
    if (!session.active || bytes.isEmpty) return;
    if (session.queue.length + bytes.length > 64000) {
      unawaited(_end(session, 'speech_overloaded'));
      return;
    }
    session.queue.add(bytes);
    _kick(session);
  }

  void _kick(_ListeningSession session) {
    if (session.pump != null || session.queue.length < 2) return;
    final pump = _drain(session);
    session.pump = pump;
    unawaited(pump.whenComplete(() {
      session.pump = null;
      if ((session.active || session.flushing) && session.queue.length >= 2) {
        _kick(session);
      }
    }));
  }

  Future<void> _drain(_ListeningSession session) async {
    try {
      while (
          (session.active || session.flushing) && session.queue.length >= 2) {
        final buffer = session.queue.takeBytes();
        final count =
            (buffer.length.clamp(0, OfflineSpeechWorker.maxChunkBytes)) & ~1;
        if (count < buffer.length) {
          session.queue.add(Uint8List.sublistView(buffer, count));
        }
        final result = await session.recognizer!
            .accept(Uint8List.sublistView(buffer, 0, count));
        if ((!session.active && !session.flushing) || session.suppressResults) {
          return;
        }
        if (result.text.trim().isEmpty) continue;
        if (result.isFinal) session.resultSent = true;
        session.onResult(result.text, result.isFinal);
        if (result.isFinal) {
          unawaited(_end(session, null));
          return;
        }
      }
    } catch (_) {
      unawaited(_end(session, 'speech_failed'));
    }
  }

  Future<void> _end(_ListeningSession session, String? error,
      {bool flush = false}) {
    if (session.ending != null) return session.ending!;
    session.active = false;
    session.flushing = flush;
    session.timeout?.cancel();
    final done = Completer<void>();
    session.ending = done.future;
    unawaited(() async {
      var finalError = error;
      try {
        await session.started.future;
        await session.subscription?.cancel();
        await session.capture.stop();
        if (flush &&
            session.recognizer != null &&
            !session.resultSent &&
            !session.suppressResults) {
          _kick(session);
          await session.pump;
          if (!session.resultSent && !session.suppressResults) {
            final result = await session.recognizer!.finish();
            if (result.text.trim().isNotEmpty) {
              session.resultSent = true;
              session.onResult(result.text, true);
              finalError = null;
            }
          }
        }
      } catch (_) {
        finalError = 'speech_failed';
      } finally {
        session.flushing = false;
        session.queue.clear();
        try {
          await session.recognizer?.close();
        } catch (_) {
          finalError = 'speech_failed';
        }
        session.endingError = finalError;
        if (identical(_session, session)) _session = null;
        try {
          session.onDone(finalError);
        } finally {
          done.complete();
        }
      }
    }());
    return done.future;
  }

  @override
  Future<void> stop() async {
    _generation++;
    final session = _session;
    if (session != null) await _end(session, null, flush: true);
  }

  @override
  Future<void> cancelForMute() async {
    _generation++;
    final session = _session;
    if (session == null) return;
    session.suppressResults = true;
    session.flushing = false;
    await _end(session, null);
    if (session.endingError != null) throw StateError('Microphone could not be stopped');
  }

  @override
  Future<void> cancel() async {
    _generation++;
    final session = _session;
    if (session != null) {
      session.suppressResults = true;
      session.flushing = false;
      await _end(session, null);
    }
  }
}

class _ListeningSession {
  _ListeningSession(this.capture, this.onResult, this.onDone);
  final PcmCapture capture;
  final SpeechResultCallback onResult;
  final void Function(String? error) onDone;
  final started = Completer<void>();
  final queue = BytesBuilder(copy: true);
  OfflineRecognizer? recognizer;
  StreamSubscription<Uint8List>? subscription;
  Timer? timeout;
  Future<void>? pump;
  Future<void>? ending;
  String? endingError;
  bool active = true;
  bool flushing = false;
  bool resultSent = false;
  bool suppressResults = false;
}
