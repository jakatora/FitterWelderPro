import '../../feedback/feedback_consent.dart';
import '../../feedback/feedback_signal.dart';
import '../../feedback/feedback_store.dart';
import '../../feedback/feedback_uploader.dart';
import '../../i18n/app_language.dart';

/// Captures missing capabilities locally. Upload is independently opt-in;
/// private report access belongs to the backend, never to this client.
class AssistantFeedbackRecorder {
  AssistantFeedbackRecorder({Future<void> Function()? upload})
      : _upload = upload ?? _flush;
  final Future<void> Function() _upload;
  final _seen = <String>{};
  static Future<void> _flush() async {
    await FeedbackUploader.instance.flush();
  }

  Future<void> missing(String text,
      {String? tool, String? skill, required AppLanguage lang}) async {
    try {
      final signal = FeedbackSignal.create(
          kind: FeedbackKind.notUnderstood,
          text: text,
          tool: tool,
          skill: skill,
          lang: lang);
      final key = '${signal.tool}:${signal.skill}:${signal.text}';
      if (_seen.contains(key) || _seen.length >= 50) return;
      if (!await FeedbackStore.instance.add(signal)) return;
      _seen.add(key);
      if ((await FeedbackConsent.instance.read()).granted) await _upload();
    } catch (_) {
      // Reporting a failure must never break the user's task.
    }
  }

  /// A problem the user reported to the author (explicit report, complaint,
  /// "can't find"). Returns whether it will leave the phone (upload consent),
  /// or `null` when it could not be stored — the caller must not claim it was.
  Future<bool?> report(String text, FeedbackKind kind,
      {String? tool, required AppLanguage lang}) async {
    try {
      final signal =
          FeedbackSignal.create(kind: kind, text: text, tool: tool, lang: lang);
      final key = '${signal.kind.name}:${signal.tool}:${signal.text}';
      if (!_seen.contains(key)) {
        if (_seen.length >= 50 || !await FeedbackStore.instance.add(signal)) {
          return null;
        }
        _seen.add(key);
      }
      final granted = (await FeedbackConsent.instance.read()).granted;
      if (granted) {
        // The upload retries later on failure; the report is already stored.
        _upload().catchError((_) {});
      }
      return granted;
    } catch (_) {
      return null;
    }
  }
}
