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
  /// In a full implementation this method would query a search API or
  /// scrape trusted websites to retrieve an answer. For example, one could
  /// call a Google Custom Search API, extract the first couple of matching
  /// results, and compare their contents. Only when at least two sources
  /// agree would the answer be returned. If no satisfactory answer is
  /// found this method should return `null`.
  ///
  /// For this prototype it simply returns `null`, indicating that no
  /// external answer was found.
  static Future<String?> searchAnswer(String question) async {
    // TODO: Implement external web search. For now return null.
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