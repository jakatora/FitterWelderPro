// Egzamin spawacza (EN ISO 9606-1, część teoretyczna) — pytania GENEROWANE
// z danych, które już są w aplikacji i przeszły weryfikację. Czysty Dart.
//
// ZASADA RZETELNOŚCI: żadnego faktu wpisanego tu z pamięci. Każda poprawna
// odpowiedź pochodzi z tabeli albo funkcji domeny innego modułu:
//   • słownik PL·EN·DE·NL·NO (lib/data/welding_glossary.dart) — procesy
//     ISO 4063, niezgodności ISO 6520-1, pozycje ISO 6947 (+ ASME), definicje,
//     skróty, BHP, tłumaczenia;
//   • zakres uprawnień EN ISO 9606-1 (lib/domain/qualification/
//     iso9606_range.dart) — tab. 3, 6, 7, 8, 9, 10 i §5.2 przez funkcje
//     domeny (evaluateIso9606, iso9606ButtThickness…);
//   • rodziny procesów (weld_process.dart);
//   • odbiór wizualny EN ISO 5817 (iso5817_table.dart);
//   • symbole EN ISO 2553 (weld_symbols/*);
//   • elektrody — limity AWS D1.1 tab. 7.1 (electrode_exposure.dart);
//   • dobór spoiwa i gazy EN ISO 14175 (lib/domain/filler/).
// Tu jest tylko układanie pytania: treść, poprawna odpowiedź i PULA
// dystraktorów z tej samej kategorii danych.
//
// NIEJEDNOZNACZNE — POMIJAMY (zamiast zgadywać):
//   • dwie pozycje danych o tej samej nazwie / numerze;
//   • niezgodności spokrewnione w ISO 6520-1 (grupa „x00” i jej podtypy,
//     numer będący przedrostkiem drugiego) nie są dla siebie dystraktorami;
//   • ISO 5817: pozycje z regułą słowną („zależy od zastosowania”,
//     „dopuszczalna miejscowo”) i pozycje zmienione w wydaniu 2023
//     (`note2023*`) — bez pytania o poziomy; treść podaje wydanie 2014,
//     a przy limitach tylko dla niezgodności krótkich — „(niezgodność
//     krótka)”;
//   • EN ISO 9606-1 §5.2: tylko procesy objęte BEZ WARUNKU dla typu spoiwa
//     próby (po filtrze tab. 4 i 5, przez evaluateIso9606); objęte
//     częściowo (np. 143 z próby 141 drutem litym) — ani odpowiedź, ani
//     dystraktor;
//   • elektrody: w odpowiedziach kod z opisem klasy, tylko jedna klasa
//     z pytanym limitem, bez klas o pokrewnym oznaczeniu (E7018 / E7018-1 /
//     E7018 H4R);
//   • EN ISO 9606-1: s ≥ 12 mm (notka „sprawdź” w domenie — EN 287-1 dawała
//     ≥ 5 mm, część materiałów szkoleniowych nadal tak podaje);
//   • definicje: dystraktor, którego nazwa pojawia się w definicji (albo
//     odwrotnie), odpada — to zwykle pojęcie nadrzędne / pokrewne;
//   • dobór spoiwa: dystraktorem może być tylko spoiwo, którego aplikacja nie
//     dobiera dla żadnej pary z grup materiałowych pytania i którego nie
//     wymienia uzasadnienie ani ostrzeżenia tej pary;
//   • tłumaczenia: dystraktor nie może być synonimem poprawnej odpowiedzi;
//   • za mało (< 2) bezpiecznych dystraktorów → pytania nie ma.
//
// Losowanie jest deterministyczne: ten sam seed → te same pytania, ta sama
// kolejność odpowiedzi (testy, powtarzalne sesje). Sesja bierze najwyżej
// jedno pytanie z tematu ([ExamItem.topic]) — pytania o tę samą rzecz nie
// zdradzają sobie odpowiedzi.

import 'dart:math';

import '../../data/welding_glossary.dart';
import '../filler/filler_catalog.dart';
import '../filler/filler_selector.dart';
import '../glossary/glossary.dart';
import '../iso5817/iso5817_limits.dart';
import '../iso5817/iso5817_table.dart';
import '../qualification/iso9606_range.dart';
import '../qualification/weld_process.dart';
import '../weld_symbols/weld_symbol.dart';
import '../weld_symbols/weld_symbol_catalog.dart';
import '../weld_symbols/weld_symbol_description.dart';
import '../welding/electrode_exposure.dart';

/// Długość szybkiej sesji i sesji nauki.
const int kExamSessionLength = 10;

/// Ile odpowiedzi ma pytanie (poprawna + dystraktory), gdy pula pozwala.
const int kExamMaxOptions = 4;

/// Kategorie pytań (kolejność listy na ekranie).
enum ExamCategory {
  processes('Procesy (ISO 4063)', 'Processes (ISO 4063)'),
  imperfections('Niezgodności (ISO 6520-1)', 'Imperfections (ISO 6520-1)'),
  positions('Pozycje spawania (ISO 6947)', 'Welding positions (ISO 6947)'),
  qualification('Zakres uprawnień (EN ISO 9606-1)',
      'Qualification range (EN ISO 9606-1)'),
  quality('Poziomy jakości (EN ISO 5817)', 'Quality levels (EN ISO 5817)'),
  symbols('Symbole spoin (EN ISO 2553)', 'Weld symbols (EN ISO 2553)'),
  consumables('Elektrody, spoiwa i gazy', 'Electrodes, fillers and gases'),
  terms('Pojęcia i dokumenty', 'Terms and documents'),
  safety('BHP', 'Health and safety'),
  vocabulary('Słownictwo obce (EN, DE)', 'Foreign vocabulary (DE)');

  const ExamCategory(this.titlePl, this.titleEn);

  final String titlePl;
  final String titleEn;

  String title({required bool en}) => en ? titleEn : titlePl;

  static ExamCategory? parse(Object? raw) {
    for (final c in values) {
      if (c.name == raw) return c;
    }
    return null;
  }
}

/// Jedno możliwe pytanie: treść, poprawna odpowiedź i pula dystraktorów
/// (już przefiltrowana — różne od poprawnej i od siebie, z tej samej
/// kategorii danych).
class ExamItem {
  const ExamItem({
    required this.id,
    required this.category,
    required this.prompt,
    required this.answer,
    required this.distractors,
    required this.explanation,
    required this.source,
    this.glyph,
    String? topic,
  }) : topic = topic ?? id;

  /// Trwały identyfikator, niezależny od języka (statystyki, powtórki).
  final String id;

  /// Temat: pytania o tę samą rzecz (np. proces 135 — nazwa, numer,
  /// rodzina; termin — definicja, skrót, tłumaczenie) zdradzałyby sobie
  /// odpowiedzi, więc sesja bierze najwyżej jedno pytanie z tematu.
  final String topic;
  final ExamCategory category;
  final String prompt;
  final String answer;
  final List<String> distractors;

  /// Krótkie wyjaśnienie po odpowiedzi (z danych).
  final String explanation;

  /// Skąd dane, np. „ISO 4063”, „EN ISO 9606-1 tab. 9”.
  final String source;

