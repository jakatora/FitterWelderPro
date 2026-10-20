// `knowledge` — fallback wiedzy: Pomoc (`searchHelp`) i słownik spawalniczy
// (`weldingGlossaryIndex`). Odpowiedź to tekst z danych aplikacji, bez
// własnych liczb asystenta.
//
// Ostrożność: trafienie z Pomocy musi pokryć większość słów treści
// wypowiedzi — jedno wspólne słowo („spoina") to za mało, wtedy lepsze jest
// „nie rozumiem" z propozycjami niż odpowiedź nie na temat.

import '../../../data/help_entries.dart';
import '../../../data/welding_glossary.dart';
import '../../../domain/glossary/glossary.dart';
import '../../../i18n/app_language.dart';
import '../../../services/help_search.dart';
import '../../../utils/decimal_parse.dart';
import '../../../widgets/tool_registry.dart' show toolById;
import '../../core/skill.dart';
import '../../core/tool_lookup.dart';

/// Język docelowy tłumaczenia z wypowiedzi.
final Map<RegExp, GlossaryLang> _targets = {
  RegExp(r'\b(?:po niemiecku|niemieck\w*|in german|german)\b'): GlossaryLang.de,
  RegExp(r'\b(?:po niderlandzku|po holendersku|niderlandzk\w*|holendersk\w*|'
      r'in dutch|dutch|flemish)\b'): GlossaryLang.nl,
  RegExp(r'\b(?:po norwesku|norwesk\w*|in norwegian|norwegian)\b'):
      GlossaryLang.no,
  RegExp(r'\b(?:po angielsku|angielsk\w*|in english|english)\b'):
      GlossaryLang.en,
  RegExp(r'\b(?:po polsku|polsk\w*|in polish|polish)\b'): GlossaryLang.pl,
};

final _translateRe = RegExp(r'\b(?:przetlumacz\w*|tlumaczeni\w*|translat\w*|'
    r'jak (?:jest|sie mowi|sie nazywa|powiedziec)|how do you say)\b');

final _definitionRe = RegExp(
    r'^(?:(?:a|i|hej|ok|powiedz)\s+)*(?:co to (?:jest|znaczy|za)|czym jest|'
    r'co oznacza|what is|what are|what does|define|definition of)\s+');

/// Słowa wokół terminu w pytaniu o tłumaczenie / definicję.
const Set<String> _frame = {
  'i',
  'and',
  'lub',
  'or',
  'otworz',
  'pokaz',
  'open',
  'show',
  'spawalniczy',
  'slownik',
  'slowniku',
  'slownika',
  'haslo',
  'hasla',
  'glossary',
  'dictionary',
  'jezyk',
  'jezyku',
  'language',
  'into',
  'znajdz',
  'find',
  'wyszukaj',
  'lookup',
  'look',
  'up',
  'w',
  'jak',
  'jest',
  'sie',
  'mowi',
  'nazywa',
  'powiedziec',
  'po',
  'co',
  'to',
  'znaczy',
  'oznacza',
  'czym',
  'za',
  'slowo',
  'termin',
  'przetlumacz',
  'tlumaczenie',
  'niemiecku',
  'niderlandzku',
  'holendersku',
  'norwesku',
  'angielsku',
  'polsku',
  'niemiecki',
  'norweski',
  'angielski',
  'polski',
  'what',
  'is',
  'are',
  'does',
  'mean',
  'means',
  'in',
  'german',
  'dutch',
  'norwegian',
  'english',
  'polish',
  'how',
  'do',
  'you',
  'say',
  'translate',
  'the',
  'a',
  'an',
  'word',
  'term',
  'define',
  'definition',
  'of',
  'na',
  'prosze',
  'powiedz',
  'mi',
  'please',
  'tell',
  'me',
  'hej',
  'ok',
};

String glossaryQuery(Utterance u) => [
      for (final t in u.tokens)
        if (!_frame.contains(t) &&
            !RegExp(r'^(?:niemieck|niderlandzk|holendersk|norwesk|angielsk|polsk)\w*$')
                .hasMatch(t))
          t,
    ].join(' ');

GlossaryLang? _target(String folded) {
  for (final e in _targets.entries) {
    if (e.key.hasMatch(folded)) return e.value;
  }
  return null;
}

List<GlossaryLang> glossaryTargets(String folded) => [
      for (final e in _targets.entries)
        if (e.key.hasMatch(folded)) e.value
    ];

(HelpCategory, HelpEntry)? _helpById(String id) {
  for (final c in kHelpCategories) {
    for (final e in c.entries) {
      if (e.id == id) return (c, e);
    }
  }
  return null;
}

GlossaryTerm? _termById(String id) {
  for (final t in kWeldingGlossary) {
    if (t.id == id) return t;
  }
  return null;
}

/// Posortowane słowa Pomocy (pytania, odpowiedzi, tagi, kategorie) per język.
final Map<AppLanguage, List<String>> _vocabularies = {};

