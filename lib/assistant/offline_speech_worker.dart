import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _ModelNewC = Pointer<Void> Function(Pointer<Utf8>);
typedef _ModelNew = Pointer<Void> Function(Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _RecognizerNewC = Pointer<Void> Function(Pointer<Void>, Float);
typedef _RecognizerNew = Pointer<Void> Function(Pointer<Void>, double);
typedef _AcceptC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef _Accept = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _ResultC = Pointer<Utf8> Function(Pointer<Void>);
typedef _Result = Pointer<Utf8> Function(Pointer<Void>);

/// A recognition result emitted by Vosk. It is not a verified command.
class OfflineSpeechResult {
  const OfflineSpeechResult(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

abstract interface class OfflineRecognizer {
  Future<OfflineSpeechResult> accept(Uint8List pcm);
  Future<OfflineSpeechResult> finish();
  Future<void> close();
}

/// One Vosk recognizer, isolated from Flutter's UI thread.
///
/// The caller must await each [accept] before submitting the next chunk.
/// This bounds queued audio: overlapping requests fail rather than buffering
/// an unlimited microphone stream. The caller owns microphone capture and
/// must stop it before [close]. This class never logs or stores audio/text.
class OfflineSpeechWorker implements OfflineRecognizer {
  OfflineSpeechWorker._(this._events, this._errors, this._exits);

  static const maxChunkBytes = 32000; // One second of 16 kHz mono PCM16.
  final ReceivePort _events;
  final ReceivePort _errors;
  final ReceivePort _exits;
  Isolate? _isolate;
  late final SendPort _commands;
  final _ready = Completer<SendPort>();
  Completer<OfflineSpeechResult>? _pending;
  Future<void>? _closeFuture;
  bool _closed = false;
  bool _finishing = false;

  static Future<OfflineSpeechWorker> open({
    required String libraryPath,
    required String modelPath,
  }) async {
    final worker =
        OfflineSpeechWorker._(ReceivePort(), ReceivePort(), ReceivePort());
    worker._events.listen(worker._onEvent);
    worker._errors.listen((_) => worker._fail());
    worker._exits.listen((_) {
      if (!worker._closed && !worker._finishing) worker._fail();
    });
    try {
      worker._isolate = await Isolate.spawn(
          _offlineSpeechMain, [worker._events.sendPort, libraryPath, modelPath],
          onError: worker._errors.sendPort, onExit: worker._exits.sendPort);
      worker._commands =
          await worker._ready.future.timeout(const Duration(seconds: 30));
      return worker;
    } catch (_) {
      worker._closed = true;
      worker._isolate?.kill(priority: Isolate.immediate);
      worker._disposePorts();
      rethrow;
    }
  }

  void _onEvent(dynamic event) {
    if (event is SendPort && !_ready.isCompleted) {
      _ready.complete(event);
      return;
    }
    if (event is List &&
        event.length == 3 &&
        event[0] == 'result' &&
        event[1] is String &&
        event[2] is bool) {
      final pending = _pending;
      _pending = null;
      pending?.complete(
          OfflineSpeechResult(event[1] as String, isFinal: event[2] as bool));
      return;
    }
    _fail();
  }

  void _fail() {
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Offline speech unavailable'));
    }
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Offline speech failed'));
    }
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _disposePorts();
  }

  Future<OfflineSpeechResult> _request(Object command) {
    if (_closed || _finishing) throw StateError('Offline speech is closed');
    if (_pending != null) {
      throw StateError('Previous audio is still processing');
    }
    final response = Completer<OfflineSpeechResult>();
    _pending = response;
    _commands.send(command);
    return response.future;
  }

  /// 16-bit little-endian, mono PCM at 16 kHz.
  @override
  Future<OfflineSpeechResult> accept(Uint8List pcm) {
    if (pcm.isEmpty || pcm.length.isOdd || pcm.length > maxChunkBytes) {
      throw ArgumentError('Expected 1–32000 bytes of complete PCM16 samples');
    }
    return _request(TransferableTypedData.fromList([pcm]));
  }

  /// Flush the current utterance. The worker may still be closed afterwards.
  @override
  Future<OfflineSpeechResult> finish() => _request('finish');

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _finishing = true;
    final pending = _pending;
    if (pending != null) {
      try {
        await pending.future;
      } catch (_) {/* worker already failed */}
    }
    if (_closed) return;
    final response = Completer<OfflineSpeechResult>();
    _pending = response;
    _commands.send('close');
    try {
      await response.future.timeout(const Duration(seconds: 10));
    } finally {
      _closed = true;
      _isolate?.kill(priority: Isolate.immediate);
      _disposePorts();
    }
  }

  void _disposePorts() {
    _events.close();
    _errors.close();
    _exits.close();
  }
}