  /// Symbol podstawowy do narysowania nad treścią (pytania o symbole).
  final WeldKind? glyph;
}

/// Pytanie w sesji: odpowiedzi w wylosowanej kolejności.
class ExamQuestion {
  const ExamQuestion({
    required this.item,
    required this.options,
    required this.correctIndex,
  });

  final ExamItem item;
  final List<String> options;
  final int correctIndex;

  String get id => item.id;
  ExamCategory get category => item.category;
  String get prompt => item.prompt;
  String get answer => item.answer;
  String get explanation => item.explanation;
  String get source => item.source;
  WeldKind? get glyph => item.glyph;
}

/// Wszystkie możliwe pytania w języku interfejsu (zbudowane raz, leniwie).
List<ExamItem> examItems({required bool en}) =>
    _cache[en] ??= List.unmodifiable(_ExamBuilder(en).build());

final Map<bool, List<ExamItem>> _cache = {};

/// Pytania jednej kategorii.
List<ExamItem> examItemsIn(ExamCategory category, {required bool en}) => [
      for (final i in examItems(en: en))
        if (i.category == category) i,
    ];

/// Pytanie po identyfikatorze (powtórki) albo `null`, gdy go już nie ma
/// (zmienione dane, inny język bez tego pytania).
ExamItem? examItemById(String id, {required bool en}) {
  for (final i in examItems(en: en)) {
    if (i.id == id) return i;
  }
  return null;
}

/// Liczba możliwych pytań w każdej kategorii.
Map<ExamCategory, int> examCategoryCounts({required bool en}) {
  final out = {for (final c in ExamCategory.values) c: 0};
  for (final i in examItems(en: en)) {
    out[i.category] = out[i.category]! + 1;
  }
  return out;
}

/// Pytanie z [item]: do [kExamMaxOptions] − 1 dystraktorów z puli
/// i przetasowane odpowiedzi — wszystko z [rnd].
ExamQuestion examQuestionFrom(ExamItem item, Random rnd) {
  final pool = [...item.distractors]..shuffle(rnd);
  final options = [item.answer, ...pool.take(kExamMaxOptions - 1)]
    ..shuffle(rnd);
  return ExamQuestion(
    item: item,
    options: List.unmodifiable(options),
    correctIndex: options.indexOf(item.answer),
  );
}

/// Losuje [count] pytań (deterministycznie z [seed]).
///
/// • [onlyIds] — tylko te pytania (powtórki); nieznane id są pomijane;
/// • [category] — nauka jednej kategorii;
/// • bez obu — szybka sesja: kategorie po kolei w wylosowanej kolejności,
///   żeby 10 pytań objęło możliwie wiele kategorii.
///
/// W każdym trybie najwyżej jedno pytanie z jednego tematu
/// ([ExamItem.topic]) — pytania nie podpowiadają sobie odpowiedzi.
List<ExamQuestion> drawExamQuestions({
  required int seed,
  required bool en,
  ExamCategory? category,
  Iterable<String>? onlyIds,
  int count = kExamSessionLength,
}) {
  final rnd = Random(seed);
  final all = examItems(en: en);
  final picked = <ExamItem>[];
  final topics = <String>{};
  void fill(List<ExamItem> pool) {
    for (final i in pool) {
      if (picked.length >= count) break;
      if (topics.add(i.topic)) picked.add(i);
    }
  }

  if (onlyIds != null) {
    final wanted = onlyIds.toSet();
    fill([
      for (final i in all)
        if (wanted.contains(i.id)) i,
    ]..shuffle(rnd));
  } else if (category != null) {
    fill([
      for (final i in all)
        if (i.category == category) i,
    ]..shuffle(rnd));
  } else {
    final byCategory = <ExamCategory, List<ExamItem>>{};
    for (final i in all) {
      byCategory.putIfAbsent(i.category, () => <ExamItem>[]).add(i);
    }
    for (final list in byCategory.values) {
      list.shuffle(rnd);
    }
    final order = byCategory.keys.toList()..shuffle(rnd);
    final cursor = {for (final c in order) c: 0};
    while (picked.length < count) {
      var added = false;
      for (final c in order) {
        if (picked.length >= count) break;
        final list = byCategory[c]!;
        var at = cursor[c]!;
        while (at < list.length && !topics.add(list[at].topic)) {
          at++;
        }
        if (at < list.length) {
          picked.add(list[at]);
          added = true;
          at++;
        }
        cursor[c] = at;
      }
      if (!added) break;
    }
  }
  return [for (final i in picked) examQuestionFrom(i, rnd)];
}

/// Liczba tematów w kategorii — tyle pytań może mieć sesja nauki.
int examTopicCount(ExamCategory category, {required bool en}) =>
    {for (final i in examItemsIn(category, en: en)) i.topic}.length;

// ─── Wspólne pomocnicze ─────────────────────────────────────────────────────

