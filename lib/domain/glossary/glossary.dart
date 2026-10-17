// Słownik spawalniczy PL · EN · DE · NL · NO — model i wyszukiwarka.
//
// Dane (const) są w lib/data/welding_glossary.dart. Tu jest tylko:
//  • model terminu ([GlossaryTerm]) i kategorie,
//  • normalizacja tekstu do szukania ([normalizeGlossary]) — bez wielkości
//    liter i znaków diakrytycznych wszystkich pięciu języków,
//  • indeks zbudowany raz (leniwie) i ranking wyników ([GlossaryIndex]).
//
// Szukanie idzie po wszystkich językach naraz, po synonimach, numerach ISO
// (6520-1, 4063) i kodach (PA, VT, WPS…). Każde słowo zapytania musi wystąpić
// w terminie (jako fragment); wyżej idą trafienia dokładne i od początku.

/// Języki danych słownika (interfejs aplikacji jest tylko PL/EN).
enum GlossaryLang {
  pl('PL', 'polski', 'Polish'),
  en('EN', 'angielski', 'English'),
  de('DE', 'niemiecki', 'German'),
  nl('NL', 'niderlandzki', 'Dutch'),
  no('NO', 'norweski (bokmål)', 'Norwegian (Bokmål)');

  const GlossaryLang(this.code, this.namePl, this.nameEn);

  /// Krótki kod na przyciskach i przy tłumaczeniach.
  final String code;
  final String namePl;
  final String nameEn;

  /// Języki, które monter może wybrać jako „mój język docelowy”.
  static const List<GlossaryLang> targets = [
    GlossaryLang.de,
    GlossaryLang.nl,
    GlossaryLang.no,
    GlossaryLang.en,
  ];

  static GlossaryLang? parse(String? raw) {
    for (final l in GlossaryLang.values) {
      if (l.name == raw) return l;
    }
    return null;
  }
}

/// Kategorie słownika w kolejności chipów na ekranie.
enum GlossaryCategory {
  process('Procesy', 'Processes'),
  imperfection('Niezgodności', 'Imperfections'),
  joint('Złącza i rowki', 'Joints and grooves'),
  position('Pozycje', 'Positions'),
  material('Materiały i spoiwa', 'Materials and consumables'),
  piping('Rury i kształtki', 'Pipes and fittings'),
  testing('Badania i dokumenty', 'Testing and documents'),
  tools('Narzędzia', 'Tools'),
  safety('BHP', 'Health and safety'),
  phrase('Zwroty na budowę', 'Site phrases');

  const GlossaryCategory(this.titlePl, this.titleEn);

  final String titlePl;
  final String titleEn;
}

/// Jeden termin (albo zwrot) w pięciu językach.
class GlossaryTerm {
  const GlossaryTerm({
    required this.id,
    required this.category,
    required this.pl,
    required this.en,
    required this.de,
    required this.nl,
    required this.no,
    this.defPl,
    this.defEn,
    this.iso6520,
    this.iso4063,
    this.code,
    this.synonyms = const {},
  });

  /// Trwały identyfikator — trafia do ulubionych w SharedPreferences.
  final String id;
  final GlossaryCategory category;

  final String pl;
  final String en;
  final String de;
  final String nl;

  /// Norweski bokmål.
  final String no;

  /// Krótka definicja (1 zdanie), opcjonalna.
  final String? defPl;
  final String? defEn;

  /// Numer referencyjny niezgodności wg ISO 6520-1 (np. '5011').
  final String? iso6520;

  /// Numer procesu wg ISO 4063 (np. '135').
  final String? iso4063;

  /// Inny kod branżowy: pozycja (PA · 1G), skrót badania (VT), WPS, 3.1…
  final String? code;

  /// Potwierdzone synonimy / określenia warsztatowe w danym języku.
  final Map<GlossaryLang, List<String>> synonyms;

  String text(GlossaryLang lang) => switch (lang) {
        GlossaryLang.pl => pl,
        GlossaryLang.en => en,
        GlossaryLang.de => de,
        GlossaryLang.nl => nl,
        GlossaryLang.no => no,
      };

  List<String> synonymsFor(GlossaryLang lang) => synonyms[lang] ?? const [];

  /// Etykieta numeru normy do wyświetlenia, np. „ISO 6520-1: 5011”.
  String? get isoLabel {
    if (iso6520 != null) return 'ISO 6520-1: $iso6520';
    if (iso4063 != null) return 'ISO 4063: $iso4063';
    return null;
  }
}

