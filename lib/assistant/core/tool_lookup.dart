// Szukanie narzędzi dla asystenta — cienka warstwa nad `searchTools`
// z rejestru (lib/widgets/tool_registry.dart, NIE edytujemy go tutaj).
//
// • [findTools] — wyniki `searchTools` z pamięcią (mózg pyta wiele razy
//   o te same słowa; wyszukiwarka zwija ~75 tytułów przy każdym wywołaniu);
// • [suggestTools] — 3 propozycje dla „nie rozumiem": każde słowo treści
//   osobno (searchTools wymaga, żeby pasowały WSZYSTKIE słowa zapytania),
//   wyniki sumowane;
// • [openFollowUp] — chip „otwórz X".

import '../../i18n/app_language.dart';
import '../../services/help_search.dart' show normalizeForSearch;
import '../../widgets/tool_registry.dart';
import 'skill.dart';

final Map<String, List<ToolSearchHit>> _memo = {};
const int _memoLimit = 512;

/// `searchTools` z pamięcią wyników (klucz: język + zapytanie zwinięte).
List<ToolSearchHit> findTools(String query, AppLanguage lang) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];
  final key = '${lang.name}|$q';
  final cached = _memo[key];
  if (cached != null) return cached;
  if (_memo.length >= _memoLimit) _memo.clear();
  return _memo[key] = List.unmodifiable(searchTools(q, lang));
}

/// Tytuł narzędzia w języku [lang].
String toolTitle(ToolSpec t, AppLanguage lang) =>
    lang == AppLanguage.en ? t.titleEn : t.titlePl;

/// Tytuł narzędzia w obu językach.
AssistantText toolTitleText(ToolSpec t) => AssistantText(t.titlePl, t.titleEn);

/// Chip „otwórz X" (wypowiedź w języku [lang]).
FollowUp openFollowUp(ToolSpec t, AppLanguage lang) => FollowUp(
      toolTitleText(t),
      lang == AppLanguage.en ? 'open ${t.titleEn}' : 'otwórz ${t.titlePl}',
    );

/// Słowa bez treści: zaimki, spójniki, pytajniki, grzeczności, czasowniki
/// „otwórz/pokaż" i słowa ogólne („narzędzie", „kalkulator").
const Set<String> kAssistantStopWords = {
  // PL
  'a', 'i', 'o', 'w', 'z', 'ze', 'na', 'do', 'od', 'po', 'za', 'dla', 'pod',
  'nad', 'przy', 'bez', 'jak', 'jaki', 'jaka', 'jakie', 'jakiej', 'jakiego',
  'co', 'czy', 'ile', 'gdzie', 'kiedy', 'dlaczego', 'czemu', 'ktory',
  'ktora', 'ktore', 'to', 'ten', 'ta', 'te', 'tu', 'tutaj', 'jest', 'sa',
  'sie', 'mi', 'mnie', 'mam', 'masz', 'moge', 'mozna', 'prosze', 'powiedz',
  'hej', 'ok', 'okej', 'asystent', 'asystencie', 'cos', 'chyba', 'moze',
  'no', 'eee', 'yyy', 'tak', 'nie', 'otworz', 'pokaz', 'uruchom', 'wlacz',
  'przejdz', 'idz', 'znajdz', 'narzedzie', 'narzedzia', 'modul', 'modulu',
  'ekran', 'kalkulator', 'kalkulatora', 'aplikacja', 'aplikacji', 'zakladka',
  'zakladke', 'okno', 'moj', 'moja', 'moje', 'twoj', 'jego', 'tego', 'tej',
  // EN
  'the', 'an', 'of', 'in', 'on', 'at', 'for', 'with', 'is', 'are', 'what',
  'how', 'why', 'when', 'where', 'which', 'can', 'does', 'my', 'me',
  'you', 'your', 'please', 'hey', 'open', 'show', 'launch', 'start', 'go',
  'take', 'find', 'tool', 'tools', 'screen', 'module', 'calculator', 'app',
  'and', 'or', 'it', 'this', 'that', 'there', 'here', 'some', 'something',
  'maybe', 'yes',
};

final _numberRe = RegExp(r'^[\d.]+$');

/// Słowa treści wypowiedzi: bez słów-wypełniaczy, liczb i słów < 3 znaków.
List<String> contentWords(Utterance u) => [
      for (final t in u.tokens)
        if (t.length >= 3 &&
            !kAssistantStopWords.contains(t) &&
            !_numberRe.hasMatch(t))
          t,
    ];

/// Do [limit] propozycji narzędzi dla wypowiedzi, której nikt nie zrozumiał:
/// każde słowo treści szukane osobno, wyniki sumowane.
List<FollowUp> suggestTools(Utterance u, {int limit = 3}) {
  final scores = <String, int>{};
  final order = <String, int>{};
  for (final w in contentWords(u)) {
    for (final hit in findTools(w, u.lang)) {
      scores[hit.tool.id] = (scores[hit.tool.id] ?? 0) + hit.score;
      order.putIfAbsent(hit.tool.id, () => order.length);
    }
  }
  final ids = scores.keys.toList()
    ..sort((a, b) {
      final s = scores[b]!.compareTo(scores[a]!);
      return s != 0 ? s : order[a]!.compareTo(order[b]!);
    });
  return [
    for (final id in ids.take(limit))
      if (toolById(id) case final t?) openFollowUp(t, u.lang),
  ];
}
