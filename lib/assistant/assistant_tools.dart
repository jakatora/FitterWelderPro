// Intencja `open_tool`: zapytanie → narzędzie z rejestru (tool_registry.dart).
// Sama nawigacja — nic nie zapisuje.

import '../i18n/app_language.dart';
import '../services/help_search.dart' show normalizeForSearch;
import '../widgets/tool_registry.dart';

/// Id wpisu samego asystenta — nie otwieramy asystenta z asystenta.
const String kAssistantToolId = 'assistant';

/// Słowa, które w poleceniu nic nie mówią o narzędziu („otwórz KALKULATOR
/// heat input").
const Set<String> _genericWords = {
  'kalkulator', 'kalkulatora', 'kalkulatory', 'narzedzie', 'narzedzia',
  'ekran', 'modul', 'zakladke', 'zakladka', 'mi', 'prosze', 'tool',
  'calculator', 'screen', 'module', 'tab', 'the', 'me', 'please', 'app',
  'do', 'dla', 'for', 'to',
};

/// Najlepiej pasujące narzędzie albo null. Najpierw całe zapytanie (każde
/// słowo musi pasować — reguła wyszukiwarki), potem bez słów ogólnych, na
/// końcu suma trafień pojedynczych słów.
ToolSpec? resolveToolQuery(String query, AppLanguage lang) {
  bool usable(ToolSpec t) => t.id != kAssistantToolId;

  final direct = searchTools(query, lang).where((h) => usable(h.tool));
  if (direct.isNotEmpty) return direct.first.tool;

  final words = normalizeForSearch(query)
      .split(' ')
      .where((w) => w.length >= 2 && !_genericWords.contains(w))
      .toList();
  if (words.isEmpty) return null;

  final reduced =
      searchTools(words.join(' '), lang).where((h) => usable(h.tool));
  if (reduced.isNotEmpty) return reduced.first.tool;

  final scores = <String, int>{};
  final byId = <String, ToolSpec>{};
  for (final w in words) {
    if (w.length < 3) continue;
    for (final hit in searchTools(w, lang)) {
      if (!usable(hit.tool)) continue;
      scores[hit.tool.id] = (scores[hit.tool.id] ?? 0) + hit.score;
      byId[hit.tool.id] = hit.tool;
    }
  }
  if (scores.isEmpty) return null;
  final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
  return byId[best.key];
}