const Map<String, String> _fold = {
  // polski
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's',
  'ź': 'z', 'ż': 'z',
  // niemiecki
  'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
  // norweski / duński
  'ø': 'o', 'å': 'a', 'æ': 'ae',
  // niderlandzki i reszta łaciny (é w „coördinator”, ë, ï…)
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ô': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u',
  'ý': 'y', 'ÿ': 'y',
  // indeksy dolne w CO₂ itd.
  '₂': '2', '₃': '3',
};

/// Tekst do porównywania: małe litery, bez diakrytyków (ą→a, ł→l, ä→a,
/// ö→o, ü→u, ß→ss, ø→o, å→a, æ→ae…), interpunkcja zamieniona na spacje,
/// wielokrotne spacje zwinięte. Cyfry zostają (numery ISO).
String normalizeGlossary(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final folded = _fold[ch];
    if (folded != null) {
      buf.write(folded);
    } else if (_isAlnum(rune)) {
      buf.write(ch);
    } else {
      buf.write(' ');
    }
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _isAlnum(int r) =>
    (r >= 0x61 && r <= 0x7a) || // a–z
    (r >= 0x30 && r <= 0x39); // 0–9

/// Warianty pisowni bez klawiatury narodowej: „ueberkopf” dla „Überkopf”,
/// „oe”/„aa” dla norweskich ø/å. Dodawane do indeksu obok formy podstawowej.
String _transliterate(String input, GlossaryLang lang) {
  final lower = input.toLowerCase();
  return switch (lang) {
    GlossaryLang.de => lower
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue'),
    GlossaryLang.no => lower.replaceAll('ø', 'oe').replaceAll('å', 'aa'),
    _ => lower,
  };
}

class _Entry {
  _Entry(this.term, this.order, this.forms, this.codes, this.haystack);

  final GlossaryTerm term;
  final int order;

  /// Znormalizowane formy (wszystkie języki + synonimy + warianty pisowni).
  final List<String> forms;

  /// Znormalizowane numery ISO i kody.
  final List<String> codes;

  /// Wszystko razem — do sprawdzania fragmentów.
  final String haystack;
}

/// Indeks wyszukiwania zbudowany raz dla danej listy terminów.
class GlossaryIndex {
  GlossaryIndex(List<GlossaryTerm> terms) : _entries = _build(terms);

  final List<_Entry> _entries;

  int get length => _entries.length;

  static List<_Entry> _build(List<GlossaryTerm> terms) {
    final out = <_Entry>[];
    for (var i = 0; i < terms.length; i++) {
      final t = terms[i];
      final forms = <String>{};
      for (final lang in GlossaryLang.values) {
        final raw = [t.text(lang), ...t.synonymsFor(lang)];
        for (final r in raw) {
          final n = normalizeGlossary(r);
          if (n.isNotEmpty) forms.add(n);
          final alt = normalizeGlossary(_transliterate(r, lang));
          if (alt.isNotEmpty) forms.add(alt);
        }
      }
      final codes = <String>{
        for (final c in [t.iso6520, t.iso4063, t.code])
          if (c != null && normalizeGlossary(c).isNotEmpty)
            normalizeGlossary(c),
      };
      final haystack = [...forms, ...codes].join(' | ');
      out.add(_Entry(t, i, forms.toList(), codes.toList(), haystack));
    }
    return out;
  }

  /// Wyniki dla [query] (puste zapytanie = wszystko w kolejności danych),
  /// zawężone do [category] i — jeśli podano — do identyfikatorów [onlyIds].
  List<GlossaryTerm> search(
    String query, {
    GlossaryCategory? category,
    Set<String>? onlyIds,
  }) {
    final q = normalizeGlossary(query);
    final tokens =
        q.isEmpty ? const <String>[] : q.split(' ').toList(growable: false);
    final scored = <({_Entry e, int score})>[];
    for (final e in _entries) {
      if (category != null && e.term.category != category) continue;
      if (onlyIds != null && !onlyIds.contains(e.term.id)) continue;
      if (tokens.isEmpty) {
        scored.add((e: e, score: 0));
        continue;
      }
      if (!tokens.every(e.haystack.contains)) continue;
      scored.add((e: e, score: _score(e, q)));
    }
    scored.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : a.e.order.compareTo(b.e.order);
    });
    return [for (final s in scored) s.e.term];
  }

  static int _score(_Entry e, String q) {
    var best = 10;
    for (final c in e.codes) {
      if (c == q) return 120;
      if (c.split(' ').any((part) => part == q)) best = 110;
      if (c.startsWith(q) && best < 90) best = 90;
    }
    for (final f in e.forms) {
      if (f == q) return 100;
      if (f.startsWith(q)) {
        if (best < 80) best = 80;
      } else if (best < 60 && f.split(' ').any((w) => w.startsWith(q))) {
        best = 60;
      } else if (best < 40 && f.contains(q)) {
        best = 40;
      }
    }
    return best;
  }
}