/// Klucz porównania odpowiedzi: bez wielkości liter i nadmiarowych spacji.
String examAnswerKey(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Czas na powietrzu do wyświetlenia: „4 h”, „30 min”, „1 h 30 min”.
String examDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// ISO 6520-1: czy numery są spokrewnione — grupa główna „x00” i jej
/// podtypy albo numer będący przedrostkiem drugiego (501 → 5011). Takie
/// pary nie są dla siebie dystraktorami.
bool iso6520Related(String a, String b) {
  if (a.isEmpty || b.isEmpty || a[0] != b[0]) return false;
  return a.endsWith('00') ||
      b.endsWith('00') ||
      a.startsWith(b) ||
      b.startsWith(a);
}

/// Kod ISO 6947 i oznaczenie ASME z pola `code` słownika („PF · ASME 3G
/// up” → (PF, 3G up)); `null`, gdy pole ma inny format.
({String iso, String asme})? glossaryPositionCodes(GlossaryTerm t) {
  final raw = t.code;
  if (raw == null) return null;
  final parts = raw.split(' · ');
  if (parts.length != 2 || !parts[1].startsWith('ASME ')) return null;
  return (
    iso: parts[0].trim(),
    asme: parts[1].substring('ASME '.length).trim(),
  );
}

/// Nazwa terminu bez dopisanego skrótu w nawiasie („Badania wizualne (VT)”
/// → „Badania wizualne”).
String glossaryNameWithoutCode(String name, String? code) {
  if (code == null) return name;
  return name.replaceAll(' ($code)', '').trim();
}

/// Rdzenie słów nazwy (≥ 4 litery, bez znaków diakrytycznych; dłuższe
/// skrócone do 5 liter) — do wykrywania pojęć pokrewnych w definicjach.
Set<String> _stems(String s) => {
      for (final w in normalizeGlossary(s).split(' '))
        if (w.length >= 4) w.length >= 5 ? w.substring(0, 5) : w,
    };

bool _mentions(String text, Set<String> stems) {
  final words = normalizeGlossary(text).split(' ');
  return stems.any((st) => words.any((w) => w.startsWith(st)));
}

/// Czy dwa zdefiniowane terminy są pokrewne: nazwa jednego pojawia się
/// w definicji drugiego (w PL albo EN).
bool glossaryDefinitionsOverlap(GlossaryTerm a, GlossaryTerm b) {
  final pairs = [
    (a.pl, a.defPl, b.pl, b.defPl),
    (a.en, a.defEn, b.en, b.defEn),
  ];
  for (final (aName, aDef, bName, bDef) in pairs) {
    if (aDef != null && _mentions(aDef, _stems(bName))) return true;
    if (bDef != null && _mentions(bDef, _stems(aName))) return true;
  }
  return false;
}

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Wartości próbek do pytań o wymiary (ISO 9606-1). s ≥ 12 celowo pominięte
/// (patrz nagłówek pliku).
const List<double> kExamButtThicknesses = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
const List<double> kExamFilletThicknesses = [1, 1.5, 2, 2.5, 3, 5, 10];
const List<double> kExamDiameters = [
  8,
  12,
  16,
  20,
  25,
  30,
  33.7,
  48.3,
  60.3,
  88.9,
  114.3,
  168.3,
];

/// Poziomy ISO 5817, na których reguła pozwala na niezgodność (z limitem
/// albo bez) — `null`, gdy któraś reguła jest słowna (niejednoznaczne).
Set<Iso5817Level>? iso5817PermittedLevels(
    Iso5817Item item, Iso5817Range range) {
  final out = <Iso5817Level>{};
  for (final level in Iso5817Level.values) {
    final rule = iso5817RuleFor(item, level, range);
    switch (rule.kind) {
      case Iso5817RuleKind.qualitative:
        return null;
      case Iso5817RuleKind.notPermitted:
        break;
      case Iso5817RuleKind.formula:
      case Iso5817RuleKind.unlimited:
      case Iso5817RuleKind.minAngle:
        out.add(level);
    }
  }
  return out;
}

/// Odpowiedzi o poziomach (od najszerszej do pustej) — tylko zbiory
/// „od najłagodniejszego w górę”: {B,C,D}, {C,D}, {D}, {}.
List<(Set<Iso5817Level>, String)> _levelOptions(bool en) => [
      (
        {Iso5817Level.b, Iso5817Level.c, Iso5817Level.d},
        en ? 'B, C and D' : 'Na B, C i D'
      ),
      (
        {Iso5817Level.c, Iso5817Level.d},
        en ? 'Only C and D' : 'Tylko na C i D'
      ),
      ({Iso5817Level.d}, en ? 'Only D' : 'Tylko na D'),
      (
        <Iso5817Level>{},
        en ? 'None (not permitted)' : 'Na żadnym (niedopuszczalna)'
      ),
    ];

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);

/// Pozycje objęte uprawnieniem z próby — przez [evaluateIso9606] (jedna
/// próbka, bez dodatkowej rury w PC).
Iso9606Range? examIso9606Range(
    Iso9606WeldType type, Iso9606Product product, Iso6947Position position) {
  final eval = evaluateIso9606(Iso9606Sample(
    product: product,
    weldType: type,
    first: const Iso9606ProcessInput(
      process: Iso9606Process.p111,
      filler: Iso9606Filler.coveringBasic,
      thicknessMm: 10,
    ),
    fm: Iso9606FmGroup.fm1,
    diameterMm: product == Iso9606Product.pipe ? 168.3 : null,
    position: position,
    backing: type == Iso9606WeldType.bw ? Iso9606Backing.ssNb : null,
    filletLayers: type == Iso9606WeldType.fw ? Iso9606FilletLayers.ml : null,
  ));
  return eval.range;
}

String _codes(Iterable<Iso6947Position> p) => p.map((e) => e.code).join(', ');

/// Wydanie EN ISO 9606-1, z którego tabel liczy domena (iso9606_range.dart:
/// EN ISO 9606-1:2017 = ISO 9606-1:2012 + Cor 1:2012 + Cor 2:2013; tak też
/// podpisuje wynik [iso9606Disclaimer]).
const String kExamIso9606Edition = 'EN ISO 9606-1:2017';

/// Nazwa typu spoiwa wg EN ISO 9606-1 §4.3.2 (tab. 4 i 5) — te same opisy
/// co na ekranie „Zakres uprawnień z próbki”.
String examIso9606FillerName(Iso9606Filler f, {required bool en}) =>
    switch (f) {
      Iso9606Filler.coveringRutile =>
        en ? 'covering A, RA, RB, RC, RR, R' : 'otulina A, RA, RB, RC, RR, R',
      Iso9606Filler.coveringBasic =>
        en ? 'basic covering B' : 'otulina zasadowa B',
      Iso9606Filler.coveringCellulosic =>
        en ? 'cellulosic covering C' : 'otulina celulozowa C',
      Iso9606Filler.solid =>
        en ? 'solid wire / rod (S)' : 'drut / pręt lity (S)',
      Iso9606Filler.metalCored => en
          ? 'metal-cored wire / rod (M)'
          : 'drut / pręt z rdzeniem metalicznym (M)',
      Iso9606Filler.basicCored => en
          ? 'basic flux-cored wire / rod (B)'
          : 'drut / pręt proszkowy zasadowy (B)',
      Iso9606Filler.otherCored => en
          ? 'flux-cored wire / rod R, P, V, W, Y or Z'
          : 'drut / pręt proszkowy R, P, V, W, Y albo Z',
      Iso9606Filler.none => en ? 'no filler (nm)' : 'bez spoiwa (nm)',
    };

/// Zakres procesów z próby procesem [process] i spoiwem [filler] — przez
/// [evaluateIso9606], czyli §5.2 PO filtrze typu spoiwa (tab. 4 i 5).
/// Klucze: objęte procesy, wartości: objęte typy spoiwa. `null`, gdy próbka
/// jest niepoprawna (np. spoiwo, którym proces nie spawa).
Map<Iso9606Process, List<Iso9606Filler>>? examIso9606Processes(
    Iso9606Process process, Iso9606Filler filler) {
  final eval = evaluateIso9606(Iso9606Sample(
    first: Iso9606ProcessInput(
      process: process,
      filler: filler,
      transfer: process.hasTransferMode ? Iso9606Transfer.dip : null,
      thicknessMm: 10,
    ),
    fm: Iso9606FmGroup.fm1,
    parentGroup: '1.1',
    position: Iso6947Position.pa,
    backing: Iso9606Backing.ssNb,
    gasDirection:
        process == Iso9606Process.p311 ? Iso9606GasDirection.leftward : null,
  ));
  return eval.range?.processes.first.processes;
}

/// Odpowiedź w pytaniu o klasę elektrod: kod z opisem klasy.
String examElectrodeOption(ElectrodeClass c, {required bool en}) =>
    '${c.code} — ${c.desc(en: en)}';

/// Klasy o pokrewnym oznaczeniu (kod jednej jest przedrostkiem kodu drugiej
/// albo pojawia się w jej opisie, np. „E7018-1” w „np. E7018-1 H4R”) — nie
/// są dla siebie dystraktorami.
bool examElectrodesRelated(ElectrodeClass a, ElectrodeClass b) =>
    a.code.startsWith(b.code) ||
    b.code.startsWith(a.code) ||
    a.descPl.contains(b.code) ||
    a.descEn.contains(b.code) ||
    b.descPl.contains(a.code) ||
    b.descEn.contains(a.code);

