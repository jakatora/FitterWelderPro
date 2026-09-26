// Pierwsza linia obrony przed treściami obraźliwymi na publicznym czacie.
//
// Apple przy treściach od użytkowników (wytyczna 1.2) wymaga trzech rzeczy:
// metody FILTROWANIA treści obraźliwych, mechanizmu ZGŁASZANIA i możliwości
// BLOKOWANIA osób. Zgłaszanie i blokowanie mamy — to jest ta pierwsza.
//
// Świadome ograniczenia, żeby nikt nie brał tego za moderację:
//   • filtrujemy przy WYSYŁCE, nie przy wyświetlaniu — stare wiadomości z
//     serwera przechodzą bez zmian, od nich jest zgłaszanie i blokowanie;
//   • lista jest krótka i celuje w wyzwiska oraz treści seksualne, a nie w
//     „brzydkie słowa" w ogóle: monter, który napisze „ciężka robota", ma
//     dostać wysłać, a nie kazanie;
//   • dopasowujemy CAŁE słowa po normalizacji (małe litery, polskie znaki
//     sprowadzone do ASCII, podstawowy leetspeak), więc „chujowy" łapiemy, a
//     „Chełm" nie.
//
// To sito, nie sąd. Sądem jest człowiek po drugiej stronie zgłoszenia.

class ContentFilter {
  ContentFilter._();

  /// Wulgaryzmy i wyzwiska. Rdzenie, nie pełne formy — dopasowujemy z
  /// dowolną końcówką fleksyjną (`chuj` → `chujowy`, `chujem`).
  static const List<String> _blockedRoots = [
    // PL — wyzwiska i wulgaryzmy
    'kurwa', 'kurwi', 'chuj', 'pizda', 'pierdol', 'jebac', 'jeban', 'jebie',
    'skurwysyn', 'zjeb', 'debil', 'kretyn', 'idiot', 'cwel', 'ciota',
    'pedzio', 'pedziu', 'pedryl', 'dziwka', 'gowno',
    // Świadomie NIE ma tu słów, które na budowie znaczą coś zwykłego:
    //   • „szmata" — szmata do przecierania rowka;
    //   • „pedał" / „pedal" — pedał nożny od TIG-a (foot pedal). Wyzwisko
    //     łapiemy tylko w zwrocie do kogoś („ty pedale") — [_blockedPhrases];
    //   • „sutki" — złączki nyplowe („trzy sutki 1/2 cala");
    //   • „dupa" — brzydkie słowo, ale nie wyzwisko; sito celuje w wyzwiska.
    // EN — wyzwiska i mowa nienawiści
    'fuck', 'cunt', 'bitch', 'nigger', 'faggot', 'retard', 'whore',
  ];

  /// Zwroty, które są wyzwiskiem tylko w całości — pojedyncze słowo jest
  /// żargonem. Dopasowanie po normalizacji, od granicy słowa.
  static final List<(String, RegExp)> _blockedPhrases = [
    ('ty pedal', RegExp(r'(^|[^a-z])ty\s+pedal[a-z]*')),
  ];

  /// Słowa branżowe, które zaczynają się jak rdzeń z listy blokad, a nie są
  /// wyzwiskiem. Porównanie z POCZĄTKIEM słowa po normalizacji.
  static const List<String> _safePrefixes = [
    'idiotood', // „idiotoodporny" — złącze, którego nie da się źle wkręcić
    'retardan', // „fire retardant" — powłoka ogniochronna
    'retarder', // „retarder" — opóźniacz (farby, beton)
    'retardat', // „retardation" — opóźnienie (zapłonu, wiązania)
  ];

  static final RegExp _word = RegExp('[a-z]+');

  static const Map<String, String> _leet = {
    '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', r'$': 's',
  };

  static const Map<String, String> _diacritics = {
    'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
    'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
  };

  static String _normalize(String input) {
    final buf = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buf.write(_diacritics[ch] ?? _leet[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Zwraca pierwsze znalezione słowo łamiące zasady albo `null`.
  /// Zwracamy je, żeby dało się je pokazać w logu moderacji — nie użytkownikowi.
  static String? firstOffense(String text) {
    final normalized = _normalize(text);
    // Całe słowa (ciągi liter po normalizacji). Rdzeń musi stać na początku
    // słowa; z tyłu dopuszczamy końcówkę fleksyjną („chujowy", „debilu").
    final words = _word
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .where((w) => !_safePrefixes.any(w.startsWith))
        .toList(growable: false);
    for (final root in _blockedRoots) {
      if (words.any((w) => w.startsWith(root))) return root;
    }
    for (final (label, re) in _blockedPhrases) {
      if (re.hasMatch(normalized)) return label;
    }
    return null;
  }

  static bool isObjectionable(String text) => firstOffense(text) != null;
}
