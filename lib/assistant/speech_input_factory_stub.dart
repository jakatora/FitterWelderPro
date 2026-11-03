import 'speech_io.dart';

SpeechInput createSpeechInput() => SystemSpeechInput();
bool isLocalSpeechInput(SpeechInput input) => false;