/// Czy reguła ISO 5817 dla któregoś poziomu dotyczy tylko niezgodności
/// krótkich (rozdz. 3.3 / 3.4).
bool iso5817ShortOnly(Iso5817Item item, Iso5817Range range) =>
    Iso5817Level.values.any((l) => iso5817RuleFor(item, l, range).shortOnly);

/// Pozycja ISO 5817:2014, którą wydanie 2023 zmieniło (`note2023*`) —
/// bez pytania (odpowiedź zależałaby od wydania).
bool iso5817ChangedIn2023(Iso5817Item item) =>
    item.note2023Pl.isNotEmpty || item.note2023En.isNotEmpty;

// ─── Budowanie pytań ────────────────────────────────────────────────────────

class _ExamBuilder {
  _ExamBuilder(this.en);

  final bool en;
  final List<ExamItem> _items = [];

  String t(String pl, String e) => en ? e : pl;

  GlossaryLang get _ui => en ? GlossaryLang.en : GlossaryLang.pl;

  String _name(GlossaryTerm term) => term.text(_ui);

  String? _def(GlossaryTerm term) => en ? term.defEn : term.defPl;

  String _withDef(String head, GlossaryTerm term) {
    final d = _def(term);
    return d == null ? head : '$head $d';
  }

  /// Dodaje pytanie, jeśli zostały co najmniej 2 bezpieczne dystraktory.
  void _add({
    required String id,
    required ExamCategory category,
    required String prompt,
    required String answer,
    required Iterable<String> pool,
    required String explanation,
    required String source,
    WeldKind? glyph,
    String? topic,
  }) {
    if (answer.trim().isEmpty) return;
    final seen = <String>{examAnswerKey(answer)};
    final distractors = <String>[];
    for (final d in pool) {
      if (d.trim().isEmpty) continue;
      if (seen.add(examAnswerKey(d))) distractors.add(d);
    }
    if (distractors.length < 2) return;
    _items.add(ExamItem(
      id: id,
      category: category,
      prompt: prompt,
      answer: answer,
      distractors: List.unmodifiable(distractors),
      explanation: explanation,
      source: source,
      glyph: glyph,
      topic: topic,
    ));
  }

  /// Temat pytań o jeden termin słownika (nazwa, numer, definicja, skrót,
  /// tłumaczenie).
  static String _termTopic(GlossaryTerm t) => 'term:${t.id}';

  List<ExamItem> build() {
    _processes();
    _imperfections();
    _positions();
    _qualification();
    _quality();
    _symbols();
    _consumables();
    _definitions();
    _abbreviations();
    _vocabulary();
    return _items;
  }

  // ── Procesy ISO 4063 ──────────────────────────────────────────────────────

  void _processes() {
    final terms = [
      for (final g in kWeldingGlossary)
        if (g.category == GlossaryCategory.process && g.iso4063 != null) g,
    ];
    final names = <String, int>{};
    final numbers = <String, int>{};
    for (final g in terms) {
      names.update(examAnswerKey(_name(g)), (v) => v + 1, ifAbsent: () => 1);
      numbers.update(g.iso4063!, (v) => v + 1, ifAbsent: () => 1);
    }
    final unique = [
      for (final g in terms)
        if (names[examAnswerKey(_name(g))] == 1 && numbers[g.iso4063!] == 1) g,
    ];
    for (final g in unique) {
      final others = [
        for (final o in unique)
          if (o.id != g.id) o,
      ];
      final n = g.iso4063!;
      final name = _name(g);
      _add(
        id: 'proc.name.${g.id}',
        category: ExamCategory.processes,
        prompt: t('Który proces ma numer $n wg ISO 4063?',
            'Which process has number $n in ISO 4063?'),
        answer: name,
        pool: others.map(_name),
        explanation: _withDef('$n — $name.', g),
        source: 'ISO 4063',
        topic: _termTopic(g),
      );
      _add(
        id: 'proc.num.${g.id}',
        category: ExamCategory.processes,
        prompt: t('Jaki numer wg ISO 4063 ma proces: „$name”?',
            'What is the ISO 4063 number of: “$name”?'),
        answer: n,
        pool: others.map((o) => o.iso4063!),
        explanation: _withDef('$n — $name.', g),
        source: 'ISO 4063',
        topic: _termTopic(g),
      );
      final number = int.tryParse(n);
      final family = number == null ? null : familyOfIso4063(number);
      if (family != null) {
        _add(
          id: 'proc.family.$n',
          category: ExamCategory.processes,
          prompt: t('Proces $n („$name”) to w skrótach ASME / AWS:',
              'Process $n (“$name”) in ASME / AWS abbreviations is:'),
          answer: family.asmeCode,
          pool: [
            for (final f in WeldProcessFamily.values)
              if (f != family) f.asmeCode,
          ],
          explanation: '$n → ${family.asmeCode}.',
          source: 'ISO 4063 · ASME IX',
          topic: _termTopic(g),
        );
      }
    }
  }

  // ── Niezgodności ISO 6520-1 ───────────────────────────────────────────────

  void _imperfections() {
    final terms = [
      for (final g in kWeldingGlossary)
        if (g.category == GlossaryCategory.imperfection && g.iso6520 != null) g,
    ];
    for (final g in terms) {
      final n = g.iso6520!;
      final others = [
        for (final o in terms)
          if (o.id != g.id && !iso6520Related(n, o.iso6520!)) o,
      ];
      final name = _name(g);
      _add(
        id: 'imp.name.${g.id}',
        category: ExamCategory.imperfections,
        prompt: t('Jak nazywa się niezgodność nr $n wg ISO 6520-1?',
            'What is imperfection no. $n in ISO 6520-1 called?'),
        answer: name,
        pool: others.map(_name),
        explanation: _withDef('$n — $name.', g),
        source: 'ISO 6520-1',
        topic: _termTopic(g),
      );
      _add(
        id: 'imp.num.${g.id}',
        category: ExamCategory.imperfections,
        prompt: t('Jaki numer wg ISO 6520-1 ma niezgodność: „$name”?',
            'What is the ISO 6520-1 number of the imperfection: “$name”?'),
        answer: n,
        pool: others.map((o) => o.iso6520!),
        explanation: _withDef('$n — $name.', g),
        source: 'ISO 6520-1',
        topic: _termTopic(g),
      );
    }
  }

  // ── Pozycje ISO 6947 ──────────────────────────────────────────────────────