List<String> _helpVocabulary(AppLanguage lang) => _vocabularies[lang] ??= () {
      final words = <String>{};
      void add(String s) {
        for (final w in normalizeForSearch(s).split(' ')) {
          if (w.isNotEmpty) words.add(w);
        }
      }

      for (final c in kHelpCategories) {
        add(c.title(lang));
        for (final e in c.entries) {
          add(e.question(lang));
          add(e.answer(lang));
          e.tags.forEach(add);
        }
      }
      return words.toList()..sort();
    }();

const Map<GlossaryLang, String> _inLangPl = {
  GlossaryLang.pl: 'Po polsku',
  GlossaryLang.en: 'Po angielsku',
  GlossaryLang.de: 'Po niemiecku',
  GlossaryLang.nl: 'Po niderlandzku',
  GlossaryLang.no: 'Po norwesku',
};

const Map<GlossaryLang, String> _inLangEn = {
  GlossaryLang.pl: 'In Polish',
  GlossaryLang.en: 'In English',
  GlossaryLang.de: 'In German',
  GlossaryLang.nl: 'In Dutch',
  GlossaryLang.no: 'In Norwegian',
};

/// Słowo i jego rdzenie dla odmiany („porowatości" → „porowatosc", „porowatos").
List<String> _stems(String w) => [
      w,
      if (w.length >= 5) w.substring(0, w.length - 1),
      if (w.length >= 6) w.substring(0, w.length - 2),
    ];

/// Odpowiedź Pomocy bez znaczników pogrubienia (`**MMA**`) — karta i mowa
/// dostają zwykły tekst.
String _plain(String s) => s.replaceAll('**', '');