void _offlineSpeechMain(List<Object> arguments) {
  final out = arguments[0] as SendPort;
  Pointer<Void> model = nullptr;
  Pointer<Void> recognizer = nullptr;
  _Free? freeModel;
  _Free? freeRecognizer;
  ReceivePort? input;
  void cleanup() {
    if (recognizer != nullptr) {
      freeRecognizer?.call(recognizer);
      recognizer = nullptr;
    }
    if (model != nullptr) {
      freeModel?.call(model);
      model = nullptr;
    }
    input?.close();
  }

  try {
    final dll = DynamicLibrary.open(arguments[1] as String);
    final modelNew =
        dll.lookupFunction<_ModelNewC, _ModelNew>('vosk_model_new');
    freeModel = dll.lookupFunction<_FreeC, _Free>('vosk_model_free');
    final recognizerNew = dll
        .lookupFunction<_RecognizerNewC, _RecognizerNew>('vosk_recognizer_new');
    freeRecognizer = dll.lookupFunction<_FreeC, _Free>('vosk_recognizer_free');
    final accept = dll
        .lookupFunction<_AcceptC, _Accept>('vosk_recognizer_accept_waveform');
    final partial =
        dll.lookupFunction<_ResultC, _Result>('vosk_recognizer_partial_result');
    final result =
        dll.lookupFunction<_ResultC, _Result>('vosk_recognizer_result');
    final finalResult =
        dll.lookupFunction<_ResultC, _Result>('vosk_recognizer_final_result');
    final setLog = dll.lookupFunction<Void Function(Int32), void Function(int)>(
        'vosk_set_log_level');
    setLog(-1);
    final path = (arguments[2] as String).toNativeUtf8();
    try {
      model = modelNew(path);
    } finally {
      calloc.free(path);
    }
    if (model == nullptr) throw StateError('Model unavailable');
    recognizer = recognizerNew(model, 16000);
    if (recognizer == nullptr) throw StateError('Recognizer unavailable');
    input = ReceivePort();
    out.send(input.sendPort);
    input.listen((dynamic message) {
      try {
        if (message is TransferableTypedData) {
          final bytes = message.materialize().asUint8List();
          final buffer = calloc<Uint8>(bytes.length);
          try {
            buffer.asTypedList(bytes.length).setAll(0, bytes);
            final status = accept(recognizer, buffer, bytes.length);
            if (status < 0) throw StateError('Audio rejected');
            final data = jsonDecode(
                (status == 1 ? result(recognizer) : partial(recognizer))
                    .toDartString());
            final text = data[status == 1 ? 'text' : 'partial'];
            if (text is! String) throw const FormatException();
            out.send(['result', text, status == 1]);
          } finally {
            calloc.free(buffer);
          }
        } else if (message == 'finish') {
          final data = jsonDecode(finalResult(recognizer).toDartString());
          final text = data['text'];
          if (text is! String) throw const FormatException();
          out.send(['result', text, true]);
        } else if (message == 'close') {
          cleanup();
          out.send(['result', '', true]);
        } else {
          throw StateError('Invalid speech request');
        }
      } catch (_) {
        cleanup();
        out.send(['error']);
      }
    });
  } catch (_) {
    cleanup();
    out.send(['error']);
  }
}