  void _positions() {
    final terms = [
      for (final g in kWeldingGlossary)
        if (g.category == GlossaryCategory.position &&
            glossaryPositionCodes(g) != null)
          g,
    ];
    for (final g in terms) {
      final codes = glossaryPositionCodes(g)!;
      final others = [
        for (final o in terms)
          if (o.id != g.id) o,
      ];
      final name = _name(g);
      final head = '${codes.iso} — $name; ASME ${codes.asme}.';
      _add(
        id: 'pos.code.${g.id}',
        category: ExamCategory.positions,
        prompt: t('Jak oznacza się wg ISO 6947 pozycję: „$name”?',
            'What is the ISO 6947 designation of: “$name”?'),
        answer: codes.iso,
        pool: others.map((o) => glossaryPositionCodes(o)!.iso),
        explanation: _withDef(head, g),
        source: 'ISO 6947',
        topic: _termTopic(g),
      );
      _add(
        id: 'pos.name.${g.id}',
        category: ExamCategory.positions,
        prompt: t('Co oznacza pozycja ${codes.iso} wg ISO 6947?',
            'What does position ${codes.iso} (ISO 6947) mean?'),
        answer: name,
        pool: others.map(_name),
        explanation: _withDef(head, g),
        source: 'ISO 6947',
        topic: _termTopic(g),
      );
      _add(
        id: 'pos.asme.${g.id}',
        category: ExamCategory.positions,
        prompt: t('Której pozycji wg ASME odpowiada ${codes.iso} (ISO 6947)?',
            'Which ASME position corresponds to ${codes.iso} (ISO 6947)?'),
        answer: codes.asme,
        pool: others.map((o) => glossaryPositionCodes(o)!.asme),
        explanation: head,
        source: 'ISO 6947 · ASME IX',
        topic: _termTopic(g),
      );
    }
  }

  // ── Zakres uprawnień EN ISO 9606-1 ────────────────────────────────────────