/// Czy jakieś słowo Pomocy zaczyna się od [term] albo od jego rdzenia
/// (odmiana: „porowatości" → „porowatosc").
bool _inVocabulary(List<String> vocab, String term) {
  bool prefix(String p) {
    var lo = 0, hi = vocab.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (vocab[mid].compareTo(p) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < vocab.length && vocab[lo].startsWith(p);
  }

  if (prefix(term)) return true;
  if (term.length >= 5 && prefix(term.substring(0, term.length - 1))) {
    return true;
  }
  return term.length >= 6 && prefix(term.substring(0, term.length - 2));
}

/// Pierwsze zdanie (do ~220 znaków) — do przeczytania na głos.
String _firstSentence(String s) {
  final m = RegExp(r'^(.{20,220}?[.!?])(?:\s|$)', dotAll: true).firstMatch(s);
  if (m != null) return m[1]!;
  return s.length <= 220 ? s : '${s.substring(0, 217)}…';
}

class KnowledgeSkill extends AssistantSkill {
  @override
  String get id => 'knowledge';
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.a;
  @override
  int? get fallbackOrder => 3;

  @override
  List<SkillExample> get examples => const [
        SkillExample('Jaki przepływ gazu osłonowego ustawić?',
            'What shielding gas flow should be set?'),
        SkillExample('Ile czasu powinien trwać back purge?',
            'How long should back purge last?'),
      ];

  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('dodaj spoinę 12'),
        SkillRejection('jaka jest średnica dn40', routesTo: 'pipe.od'),
        SkillRejection('otwórz słownik spawalniczy', routesTo: 'tool.open'),
      ];

  @override
  SkillMatch? match(Utterance u, AssistantContext ctx) {
    final f = u.folded;
    final target = _target(f);
    if (target != null || _translateRe.hasMatch(f)) {
      final term = glossaryQuery(u);
      if (term.isNotEmpty) {
        final hits = weldingGlossaryIndex.search(term);
        if (hits.isNotEmpty) {
          return SkillMatch(this, 0.8,
              slots: {
                'kind': 'glossary',
                'id': hits.first.id,
                'also': [for (final h in hits.skip(1).take(2)) h.id],
                'target': target?.name,
              },
              utterance: u);
        }
      }
    }

    // A concrete measurement needs a calculation skill, not a generic FAQ
    // selected just because it contains one word such as "porosity".
    const units = {
      'a',
      'amper',
      'amperow',
      'amps',
      'v',
      'volt',
      'volts',
      'mm',
      'cm',
      'kg',
      'bar',
      'psi',
      'min',
      'sekund',
      'seconds'
    };
    for (var i = 0; i + 1 < u.tokens.length; i++) {
      if (parseDecimal(u.tokens[i]) != null &&
          units.contains(u.tokens[i + 1])) {
        return null;
      }
    }
    final help = _helpHit(u);
    if (help != null) {
      return SkillMatch(this, 0.65,
          slots: {'kind': 'help', 'id': help.entry.id}, utterance: u);
    }

    if (_definitionRe.hasMatch(f)) {
      final term = glossaryQuery(u);
      if (term.isNotEmpty) {
        final hits = weldingGlossaryIndex.search(term);
        final withDef = [
          for (final h in hits.take(3))
            if (h.defPl != null && h.defEn != null) h,
        ];
        if (withDef.isNotEmpty) {
          return SkillMatch(this, 0.6,
              slots: {'kind': 'definition', 'id': withDef.first.id},
              utterance: u);
        }
      }
    }
    return null;
  }

  /// Wpis Pomocy (z 3 najlepszych `searchHelp`), którego PYTANIE albo tagi
  /// pokrywają ≥ 60 % słów treści wypowiedzi. Trafienia tylko w treści
  /// odpowiedzi się nie liczą — „jaki prąd na TIG nierdzewka" nie może
  /// dostać odpowiedzi o filtrze przyłbicy, bo w niej padają „TIG" i „prąd".
  HelpSearchResult? _helpHit(Utterance u) {
    final content = contentWords(u);
    if (content.isEmpty) return null;
    // Tani filtr przed pełnym `searchHelp` (≈ 3 ms): słowa, których nie ma
    // nigdzie w Pomocy, i tak nie dadzą pokrycia.
    final vocab = _helpVocabulary(u.lang);
    final possible = content.where((w) => _inVocabulary(vocab, w)).length;
    if (possible / content.length < 0.6) return null;
    for (final r in searchHelp(u.raw, u.lang, limit: 3)) {
      if (r.score < 20) break;
      final q = normalizeForSearch(r.entry.question(u.lang));
      final tags = [for (final t in r.entry.tags) normalizeForSearch(t)];
      final covered = content
          .where((w) => _stems(w)
              .any((s) => q.contains(s) || tags.any((t) => t.contains(s))))
          .length;
      if (covered / content.length >= 0.6) return r;
    }
    return null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final kind = m.slots['kind'];
    final id = m.slots['id'] as String;
    if (kind == 'help') {
      final found = _helpById(id);
      if (found == null) return _missing();
      final (cat, e) = found;
      final qPl = e.question(AppLanguage.pl), qEn = e.question(AppLanguage.en);
      final aPl = _plain(e.answer(AppLanguage.pl)),
          aEn = _plain(e.answer(AppLanguage.en));
      return AnswerResult(AssistantAnswer(
        text: AssistantText('$qPl\n$aPl', '$qEn\n$aEn'),
        spoken: AssistantText(_firstSentence(aPl), _firstSentence(aEn)),
        source: AssistantText('Pomoc: ${cat.title(AppLanguage.pl)}',
            'Help: ${cat.title(AppLanguage.en)}'),
      ));
    }
    final term = _termById(id);
    if (term == null) return _missing();
    final glossaryTool = toolById('glossary');
    final followUps = [
      if (glossaryTool != null) openFollowUp(glossaryTool, ctx.lang),
    ];
    final iso = term.isoLabel;
    final source = AssistantText(
        'Słownik spawalniczy${iso == null ? '' : ' · $iso'}',
        'Welding dictionary${iso == null ? '' : ' · $iso'}');
    if (kind == 'definition') {
      return AnswerResult(
        AssistantAnswer(
          text: AssistantText(
              '„${term.pl}” — ${term.defPl}', '"${term.en}" — ${term.defEn}'),
          source: source,
        ),
        followUps: followUps,
      );
    }
    final target = GlossaryLang.parse(m.slots['target'] as String?);
    List<GlossaryLang> order(GlossaryLang ui) => [
          if (target != null && target != ui) target,
          for (final l in const [
            GlossaryLang.de,
            GlossaryLang.nl,
            GlossaryLang.no,
            GlossaryLang.en,
            GlossaryLang.pl,
          ])
            if (l != ui && l != target) l,
        ];
    String list(GlossaryLang ui) =>
        order(ui).map((l) => '${l.code}: ${term.text(l)}').join(' · ');
    final also = [
      for (final a in (m.slots['also'] as List? ?? const []).cast<String>())
        if (_termById(a) case final t?) t,
    ];
    final spokenTarget = target ?? GlossaryLang.de;
    return AnswerResult(
      AssistantAnswer(
        text: AssistantText('„${term.pl}” — ${list(GlossaryLang.pl)}.',
            '"${term.en}" — ${list(GlossaryLang.en)}.'),
        spoken: AssistantText(
            '${_inLangPl[spokenTarget]}: ${term.text(spokenTarget)}.',
            '${_inLangEn[spokenTarget]}: ${term.text(spokenTarget)}.'),
        lines: [
          for (final l in GlossaryLang.values)
            AnswerLine(AssistantText(l.namePl, l.nameEn), term.text(l)),
          for (final t in also)
            AnswerLine(const AssistantText('Zobacz też', 'See also'),
                ctx.lang == AppLanguage.en ? t.en : t.pl),
        ],
        source: source,
      ),
      followUps: followUps,
    );
  }

  SkillResult _missing() => const FailedResult(AssistantText(
      'Nie znalazłem tego w Pomocy ani w słowniku.',
      'I could not find it in Help or the dictionary.'));
}
