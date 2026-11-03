import 'speech_io.dart';
import 'speech_input_factory_stub.dart'
    if (dart.library.io) 'speech_input_factory_io.dart' as platform;

SpeechInput createSpeechInput() => platform.createSpeechInput();
bool isLocalSpeechInput(SpeechInput input) =>
    platform.isLocalSpeechInput(input);
