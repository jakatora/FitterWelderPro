// Wady spoin: przyczyny i naprawa — wybór przyczyn, wyszukiwarka, tekst do
// udostępnienia. Czysty Dart (bez Fluttera).
//
// Dane: lib/data/weld_defects.dart. Model: defect_model.dart.
//
// Zasady wyboru ([defectAdvice]):
//  • przyczyna wchodzi, gdy dotyczy wybranego procesu, a materiał / pozycja
//    są puste (każdy) albo pasują do wybranych;
//  • bez wybranego materiału / pozycji widać wszystkie przyczyny procesu
//    (ekran oznacza materiał / pozycję przy przyczynie);
//  • kolejność: najpierw przyczyny typowe dla WYBRANEJ pozycji, potem wg
//    [DefectCause.rank] (1 = najczęstsza / najszybsza do sprawdzenia),
//    przy remisie — kolejność w danych.

import '../../data/weld_defects.dart';
import '../glossary/glossary.dart' show normalizeGlossary;
import '../iso5817/iso5817_table.dart';
import 'defect_model.dart';

export 'defect_model.dart';

/// Wynik dla wybranej wady, procesu, materiału i pozycji.
class DefectAdvice {
  final WeldDefect defect;
  final DefectProcess process;

  /// Materiał użyty do filtrowania (null = wszystkie).
  final DefectMaterial? material;
  final DefectPosition? position;

  /// Przyczyny w kolejności sprawdzania.
  final List<DefectCause> causes;

  /// Kroki naprawy dla procesu / materiału.
  final List<DefectStep> repair;

  /// „Przed następnym ściegiem”.
  final List<DefectStep> checklist;

  /// Pozycje EN ISO 5817 (tablica 1) z tymi samymi numerami ISO 6520-1.
  final List<Iso5817Item> iso5817;

  /// To samo z numerami wady, których dotyczy każda pozycja.
  final List<Iso5817Link> iso5817Links;

  /// Numery wady bez pozycji VT w aplikacji (limity wewnętrznych —
  /// pełna norma / specyfikacja RT / UT).
  final List<Iso6520Ref> iso5817Uncovered;

  const DefectAdvice({
    required this.defect,
    required this.process,
    required this.material,
    required this.position,
    required this.causes,
    required this.repair,
    required this.checklist,
    required this.iso5817,
    required this.iso5817Links,
    required this.iso5817Uncovered,
  });
}

/// Materiał, którym faktycznie filtrujemy: gdy dla wady i procesu zostaje
/// jeden materiał (131 → aluminium, pęknięcia wodorowe → stal węglowa), to
/// on; materiał spoza listy jest ignorowany (null = wszystkie).
DefectMaterial? effectiveMaterial(
    WeldDefect defect, DefectProcess process, DefectMaterial? material) {
  final allowed = defect.materialsFor(process);
  if (allowed.length == 1) return allowed.first;
  if (material != null && allowed.contains(material)) return material;
  return null;
}

bool _materialOk(Set<DefectMaterial> set, DefectMaterial? m) =>
    m == null || set.isEmpty || set.contains(m);

bool _stepOk(DefectStep s, DefectProcess p, DefectMaterial? m) =>
    (s.processes.isEmpty || s.processes.contains(p)) &&
    _materialOk(s.materials, m);