  void _qualification() {
    // Pozycje (tab. 9 — BW, tab. 10 — FW).
    for (final type in Iso9606WeldType.values) {
      for (final product in Iso9606Product.values) {
        final tested = iso9606TestPositions(type, product);
        final ranges = <Iso6947Position, Iso9606Range>{};
        for (final p in tested) {
          final r = examIso9606Range(type, product, p);
          if (r != null) ranges[p] = r;
        }
        final isButt = type == Iso9606WeldType.bw;
        final pipe = product == Iso9606Product.pipe;
        final table =
            isButt ? t('tab. 9', 'Table 9') : t('tab. 10', 'Table 10');
        for (final entry in ranges.entries) {
          final pos = entry.key;
          final answer = _codes(entry.value.positions);
          final weld = isButt
              ? t('spoiny czołowej (BW)', 'butt weld (BW)')
              : t('spoiny pachwinowej (FW)', 'fillet weld (FW)');
          final where = pipe
              ? t('na rurze (T)', 'on pipe (T)')
              : t('na blasze (P)', 'on plate (P)');
          final single = isButt &&
                  pipe &&
                  (pos == Iso6947Position.ph || pos == Iso6947Position.pj)
              ? t(' (bez dodatkowej próbki w PC)',
                  ' (no extra test piece in PC)')
              : '';
          final notes = [
            for (final n in entry.value.notes)
              if (n.pl.contains('L045')) n.text(en: en),
          ];
          _add(
            id: 'q.pos.${type.code}.${product.code}.${pos.code}',
            category: ExamCategory.qualification,
            prompt: t(
                '$kExamIso9606Edition: próba $weld $where w pozycji ${pos.code}$single. '
                    'Jakie pozycje obejmuje uprawnienie?',
                '$kExamIso9606Edition: $weld test $where in position ${pos.code}'
                    '$single. Which positions does the qualification cover?'),
            answer: answer,
            pool: [
              for (final other in ranges.entries)
                if (other.key != pos) _codes(other.value.positions),
            ],
            explanation: [
              '${t('Tab.', 'Table')} ${isButt ? 9 : 10}: ${pos.code} → '
                  '$answer.',
              ...notes,
            ].join(' '),
            source: '$kExamIso9606Edition $table',
          );
        }
      }
    }

    // Grubość spoin czołowych (tab. 6), jeden proces, nie 311.
    String buttRange(double s) =>
        iso9606RangeText(iso9606ButtThickness(s), en: en);
    for (final s in kExamButtThicknesses) {
      final v = iso9606Mm(s, en: en);
      _add(
        id: 'q.s.${_num(s)}',
        category: ExamCategory.qualification,
        prompt: t(
            '$kExamIso9606Edition: spoina czołowa, jeden proces (inny niż 311), '
                'grubość stopiwa próbki s = $v mm. Jaki zakres grubości '
                'obejmuje uprawnienie?',
            '$kExamIso9606Edition: butt weld, single process (not 311), deposited '
                'thickness of the test piece s = $v mm. What thickness range '
                'does the qualification cover?'),
        answer: buttRange(s),
        pool: [
          for (final o in kExamButtThicknesses)
            if (o != s) buttRange(o),
        ],
        explanation: 's = $v mm → ${buttRange(s)}.',
        source: '$kExamIso9606Edition ${t('tab. 6', 'Table 6')}',
      );
    }

    // Grubość materiału spoin pachwinowych (tab. 8).
    String fillet(double v) =>
        iso9606RangeText(iso9606FilletThickness(v), en: en);
    for (final tt in kExamFilletThicknesses) {
      final v = iso9606Mm(tt, en: en);
      _add(
        id: 'q.t.${_num(tt)}',
        category: ExamCategory.qualification,
        prompt: t(
            '$kExamIso9606Edition: spoina pachwinowa, grubość materiału próbki '
                't = $v mm. Jaki zakres grubości obejmuje uprawnienie?',
            '$kExamIso9606Edition: fillet weld, test piece material thickness '
                't = $v mm. What thickness range does the qualification '
                'cover?'),
        answer: fillet(tt),
        pool: [
          for (final o in kExamFilletThicknesses)
            if (o != tt) fillet(o),
        ],
        explanation: 't = $v mm → ${fillet(tt)}.',
        source: '$kExamIso9606Edition ${t('tab. 8', 'Table 8')}',
      );
    }

    // Średnica rury (tab. 7).
    String dia(double d) => iso9606RangeText(iso9606Diameter(d), en: en);
    for (final d in kExamDiameters) {
      final v = iso9606Mm(d, en: en);
      _add(
        id: 'q.d.${_num(d)}',
        category: ExamCategory.qualification,
        prompt: t(
            '$kExamIso9606Edition: próba na rurze o średnicy zewnętrznej D = $v mm. '
                'Jaki zakres średnic obejmuje uprawnienie?',
            '$kExamIso9606Edition: pipe test piece with outside diameter '
                'D = $v mm. What diameter range does the qualification '
                'cover?'),
        answer: dia(d),
        pool: [
          for (final o in kExamDiameters)
            if (o != d) dia(o),
        ],
        explanation: 'D = $v mm → ${dia(d)}.',
        source: '$kExamIso9606Edition ${t('tab. 7', 'Table 7')}',
      );
    }

    // Procesy (§5.2 PO filtrze typu spoiwa z tab. 4 i 5): próba procesem p
    // spoiwem f obejmuje też proces c — tylko gdy c jest objęty KAŻDYM swoim
    // typem spoiwa (bez warunku). Proces objęty częściowo (np. 143 z próby
    // 141 drutem litym — tylko rdzeń metaliczny M) nie jest ani odpowiedzią,
    // ani dystraktorem.
    for (final p in Iso9606Process.values) {
      for (final f in p.fillers) {
        final covered = examIso9606Processes(p, f);
        if (covered == null) continue;
        final pName = en ? p.nameEn : p.namePl;
        final fName = examIso9606FillerName(f, en: en);
        final summary = [
          for (final e in covered.entries)
            '${e.key.code} (${e.value.map((x) => x.code).join(', ')})',
        ].join('; ');
        for (final c in Iso9606Process.values) {
          final types = covered[c];
          if (c == p || types == null) continue;
          if (!c.fillers.every(types.contains)) continue;
          final noFiller = c.fillers.every((x) => x == Iso9606Filler.none);
          _add(
            id: 'q.proc.${p.number}.${f.name}.${c.number}',
            category: ExamCategory.qualification,
            prompt: t(
                '$kExamIso9606Edition §5.2: uprawnienie z próby procesem '
                    '${p.number} ($pName), typ spoiwa: $fName, obejmuje '
                    'także proces:',
                '$kExamIso9606Edition cl. 5.2: a qualification from a test '
                    'with process ${p.number} ($pName), filler type: $fName, '
                    'also covers process:'),
            answer: c.code,
            pool: [
              for (final x in Iso9606Process.values)
                if (!covered.containsKey(x)) x.code,
            ],
            explanation: [
              t(
                  '§5.2 i tab. 4 / 5: ${p.number} (${f.code}) → $summary.',
                  'Cl. 5.2 and Tables 4 / 5: ${p.number} (${f.code}) → '
                      '$summary.'),
              if (noFiller)
                t(
                    'Spawanie bez spoiwa — tylko na grupie materiału rodzimego '
                        'z próby (§5.6 uwaga).',
                    'Welding without filler — only on the parent material '
                        'group of the test (cl. 5.6 note).'),
            ].join(' '),
            source: '$kExamIso9606Edition ${t('§5.2, tab. 4 i 5', 'cl. 5.2, '
                'Tables 4 and 5')}',
            topic: 'q.proc.${p.number}.${f.name}',
          );
        }
      }
    }

    // Grupy spoiw FM (tab. 3).
    String fmSet(Iso9606FmGroup g) => [
          for (final x in Iso9606FmGroup.values)
            if (kIso9606FmRange[g]!.contains(x)) x.code,
        ].join(', ');
    for (final g in Iso9606FmGroup.values) {
      final desc = en ? g.nameEn : g.namePl;
      _add(
        id: 'q.fm.${g.code}',
        category: ExamCategory.qualification,
        prompt: t(
            '$kExamIso9606Edition tab. 3: próba spoiwem z grupy ${g.code} ($desc) '
                'obejmuje grupy spoiw:',
            '$kExamIso9606Edition Table 3: a test with filler group ${g.code} '
                '($desc) covers filler groups:'),
        answer: fmSet(g),
        pool: [
          for (final o in Iso9606FmGroup.values)
            if (o != g) fmSet(o),
        ],
        explanation: '${g.code} → ${fmSet(g)}.',
        source: '$kExamIso9606Edition ${t('tab. 3', 'Table 3')}',
      );
    }
  }

  // ── Poziomy jakości EN ISO 5817 ───────────────────────────────────────────

  void _quality() {
    final byStrictness = [...Iso5817Level.values]
      ..sort((a, b) => a.strictness.compareTo(b.strictness));
    final order = byStrictness.map((l) => l.letter).join(', ');
    final strictest = byStrictness.first;
    final mildest = byStrictness.last;
    final explanation =
        t('Od najostrzejszego: $order.', 'From the most stringent: $order.');
    _add(
      id: 'q5817.strict',
      category: ExamCategory.quality,
      prompt: t('Który poziom jakości wg $kIso5817Edition jest najostrzejszy?',
          'Which $kIso5817Edition quality level is the most stringent?'),
      answer: strictest.letter,
      pool: [
        for (final l in byStrictness)
          if (l != strictest) l.letter,
      ],
      explanation: explanation,
      source: kIso5817Edition,
      topic: 'q5817.order',
    );
    _add(
      id: 'q5817.mild',
      category: ExamCategory.quality,
      prompt: t(
          'Który poziom jakości wg $kIso5817Edition jest najłagodniejszy?',
          'Which $kIso5817Edition quality level is the least stringent?'),
      answer: mildest.letter,
      pool: [
        for (final l in byStrictness)
          if (l != mildest) l.letter,
      ],
      explanation: explanation,
      source: kIso5817Edition,
      topic: 'q5817.order',
    );

    final options = _levelOptions(en);
    for (final item in kIso5817Items) {
      // Wydanie 2023 zmieniło tę pozycję — odpowiedź zależałaby od wydania.
      if (iso5817ChangedIn2023(item)) continue;
      final ranges = item.splitsThickness
          ? [Iso5817Range.thin, Iso5817Range.thick]
          : [Iso5817Range.thick];
      for (final range in ranges) {
        final permitted = iso5817PermittedLevels(item, range);
        if (permitted == null) continue;
        final match = [
          for (final o in options)
            if (_sameSet(o.$1, permitted)) o,
        ];
        if (match.length != 1) continue;
        final answer = match.single.$2;
        final kind = item.kinds.length == 2
            ? ''
            : item.kinds.contains(Iso5817WeldKind.butt)
                ? t(', spoina czołowa', ', butt weld')
                : t(', spoina pachwinowa', ', fillet weld');
        final thickness = !item.splitsThickness
            ? ''
            : range == Iso5817Range.thin
                ? t(', 0,5 ≤ t ≤ 3 mm', ', 0.5 ≤ t ≤ 3 mm')
                : ', t > 3 mm';
        // Limit tylko dla niezgodności krótkich (rozdz. 3.3 / 3.4) — pytanie
        // dotyczy niezgodności krótkiej (długa bywa dopuszczalna na mniejszej
        // liczbie poziomów).
        final short = iso5817ShortOnly(item, range)
            ? t(' (niezgodność krótka)', ' (short imperfection)')
            : '';
        final name = en ? item.nameEn : item.namePl;
        final rules = [
          for (final level in [Iso5817Level.d, Iso5817Level.c, Iso5817Level.b])
            '${level.letter}: ${iso5817RuleText(iso5817RuleFor(item, level, range), en: en, symbol: item.symbol)}',
        ].join('; ');
        _add(
          id: 'q5817.lv.${item.id}.${item.splitsThickness ? range.name : 'all'}',
          category: ExamCategory.quality,
          prompt: t(
              '$kIso5817Edition, poz. ${item.no}: „$name”$short (ISO 6520-1: '
                  '${item.codes.join(', ')})$kind$thickness. Na których '
                  'poziomach jakości ta niezgodność jest dopuszczalna '
                  '(w granicach limitu)?',
              '$kIso5817Edition, item ${item.no}: “$name”$short (ISO 6520-1: '
                  '${item.codes.join(', ')})$kind$thickness. At which quality '
                  'levels is this imperfection permitted (within the limit)?'),
          answer: answer,
          pool: [
            for (final o in options)
              if (o.$2 != answer) o.$2,
          ],
          explanation: '$rules.',
          source: '$kIso5817Edition ${t('tab. 1', 'Table 1')}',
          topic: 'q5817.lv.${item.id}',
        );
      }
    }
  }

  // ── Symbole EN ISO 2553 ───────────────────────────────────────────────────

  void _symbols() {
    final kinds = [for (final info in basicSymbolCatalog) info.kind];
    for (final info in basicSymbolCatalog) {
      _add(
        id: 'sym.glyph.${info.kind.name}',
        category: ExamCategory.symbols,
        prompt: t(
            'Jak nazywa się spoina oznaczona tym symbolem podstawowym '
                '(EN ISO 2553)?',
            'What weld does this basic symbol (EN ISO 2553) stand for?'),
        answer: weldKindName(info.kind, en: en),
        pool: [
          for (final k in kinds)
            if (k != info.kind) weldKindName(k, en: en),
        ],
        explanation: en ? info.bodyEn : info.bodyPl,
        source: 'EN ISO 2553:2019 ${t('tab. 1', 'Table 1')}',
        glyph: info.kind,
      );
    }
    for (final system in SymbolSystem.values) {
      final label = system == SymbolSystem.a ? 'A' : 'B';
      final rule = [
        for (final side in WeldSide.values)
          '${sideAsDrawn(system, side, en: en)} → '
              '${weldSideText(side, en: en)}',
      ].join('; ');
      for (final side in [WeldSide.arrow, WeldSide.other]) {
        final drawn = sideAsDrawn(system, side, en: en);
        _add(
          id: 'sym.side.${system.name}.${side.name}',
          category: ExamCategory.symbols,
          prompt: t(
              'EN ISO 2553, system $label: symbol spoiny narysowano — '
                  '„$drawn”. Gdzie wykonać spoinę?',
              'EN ISO 2553, system $label: the weld symbol is drawn '
                  '“$drawn”. Where is the weld made?'),
          answer: _cap(weldSideText(side, en: en)),
          pool: [
            for (final s in WeldSide.values)
              if (s != side) _cap(weldSideText(s, en: en)),
          ],
          explanation: '${t('System', 'System')} $label: $rule.',
          source: 'EN ISO 2553:2019',
          topic: 'sym.side.${system.name}',
        );
      }
    }
  }

  // ── Elektrody, spoiwa, gazy ───────────────────────────────────────────────

  void _consumables() {
    // Elektrody: limity AWS D1.1 tab. 7.1 (kolumna A) — tylko klasy AWS,
    // nie „wg producenta”.
    final aws = [
      for (final c in ElectrodeClass.values)
        if (!c.family.perManufacturer) c,
    ];
    for (final c in aws) {
      final limit = examDuration(c.limitMinutes);
      final explanation = t(
          '${c.code}: $limit na powietrzu; po przekroczeniu — ponowne '
              'suszenie ${c.family.redry(en: en)}.',
          '${c.code}: $limit in the open air; after that — re-drying '
              '${c.family.redry(en: en)}.');
      _add(
        id: 'el.limit.${c.name}',
        category: ExamCategory.consumables,
        prompt: t(
            'AWS D1.1 (tab. 7.1, kolumna A): ile maksymalnie mogą leżeć poza '
                'piecykiem elektrody ${c.code} — ${c.desc(en: en)}?',
            'AWS D1.1 (Table 7.1, column A): how long may ${c.code} '
                'electrodes — ${c.desc(en: en)} — stay out of the oven at '
                'most?'),
        answer: limit,
        pool: [
          for (final o in aws)
            if (o != c) examDuration(o.limitMinutes),
        ],
        explanation: explanation,
        source: 'AWS D1.1:2020 ${t('tab. 7.1', 'Table 7.1')}',
        topic: 'el:${c.limitMinutes}',
      );
      // „Która z poniższych”: wśród odpowiedzi jest tylko jedna klasa z tym
      // limitem; klasy o pokrewnym oznaczeniu (E7018 / E7018-1 / E7018 H4R…)
      // nie są dystraktorami; odpowiedzi pokazują opis klasy.
      _add(
        id: 'el.class.${c.name}',
        category: ExamCategory.consumables,
        prompt: t(
            'Która z poniższych klas elektrod ma wg AWS D1.1 (tab. 7.1, '
                'kolumna A) limit czasu poza piecykiem równy $limit?',
            'Which of the following electrode classes has an out-of-oven '
                'limit of $limit per AWS D1.1 (Table 7.1, column A)?'),
        answer: examElectrodeOption(c, en: en),
        pool: [
          for (final o in aws)
            if (o.limitMinutes != c.limitMinutes &&
                !examElectrodesRelated(o, c))
              examElectrodeOption(o, en: en),
        ],
        explanation: explanation,
        source: 'AWS D1.1:2020 ${t('tab. 7.1', 'Table 7.1')}',
        // Ten sam temat co pytanie o limit — zdradzałyby sobie odpowiedź;
        // pytania o ten sam limit mają też tę samą treść.
        topic: 'el:${c.limitMinutes}',
      );
    }

    // Gazy wg EN ISO 14175.
    for (final g in GasSymbol.values) {
      final desc = g.description.of(english: en);
      _add(
        id: 'gas.sym.${g.code}',
        category: ExamCategory.consumables,
        prompt: t('Co oznacza symbol gazu ${g.code} wg EN ISO 14175?',
            'What does gas symbol ${g.code} (EN ISO 14175) mean?'),
        answer: desc,
        pool: [
          for (final o in GasSymbol.values)
            if (o != g) o.description.of(english: en),
        ],
        explanation: '${g.code} = $desc.',
        source: 'EN ISO 14175:2008 ${t('tab. 3', 'Table 3')}',
        topic: 'gas:${g.code}',
      );
      _add(
        id: 'gas.code.${g.code}',
        category: ExamCategory.consumables,
        prompt: t('Jaki symbol wg EN ISO 14175 ma gaz: „$desc”?',
            'Which EN ISO 14175 symbol has the gas: “$desc”?'),
        answer: g.code,
        pool: [
          for (final o in GasSymbol.values)
            if (o != g) o.code,
        ],
        explanation: '${g.code} = $desc.',
        source: 'EN ISO 14175:2008 ${t('tab. 3', 'Table 3')}',
        topic: 'gas:${g.code}',
      );
    }

    // Dobór spoiwa: rodziny i grupy materiałowe, w których aplikacja je
    // dobiera.
    final families = <String, FillerFamily>{};
    final familyGroups = <String, Set<MaterialGroup>>{};
    final pairs = <(BaseMaterial, BaseMaterial, FillerRecommendation)>[];
    for (final a in BaseMaterial.values) {
      for (final b in BaseMaterial.values) {
        if (b.index < a.index) continue;
        final rec = selectFiller(a, b);
        final f = rec.family;
        if (rec.verdict != FillerVerdict.typical || f == null) continue;
        final key = examAnswerKey(f.name.of(english: en));
        families.putIfAbsent(key, () => f);
        familyGroups.putIfAbsent(key, () => <MaterialGroup>{})
          ..add(a.group)
          ..add(b.group);
        pairs.add((a, b, rec));
      }
    }
    for (final (a, b, rec) in pairs) {
      final answer = rec.family!.name.of(english: en);
      final groups = {a.group, b.group};
      final texts = [rec.summary, ...rec.warnings]
          .expand((x) => [x.pl, x.en])
          .join(' \n ');
      final pool = <String>[];
      for (final entry in families.entries) {
        final name = entry.value.name.of(english: en);
        if (examAnswerKey(name) == examAnswerKey(answer)) continue;
        if (familyGroups[entry.key]!.any(groups.contains)) continue;
        if (fillerTokens(entry.value).any(texts.contains)) continue;
        pool.add(name);
      }
      final aName = a.label.of(english: en);
      final bName = b.label.of(english: en);
      _add(
        id: 'fill.${a.name}.${b.name}',
        category: ExamCategory.consumables,
        prompt: a == b
            ? t(
                'Typowe spoiwo (dobór w aplikacji) do spawania: $aName + '
                    '$aName?',
                'Typical filler (app selection) for welding $aName to '
                    '$aName?')
            : t(
                'Typowe spoiwo (dobór w aplikacji) do połączenia: $aName + '
                    '$bName?',
                'Typical filler (app selection) for joining $aName to '
                    '$bName?'),
        answer: answer,
        pool: pool,
        explanation: '${rec.summary.of(english: en)} '
            '${t('Wiąże WPS.', 'The WPS governs.')}',
        source: t('Dobór spoiwa w aplikacji', 'App filler selection'),
      );
    }
  }

  // ── Definicje (słownik) ───────────────────────────────────────────────────

  /// Kategoria egzaminu dla terminu słownika w pytaniach o definicje
  /// i skróty; `null` — bez pytań (procesy i pozycje mają własne pytania,
  /// a ich definicje się zazębiają).
  static ExamCategory? _termCategory(GlossaryCategory c) => switch (c) {
        GlossaryCategory.imperfection => ExamCategory.imperfections,
        GlossaryCategory.safety => ExamCategory.safety,
        GlossaryCategory.joint ||
        GlossaryCategory.material ||
        GlossaryCategory.piping ||
        GlossaryCategory.testing ||
        GlossaryCategory.tools =>
          ExamCategory.terms,
        GlossaryCategory.process ||
        GlossaryCategory.position ||
        GlossaryCategory.phrase =>
          null,
      };

  void _definitions() {
    bool usable(GlossaryTerm g) =>
        g.defPl != null &&
        g.defEn != null &&
        _termCategory(g.category) != null &&
        // Pojęcia ogólne („niezgodność”, „wada”) obejmują pozostałe.
        (g.category != GlossaryCategory.imperfection || g.iso6520 != null);
    final defined = [
      for (final g in kWeldingGlossary)
        if (usable(g)) g,
    ];
    for (final g in defined) {
      final others = [
        for (final o in defined)
          if (o.id != g.id &&
              o.category == g.category &&
              !glossaryDefinitionsOverlap(g, o) &&
              !(g.iso6520 != null &&
                  o.iso6520 != null &&
                  iso6520Related(g.iso6520!, o.iso6520!)))
            o,
      ];
      final name = _name(g);
      _add(
        id: 'def.${g.id}',
        category: _termCategory(g.category)!,
        prompt: t('Który termin pasuje do definicji: „${_def(g)}”?',
            'Which term matches the definition: “${_def(g)}”?'),
        answer: name,
        pool: others.map(_name),
        explanation: '$name: ${_def(g)}',
        source: t('Słownik spawalniczy aplikacji', 'App welding glossary'),
        topic: _termTopic(g),
      );
    }
  }

  // ── Skróty ────────────────────────────────────────────────────────────────

  void _abbreviations() {
    bool usable(GlossaryTerm g) {
      final code = g.code;
      if (code == null || _termCategory(g.category) == null) return false;
      final pl = glossaryNameWithoutCode(g.pl, code);
      final e = glossaryNameWithoutCode(g.en, code);
      // Nazwa zawiera skrót mimo obcięcia (np. „atest 3.1”) — pytanie bez
      // sensu.
      return !pl.contains(code) && !e.contains(code);
    }

    final terms = [
      for (final g in kWeldingGlossary)
        if (usable(g)) g,
    ];
    String expanded(GlossaryTerm g) =>
        glossaryNameWithoutCode(_name(g), g.code);
    for (final g in terms) {
      final code = g.code!;
      final name = expanded(g);
      final other = en ? null : glossaryNameWithoutCode(g.en, code);
      _add(
        id: 'abbr.${g.id}',
        category: _termCategory(g.category)!,
        prompt: t('Co oznacza skrót „$code”?', 'What does “$code” stand for?'),
        answer: name,
        pool: [
          for (final o in terms)
            if (o.id != g.id) expanded(o),
        ],
        explanation: _withDef(
            other == null ? '$code — $name.' : '$code — $name (ang. $other).',
            g),
        source: t('Słownik spawalniczy aplikacji', 'App welding glossary'),
        topic: _termTopic(g),
      );
    }
  }

  // ── Słownictwo PL → EN / DE (EN → DE w interfejsie EN) ────────────────────

  void _vocabulary() {
    final source = _ui;
    final targets =
        en ? const [GlossaryLang.de] : const [GlossaryLang.en, GlossaryLang.de];
    final terms = [
      for (final g in kWeldingGlossary)
        if (g.category != GlossaryCategory.phrase) g,
    ];
    for (final target in targets) {
      for (final g in terms) {
        final from = g.text(source);
        final to = g.text(target);
        if (normalizeGlossary(from) == normalizeGlossary(to)) continue;
        final synonyms = {
          for (final s in g.synonymsFor(target)) normalizeGlossary(s),
        };
        final pool = <String>[];
        for (final o in terms) {
          if (o.id == g.id || o.category != g.category) continue;
          final oTo = o.text(target);
          final n = normalizeGlossary(oTo);
          if (n == normalizeGlossary(to) || synonyms.contains(n)) continue;
          if (o
              .synonymsFor(target)
              .map(normalizeGlossary)
              .contains(normalizeGlossary(to))) {
            continue;
          }
          if (normalizeGlossary(o.text(source)) == normalizeGlossary(from)) {
            continue;
          }
          pool.add(oTo);
        }
        final langName = switch (target) {
          GlossaryLang.de => t('po niemiecku', 'in German'),
          _ => t('po angielsku', 'in English'),
        };
        final translations = [
          for (final l in targets) '${l.code}: ${g.text(l)}',
        ].join(' · ');
        _add(
          id: 'vocab.${target.name}.${g.id}',
          category: g.category == GlossaryCategory.safety
              ? ExamCategory.safety
              : ExamCategory.vocabulary,
          prompt:
              t('Jak jest $langName: „$from”?', 'What is “$from” $langName?'),
          answer: to,
          pool: pool,
          explanation: '$from — $translations.',
          source: t('Słownik spawalniczy aplikacji', 'App welding glossary'),
          topic: _termTopic(g),
        );
      }
    }
  }
}

/// Fragmenty nazwy spoiwa, po których poznać, że tekst (uzasadnienie,
/// ostrzeżenie) o nim wspomina: ciągi ≥ 3 znaków z cyfrą („309L”, „5356”,
/// „G3Si1”, „1CrMo”).
List<String> fillerTokens(FillerFamily f) => {
      for (final name in [f.name.pl, f.name.en])
        for (final part in name.split(RegExp(r'[^A-Za-z0-9]+')))
          if (part.length >= 3 && part.contains(RegExp(r'\d'))) part,
    }.toList();
