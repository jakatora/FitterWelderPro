import '../data/help_entries.dart';
import '../i18n/app_language.dart';

// Lightweight search for the help knowledge base.
// Strategy: normalize query → split into terms → score each entry by which
// fields contain which term. Tags + question carry the highest weight; answer
// text is consulted last (lots of false-positive risk).
//
// We deliberately avoid Levenshtein / fuzzy distance libraries — they add bulk
// and rarely beat a well-curated tags list for short technical queries.

class HelpSearchResult {
  /// Owning category (used to render filter chips and group results).
  final HelpCategory category;
  final HelpEntry entry;

  /// Higher is better. 0 means no match.
  final int score;

  /// Tokens that actually matched, lower-cased — used by the UI to highlight
  /// the relevant words in question / answer text.
  final List<String> matchedTerms;

  const HelpSearchResult({
    required this.category,
    required this.entry,
    required this.score,
    required this.matchedTerms,
  });
}

/// Strip common Polish (and English plural) inflection suffixes so "kolano",
/// "kolana", "kolanka", "kolanami" all collapse to the same stem. Crude —
/// no real morphology — but cheap and catches the most common false-negatives
/// in routine fitter queries. We never strip below 4 chars (else "rura" →
/// "" garbage).
String _stem(String word) {
  if (word.length <= 4) return word;
  // Order matters — longest suffix first.
  const suffixes = <String>[
    'owanie', 'iastego', 'iastej', 'owego', 'owej', 'iach',
    'ami', 'iem', 'ach', 'owi', 'ego', 'emu', 'imi', 'ymi', 'owy',
    'owa', 'owe', 'iej', 'iom', 'ich', 'ych',
    'ami', 'om', 'ów', 'ie', 'ia', 'ii', 'em',
    'es', 'er', // english plurals / -er
    'y', 'i', 'u', 'a', 'e', 'o',
  ];
  for (final suf in suffixes) {
    if (word.length > suf.length + 3 && word.endsWith(suf)) {
      return word.substring(0, word.length - suf.length);
    }
  }
  return word;
}

/// Normalises a string for matching: lowercased, accents folded, punctuation
/// reduced to spaces. Polish-aware: ą→a, ż→z, etc.
String normalizeForSearch(String s) {
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.runes) {
    final c = String.fromCharCode(ch);
    switch (c) {
      case 'ą': buf.write('a'); break;
      case 'ć': buf.write('c'); break;
      case 'ę': buf.write('e'); break;
      case 'ł': buf.write('l'); break;
      case 'ń': buf.write('n'); break;
      case 'ó': buf.write('o'); break;
      case 'ś': buf.write('s'); break;
      case 'ź': buf.write('z'); break;
      case 'ż': buf.write('z'); break;
      default:
        // collapse anything non-alphanumeric to a single space so terms split
        if (RegExp(r'[a-z0-9]').hasMatch(c)) {
          buf.write(c);
        } else {
          buf.write(' ');
        }
    }
  }
  // Squash multiple spaces.
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Search the entire knowledge base. Returns results sorted by score, then
/// alphabetically by question text. An empty query returns nothing — the UI
/// shows the category tree in that case.
List<HelpSearchResult> searchHelp(
  String rawQuery,
  AppLanguage lang, {
  String? categoryFilter,
  int limit = 80,
}) {
  final query = normalizeForSearch(rawQuery);
  if (query.isEmpty) return const [];

  final terms = query.split(' ').where((t) => t.length >= 2).toList();
  if (terms.isEmpty) return const [];

  final results = <HelpSearchResult>[];

  for (final cat in kHelpCategories) {
    if (categoryFilter != null && cat.id != categoryFilter) continue;

    final catTitleN = normalizeForSearch(cat.title(lang));

    for (final entry in cat.entries) {
      final qN = normalizeForSearch(entry.question(lang));
      final aN = normalizeForSearch(entry.answer(lang));
      final tagsN = entry.tags.map((t) => normalizeForSearch(t)).toList();

      var score = 0;
      final matched = <String>{};

      // Pre-compute term + stem pairs so each term gives us one "exact"
      // match check and one "stem fallback" check ("kolano" stems to "kolan"
      // and matches the tag "kolana" / "kolanka" / "kolanami").
      final termStems =
          terms.map((t) => (term: t, stem: _stem(t))).toList(growable: false);

      for (final ts in termStems) {
        final term = ts.term;
        final stem = ts.stem;
        // Tag matches — strongest signal. Exact > prefix > contains > stem.
        var tagHit = false;
        for (final tag in tagsN) {
          if (tag == term) {
            score += 12;
            tagHit = true;
            break;
          }
          if (tag.startsWith(term)) {
            score += 8;
            tagHit = true;
            break;
          }
          if (tag.contains(term)) {
            score += 5;
            tagHit = true;
            break;
          }
          // Stem fallback only if the term is long enough to matter and the
          // stem differs from the term itself.
          if (stem.length >= 4 && stem != term && tag.contains(stem)) {
            score += 4;
            tagHit = true;
            break;
          }
        }
        if (tagHit) matched.add(term);

        // Question — strong signal as it's what the user is "asking".
        if (qN.contains(term)) {
          score += 10;
          matched.add(term);
        } else if (stem.length >= 4 && stem != term && qN.contains(stem)) {
          // Stemmed question hit — half-weight of literal.
          score += 6;
          matched.add(term);
        }

        // Category title — context boost.
        if (catTitleN.contains(term)) score += 2;

        // Answer — weakest, but useful for buried technical terms.
        if (aN.contains(term)) {
          score += 3;
          matched.add(term);
        } else if (stem.length >= 4 && stem != term && aN.contains(stem)) {
          score += 2;
          matched.add(term);
        }
      }

      // Multi-term AND bonus — results that hit every term in the query
      // beat scatter-hit results with the same per-term score.
      if (matched.length == terms.length && terms.length > 1) {
        score += 6 * terms.length;
      }

      // Require at least one of the query terms to actually match something.
      if (score > 0 && matched.isNotEmpty) {
        // Bonus: phrase match (the full query appears as a substring of question)
        // beats scattered word matches.
        if (qN.contains(query)) score += 15;

        results.add(HelpSearchResult(
          category: cat,
          entry: entry,
          score: score,
          matchedTerms: matched.toList(),
        ));
      }
    }
  }

  results.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.entry.question(lang).compareTo(b.entry.question(lang));
  });

  if (results.length > limit) return results.sublist(0, limit);
  return results;
}