/// Przyczyny, naprawa i lista kontrolna dla wady [defect] w procesie
/// [process]; `null`, gdy wada nie dotyczy tego procesu.
DefectAdvice? defectAdvice(
  WeldDefect defect,
  DefectProcess process, {
  DefectMaterial? material,
  DefectPosition? position,
}) {
  if (!defect.processes.contains(process)) return null;
  final m = effectiveMaterial(defect, process, material);

  final indexed = <(int, DefectCause)>[];
  for (final (i, c) in defect.causes.indexed) {
    if (!c.appliesTo(process)) continue;
    if (!_materialOk(c.materials, m)) continue;
    if (position != null &&
        c.positions.isNotEmpty &&
        !c.positions.contains(position)) {
      continue;
    }
    indexed.add((i, c));
  }
  int positionKey(DefectCause c) =>
      position != null && c.positions.contains(position) ? 0 : 1;
  indexed.sort((a, b) {
    final byPos = positionKey(a.$2).compareTo(positionKey(b.$2));
    if (byPos != 0) return byPos;
    final byRank = a.$2.rank.compareTo(b.$2.rank);
    if (byRank != 0) return byRank;
    return a.$1.compareTo(b.$1);
  });

  return DefectAdvice(
    defect: defect,
    process: process,
    material: m,
    position: position,
    causes: [for (final e in indexed) e.$2],
    repair: [
      for (final s in defect.repair)
        if (_stepOk(s, process, m)) s
    ],
    checklist: [
      for (final s in defect.checklist)
        if (_stepOk(s, process, m)) s
    ],
    iso5817: iso5817ItemsForDefect(defect),
    iso5817Links: iso5817LinksForDefect(defect),
    iso5817Uncovered: iso5817UncoveredRefs(defect),
  );
}

/// Pozycja tablicy 1 EN ISO 5817 z numerami wady, których dotyczy.
class Iso5817Link {
  final Iso5817Item item;

  /// Numery ISO 6520-1 wady objęte tą pozycją.
  final List<Iso6520Ref> refs;
  const Iso5817Link(this.item, this.refs);

  /// „1.7 (5011, 5012)”.
  String get label => '${item.no} (${refs.map((r) => r.code).join(', ')})';
}

/// Numer nadrzędny ISO 6520-1: 5011 → 501, 101 → 100; dla 100, 200… — null.
int? _parentCode(int code) {
  if (code >= 1000) return code ~/ 10;
  if (code % 100 != 0) return (code ~/ 100) * 100;
  return null;
}

/// Pozycja z numerem [itemCode] obejmuje numer [code]: ten sam numer albo
/// jego podgrupa (101 → 100 „Pęknięcie”, 4011 → 401 „Przyklejenie”).
bool _covers(int itemCode, int code) {
  for (int? c = code; c != null; c = _parentCode(c)) {
    if (c == itemCode) return true;
  }
  return false;
}

/// Pozycje tablicy 1 EN ISO 5817 (z aplikacji — tylko odbiór wizualny VT)
/// dla numerów wady, w kolejności tablicy. Numer z własną pozycją (104 →
/// 1.2) nie dostaje dodatkowo pozycji nadrzędnej (100 → 1.1); numer bez
/// własnej (101) — pozycję nadrzędną. Bliźniacze pozycje czołowa /
/// pachwinowa (1.3, 1.12) — jedna: pachwinowa, gdy wada ma pozycję tylko
/// pachwinową (np. 1.10), inaczej czołowa. Warianty tego samego rodzaju
/// spoiny (3.1 blachy / rury) zostają oba.
List<Iso5817Link> iso5817LinksForDefect(WeldDefect defect) {
  final perItem = <Iso5817Item, List<Iso6520Ref>>{};
  for (final r in defect.refs) {
    final exact = [
      for (final i in kIso5817Items)
        if (i.codes.contains(r.code)) i
    ];
    final hits = exact.isNotEmpty
        ? exact
        : [
            for (final i in kIso5817Items)
              if (i.codes.any((ic) => _covers(ic, r.code))) i
          ];
    for (final i in hits) {
      perItem.putIfAbsent(i, () => []).add(r);
    }
  }
  final matching = [
    for (final i in kIso5817Items)
      if (perItem[i] != null) Iso5817Link(i, perItem[i]!)
  ];
  // Pozycja tylko pachwinowa bez czołowego bliźniaka (1.10, 1.16, 1.20…)
  // oznacza wadę spoin pachwinowych.
  bool filletOnly(Iso5817Item i) =>
      i.kinds.length == 1 &&
      i.appliesTo(Iso5817WeldKind.fillet) &&
      !matching.any((l) =>
          l.item.no == i.no && l.item.appliesTo(Iso5817WeldKind.butt));
  final preferred = matching.any((l) => filletOnly(l.item))
      ? Iso5817WeldKind.fillet
      : Iso5817WeldKind.butt;
  final dropped = <Iso5817Link>{};
  for (final a in matching) {
    for (final b in matching) {
      if (identical(a, b) || a.item.no != b.item.no) continue;
      final twins = a.item.kinds.intersection(b.item.kinds).isEmpty;
      if (twins && !a.item.appliesTo(preferred)) dropped.add(a);
    }
  }
  return [
    for (final l in matching)
      if (!dropped.contains(l)) l
  ];
}

