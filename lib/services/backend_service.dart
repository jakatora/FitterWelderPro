import 'dart:async';

/// A very simple backend service used by the tutor module.
///
/// This service exposes two operations:
///  * [getAnswer] returns a cached answer for a given question if one exists.
///  * [getOrSearchAnswer] first tries to get a cached answer. If it does
///    not find one then it invokes [searchAnswer] to look up an answer
///    externally. When an external answer is found it is cached via
///    [addAnswer] for future queries.
///  *
/// In this prototype the external search is intentionally left
/// unimplemented. To add real network functionality one could use the
/// `http` package to call a search API or scrape trusted sources.
class BackendService {
  /// In-memory store of question/answer pairs. Keys are normalized to
  /// lowercase to allow case-insensitive lookups.
  static final Map<String, String> _answers = {};

  /// Returns a cached answer for the given [question], or `null` if none
  /// exists. The lookup is case-insensitive and ignores leading/trailing
  /// whitespace.
  static Future<String?> getAnswer(String question) async {
    return _answers[question.toLowerCase().trim()];
  }

  /// Caches an [answer] for the supplied [question]. The question key is
  /// normalized to lowercase with whitespace trimmed.
  static Future<void> addAnswer(String question, String answer) async {
    _answers[question.toLowerCase().trim()] = answer;
  }

  /// Performs an external search for an answer to [question].
  ///
  /// Reserved hook for an external answer source. Today this is a stub —
  /// the tutor flow falls back to the local cache when this returns null,
  /// which is the only intended behaviour. Out of scope to add a real
  /// search backend here; if anyone wants that, route the call through
  /// the AI chat service so we keep one backend client.
  static Future<String?> searchAnswer(String question) async {
    return null;
  }

  /// Retrieves a cached answer for [question] or searches externally.
  ///
  /// If a cached answer exists it will be returned immediately. Otherwise
  /// [searchAnswer] is invoked. When a non-null result is returned from
  /// [searchAnswer], it is cached via [addAnswer] before being returned.
  static Future<String?> getOrSearchAnswer(String question) async {
    final cached = await getAnswer(question);
    if (cached != null) return cached;

    final external = await searchAnswer(question);
    if (external != null) {
      await addAnswer(question, external);
      return external;
    }
    return null;
  }
}