/// Same pozycje z [iso5817LinksForDefect].
List<Iso5817Item> iso5817ItemsForDefect(WeldDefect defect) =>
    [for (final l in iso5817LinksForDefect(defect)) l.item];

/// Numery wady bez pozycji VT w aplikacji (np. pory wewnętrzne 2011–2016,
/// żużel 301) — ich limity są w pełnej normie / specyfikacji RT / UT.
List<Iso6520Ref> iso5817UncoveredRefs(WeldDefect defect) {
  final covered = {
    for (final l in iso5817LinksForDefect(defect)) ...l.refs.map((r) => r.code)
  };
  return [
    for (final r in defect.refs)
      if (!covered.contains(r.code)) r
  ];
}

/// Uwaga o zakresie pozycji ISO 5817 w aplikacji (ekran i udostępnianie).
String iso5817ScopeNote({required bool en}) => en
    ? 'The app holds only the items for visual testing (VT); limits for '
        'internal imperfections — the full standard / RT / UT specification.'
    : 'Aplikacja zawiera tylko pozycje do odbioru wizualnego (VT); limity '
        'niezgodności wewnętrznych — pełna norma / specyfikacja RT / UT.';

/// Wada po identyfikatorze (null, gdy nie ma).
WeldDefect? weldDefectById(String id) {
  for (final d in kWeldDefects) {
    if (d.id == id) return d;
  }
  return null;
}

/// Wady, które dotyczą procesu (w kolejności danych).
List<WeldDefect> defectsForProcess(DefectProcess process) =>
    [for (final d in kWeldDefects) if (d.processes.contains(process)) d];

String _haystack(WeldDefect d) => normalizeGlossary([
      d.title.pl,
      d.title.en,
      for (final r in d.refs) ...[r.pl, r.en, '${r.code}'],
      ...d.keywords,
    ].join(' '));

/// Szuka wad po nazwie PL / EN (tytuł, oficjalne nazwy ISO 6520-1, słowa
/// potoczne) i po numerze ISO 6520-1. Wielkość liter i polskie znaki bez
/// znaczenia; każde słowo zapytania musi wystąpić. Pusty wynik dla pustego
/// zapytania. Wyżej: dokładny numer, potem nazwa od początku.
List<WeldDefect> searchDefects(String query,
    {List<WeldDefect> defects = kWeldDefects}) {
  final q = normalizeGlossary(query);
  if (q.isEmpty) return const [];
  final terms = q.split(' ');
  final hits = <(int, int, WeldDefect)>[];
  for (final (i, d) in defects.indexed) {
    final hay = _haystack(d);
    if (!terms.every(hay.contains)) continue;
    final titles = [normalizeGlossary(d.title.pl), normalizeGlossary(d.title.en)];
    final names = [
      for (final r in d.refs) ...[normalizeGlossary(r.pl), normalizeGlossary(r.en)]
    ];
    var score = 0;
    if (d.codes.any((c) => '$c' == q)) {
      score = 100;
    } else if (d.codes.any((c) => '$c'.startsWith(q))) {
      score = 80;
    } else if (titles.any((t) => t.startsWith(q))) {
      score = 60;
    } else if (names.any((n) => n.startsWith(q))) {
      score = 50;
    } else if (titles.any((t) => t.contains(q))) {
      score = 40;
    } else if (names.any((n) => n.contains(q))) {
      score = 30;
    } else {
      score = 10;
    }
    hits.add((score, i, d));
  }
  hits.sort((a, b) {
    final s = b.$1.compareTo(a.$1);
    return s != 0 ? s : a.$2.compareTo(b.$2);
  });
  return [for (final h in hits) h.$3];
}

/// Etykiety źródeł przyczyny („TWI · Lincoln”).
String defectSourceLabel(List<String> keys) => <String>{
      for (final k in keys)
        if (kDefectSources[k] != null) kDefectSources[k]!.short
    }.join(' · ');

/// Ostrzeżenie wyświetlane na ekranie i dopisywane do udostępnianego tekstu.
String defectDisclaimer({required bool en}) => en
    ? 'Hints for finding the cause, not a procedure. The WPS, the filler '
        'data sheet and the project repair procedure are binding (preheat, '
        'repair method, number of repairs allowed in one place, NDT after '
        'repair).'
    : 'Podpowiedź do szukania przyczyny, nie procedura. Wiążące są WPS, '
        'karta spoiwa i procedura naprawy z projektu (podgrzewanie, sposób '
        'naprawy, dopuszczalna liczba napraw w tym samym miejscu, badania po '
        'naprawie).';

/// Tekst do udostępnienia (SMS, komunikator, e-mail).
String buildDefectShareText(
  DefectAdvice a, {
  required bool en,
  Set<String> checked = const {},
}) {
  final d = a.defect;
  final b = StringBuffer()
    ..writeln(en ? 'Weld defect: ${d.title.en}' : 'Wada spoiny: ${d.title.pl}')
    ..writeln('ISO 6520-1: ${[
      for (final r in d.refs) '${r.code} ${en ? r.en : r.pl}'
    ].join('; ')}');
  final parts = <String>[
    '${en ? 'Process' : 'Proces'}: ${a.process.label}',
    if (a.material != null)
      '${en ? 'Material' : 'Materiał'}: ${en ? a.material!.en : a.material!.pl}',
    if (a.position != null)
      '${en ? 'Position' : 'Pozycja'}: ${a.position!.code}',
  ];
  b
    ..writeln(parts.join(' · '))
    ..writeln()
    ..writeln(en
        ? 'Causes (check in this order):'
        : 'Przyczyny (sprawdzaj po kolei):');
  for (final (i, c) in a.causes.indexed) {
    b
      ..writeln('${i + 1}. ${c.cause.of(en: en)}')
      ..writeln('   ${en ? 'Check' : 'Sprawdź'}: ${c.check.of(en: en)}')
      ..writeln('   ${en ? 'Fix' : 'Zaradczo'}: ${c.fix.of(en: en)}');
  }
  if (a.repair.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Repair:' : 'Naprawa:');
    for (final (i, s) in a.repair.indexed) {
      b.writeln('${i + 1}. ${s.text.of(en: en)}');
    }
    b.writeln('${en ? 'Cut out' : 'Do wycięcia'}: ${d.cutOut.of(en: en)}');
  }
  if (d.safety.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Safety:' : 'BHP:');
    for (final s in d.safety) {
      b.writeln('- ${s.of(en: en)}');
    }
  }
  if (a.checklist.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Before the next run:' : 'Przed następnym ściegiem:');
    for (final s in a.checklist) {
      b.writeln('[${checked.contains(s.id) ? 'x' : ' '}] ${s.text.of(en: en)}');
    }
  }
  b.writeln();
  if (a.iso5817Links.isNotEmpty) {
    b.writeln('${en ? 'Limits' : 'Limity'}: EN ISO 5817, '
        '${en ? 'Table 1 item' : 'tablica 1 poz.'} '
        '${a.iso5817Links.map((l) => l.label).join(', ')}');
  }
  if (a.iso5817Uncovered.isNotEmpty) {
    final codes = a.iso5817Uncovered.map((r) => r.code).join(', ');
    b.writeln(a.iso5817Links.isEmpty
        ? '${en ? 'Limits' : 'Limity'}: ${iso5817ScopeNote(en: en)}'
        : '$codes: ${iso5817ScopeNote(en: en)}');
  }
  b
    ..writeln()
    ..write(defectDisclaimer(en: en));
  return b.toString();
}
