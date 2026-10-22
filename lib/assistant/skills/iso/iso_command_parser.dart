// Polecenie rysowania Zeszytu ISO z wypowiedzi (plan 3.2, spec §4.5).
//
// Czysta funkcja [parseIsoCommand]: „narysuj rura dwa metry w prawo kolano
// w górę rura metr” → [IsoPipe(right, 2000), IsoTurn(up), IsoPipe(1000)].
// Żadnego I/O, żadnego stanu — umiejętność `iso.draw` woła ją w `match`.
//
// Gramatyka (kolejność elementów = kolejność rysowania):
//   rura | rurę | rurka | rury | odcinek | pipe   [długość] [kierunek] [DN]
//   kolano | kolanko | łuk | skręt | elbow | bend [45|90] [kierunek] [DN]
//       — „kolano” to ZAMIAR skrętu następnej rury (kolano wstawia zeszyt);
//   kolano 45 wymaga kierunku płaszczyzny skrętu; trójnik wspiera przelot
//   i osobne odgałęzienie. Inne kąty / olet wymagają dalszej obsługi;
//   kołnierz [zaślepiający] | zaślepka | dennica | redukcja [DN na DN] |
//   zawór (kulowy | zasuwa | zwrotny | grzybkowy | przepustnica) | spoina
//   [montażowa] | podpora   [DN];
//   kierunki: w prawo / w lewo / w górę / w dół / do przodu / do tyłu
//   (EN right / left / up / down / forward / back) oraz strony świata
//   (północ / południe / wschód / zachód) — te rozwiązuje dopiero strzałka
//   północy na rysunku ([IsoCommand.compassAt]);
//   polecenia: „nowy rysunek”, „cofnij”, „zmień ostatnie kolano w górę”.
//
// Zasada jak w całym asystencie: niejasne → ostrzeżenie albo null (umiejętność
// dopyta), NIGDY cichy zły rysunek. Pytania („ile waży rura dn50”), zapisy
// („zapisz spawam rurę…”) i słowa innych modułów (ścianka, waga, prąd)
// odrzucamy tutaj, żeby rysowanie nie podkradało cudzych zamiarów.

import 'package:flutter/foundation.dart';
import '../../../domain/iso_notebook/sketch_settings.dart';

import '../../../domain/fitter/pipe_size_lookup.dart' show dnForNps, knownDns;
import '../../../i18n/app_language.dart';
import '../../../screens/iso_notebook_screen.dart'
    show
        IsoCompass,
        IsoDir,
        IsoFitting,
        IsoPipe,
        IsoStep,
        IsoTurn,
        kIsoNotebookDnChoices;
import '../../core/spoken_numbers.dart' show SpokenItem, isInchUnit;
import '../../core/utterance.dart';
import '../../core/command_words.dart' show referencesInstruction;
import '../core/skill_words.dart' show mentionsWall, mentionsWeight;

/// Narzędzie zastępcze: „zawór” bez rodzaju. Nie trafia do zeszytu —
/// umiejętność najpierw pyta, jaki to zawór.
const String kIsoAnyValve = 'valve';

/// Zawory, które zeszyt umie postawić (nazwy narzędzi [IsoFitting.tool]).
const List<String> kIsoValveTools = [
  'ballValve',
  'gateValve',
  'checkValve',
  'globeValve',
  'butterflyValve',
];

enum IsoCommandKind {
  /// Rysuj [IsoCommand.steps] (opcjonalnie na nowym arkuszu).
  draw,

  /// Sam „nowy rysunek” — bez elementów.
  newSketch,

  /// „Cofnij” — ostatni krok na rysunku.
  undo,

  /// „Zmień ostatnie kolano w górę” — cofnij ostatnie polecenie i narysuj je
  /// jeszcze raz z innym skrętem.
  changeLastTurn,
  /// Replace only the entered ISO dimension, preserving geometry and take-outs.
  setPipeDimension,
  renameSketch,
  setRootGap,
}

enum IsoParseWarningKind {
  /// „rura 2” — liczba bez jednostki przyjęta jako metry ([IsoParseWarning
  /// .value] = mm).
  lengthAssumedMeters,

  /// Kolano inne niż 90° ([IsoParseWarning.value] = kąt).
  unsupported45,

  /// A mitred/segmented bend has no native ISO component contract yet.
  unsupportedSegmentedBend,

  /// Trójnik / olet / odgałęzienie.
  unsupportedTee,

  /// „Zawór” bez rodzaju (krok to [kIsoAnyValve]).
  valveTypeMissing,

  /// An axial body in a route cannot turn flow by itself.
  axialDirectionRequiresPipe,

  /// More than one direction was assigned to one drawing element.
  directionAmbiguous,

  /// Explicit fitting sizes are ambiguous, invalid or not supported by this symbol.
  invalidSymbolSize,
}

@immutable
class IsoParseWarning {
  const IsoParseWarning(this.kind, {this.step, this.value});

  final IsoParseWarningKind kind;

  /// Indeks kroku w [IsoCommand.steps], którego dotyczy.
  final int? step;
  final double? value;

  @override
  bool operator ==(Object other) =>
      other is IsoParseWarning &&
      other.kind == kind &&
      other.step == step &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kind, step, value);

  @override
  String toString() =>
      'IsoParseWarning(${kind.name}${step != null ? ' @$step' : ''}'
      '${value != null ? ' = $value' : ''})';
}

/// Wynik [parseIsoCommand].
@immutable
class IsoCommand {
  const IsoCommand({
    required this.kind,
    this.steps = const [],
    this.newSketch = false,
    this.fromLastTee = false,
    this.explicitLastTee = false,
    this.append = false,
    this.turnDir,
    this.turnCompass,
    this.compassAt = const {},
    this.warnings = const [],
    this.explicit = false,
    this.strong = false,
    this.unknownWords = 0,
    this.dimensionMm,
    this.pipeOrdinal,
    this.sketchName,
    this.gapMm,
  });

  final IsoCommandKind kind;
  final double? dimensionMm;
  /// One-based creation order; null identifies the last pipe.
  final int? pipeOrdinal;
  final String? sketchName;
  final double? gapMm;

  /// Kroki do narysowania ([IsoCommandKind.draw]).
  final List<IsoStep> steps;

  /// Padło „nowy rysunek / od nowa / new drawing”.
  final bool newSketch;
  final bool fromLastTee;
  final bool explicitLastTee;

  /// Padło „dorysuj / do tego rysunku / add to the drawing” — rysuj do
  /// ostatniego szkicu bez pytania.
  final bool append;

  /// Nowy kierunek ostatniego skrętu ([IsoCommandKind.changeLastTurn]).
  final IsoDir? turnDir;

  /// Strona świata zamiast [turnDir] — do rozwiązania strzałką północy.
  final IsoCompass? turnCompass;

  /// Kroki, których kierunek padł jako strona świata (indeks → strona).
  /// Kierunek kroku w [steps] jest wtedy pusty, dopóki umiejętność nie
  /// rozwiąże go przez strzałkę północy (albo nie dopyta).
  final Map<int, IsoCompass> compassAt;

  final List<IsoParseWarning> warnings;

  /// Jawny zamiar rysowania („narysuj”, „do rysunku”, „nowy rysunek”,
  /// „ostatnie kolano”) — bez niego polecenie liczy się tylko w zeszycie.
  final bool explicit;

  /// Konkretne polecenie (≥ 2 elementy albo element z kierunkiem, długością
  /// czy DN; „cofnij”) — samo „rura” w zeszycie to jeszcze za mało.
  final bool strong;

  /// Słowa spoza gramatyki rysowania (obniżają pewność).
  final int unknownWords;

  bool has(IsoParseWarningKind k) => warnings.any((w) => w.kind == k);

  IsoParseWarning? firstWarning(IsoParseWarningKind k) {
    for (final w in warnings) {
      if (w.kind == k) return w;
    }
    return null;
  }

  /// Kopia z innymi krokami / stronami świata / ostrzeżeniami.
  IsoCommand copyWith({
    List<IsoStep>? steps,
    Map<int, IsoCompass>? compassAt,
    List<IsoParseWarning>? warnings,
    bool? newSketch,
    bool? fromLastTee,
    bool? explicitLastTee,
    bool? append,
  }) =>
      IsoCommand(
        kind: kind,
        dimensionMm: dimensionMm,
        pipeOrdinal: pipeOrdinal,
        sketchName: sketchName,
        gapMm: gapMm,
        steps: steps ?? this.steps,
        newSketch: newSketch ?? this.newSketch,
        append: append ?? this.append,
        fromLastTee: fromLastTee ?? this.fromLastTee,
        explicitLastTee: explicitLastTee ?? this.explicitLastTee,
        turnDir: turnDir,
        turnCompass: turnCompass,
        compassAt: compassAt ?? this.compassAt,
        warnings: warnings ?? this.warnings,
        explicit: explicit,
        strong: strong,
        unknownWords: unknownWords,
      );

  /// [IsoCommandKind.changeLastTurn] z rozwiązanym kierunkiem.
  IsoCommand withTurnDir(IsoDir dir) => IsoCommand(
        kind: kind,
        steps: steps,
        newSketch: newSketch,
        append: append,
        fromLastTee: fromLastTee,
        explicitLastTee: explicitLastTee,
        turnDir: dir,
        compassAt: compassAt,
        warnings: warnings,
        explicit: explicit,
        strong: strong,
        unknownWords: unknownWords,
      );

  /// Fills one explicitly missing valve type, preserving the rest of the
  /// sequence. Conflicting types or ambiguous sizes leave it unanswered.
  IsoCommand? chooseValve(Utterance answer) {
    if (answer.hasAny(const ['nie', 'not', 'no', 'bez', 'without'])) {
      return null;
    }
    for (final token in answer.tokens) {
      final element = _element(token);
      if (element != null && element != _El.valve) return null;
    }
    final types = {
      for (final token in answer.tokens)
        if (token != 'return' || answer.hasAny(const ['non return']))
          if (_valveTypeOf(token) case final type?) type
    };
    if (types.length != 1) return null;
    final missing = firstWarning(IsoParseWarningKind.valveTypeMissing);
    final index = missing?.step;
    if (index == null || index < 0 || index >= steps.length) return null;
    final original = steps[index];
    if (original is! IsoFitting || original.tool != kIsoAnyValve) return null;
    final sizeMentioned = answer.mentionsDn ||
        answer.hasAny(const ['nps']) ||
        answer.tokens.any(isInchUnit);
    final dn = _dnOf(answer);
    if (sizeMentioned && (dn == null || !kIsoNotebookDnChoices.contains(dn))) {
      return null;
    }
    if (!sizeMentioned && answer.items.any((item) => item.isNumber)) {
      return null;
    }
    if (_directionsIn(answer.items).length > 1) return null;
    final direction = isoDirectionOf(answer), compass = isoCompassOf(answer);
    if ((direction != null || compass != null) && !original.symbolOnly) {
      return null;
    }
    final copy = List<IsoStep>.from(steps);
    copy[index] = IsoFitting(types.single,
        dn: dn ?? original.dn,
        dnOut: original.dnOut,
        symbolOnly: original.symbolOnly,
        dir: direction ?? (compass == null ? original.dir : null));
    final directions = Map<int, IsoCompass>.from(compassAt);
    if (direction != null) directions.remove(index);
    if (compass != null) directions[index] = compass;
    return copyWith(steps: copy, compassAt: directions, warnings: [
      for (final w in warnings)
        if (w != missing) w
    ]);
  }

  /// A 45-degree bend specifies a plane through a target axis. Ask before
  /// opening or modifying a sheet if neither it nor its following pipe has one.
  int? get missingSpatialTurnDirection {
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step is! IsoTurn ||
          step.degrees != 45 ||
          step.toDir != null ||
          compassAt.containsKey(i)) {
        continue;
      }
      final following = i + 1 < steps.length ? steps[i + 1] : null;
      // Let the controller report a missing downstream pipe first.
      if (following is! IsoPipe) continue;
      if ((following.dir != null || compassAt.containsKey(i + 1))) {
        continue;
      }
      return i;
    }
    return null;
  }

  IsoCommand withSpatialTurnDirection(
      int index, IsoDir? direction, IsoCompass? compass) {
    final copy = List<IsoStep>.from(steps);
    final original = copy[index] as IsoTurn;
    copy[index] =
        IsoTurn(toDir: direction, dn: original.dn, degrees: original.degrees);
    return copyWith(steps: copy, compassAt: {
      ...compassAt,
      if (compass != null) index: compass,
    });
  }

  /// Resolves all compass references together. A missing north arrow leaves
  /// the original command untouched; no partial direction is guessed.
  IsoCommand? resolveCompass(IsoDir? Function(IsoCompass) direction) {
    final resolved = List<IsoStep>.from(steps);
    for (final e in compassAt.entries) {
      if (e.key < 0 || e.key >= resolved.length) return null;
      if (resolved[e.key] is! IsoPipe &&
          resolved[e.key] is! IsoTurn &&
          !(resolved[e.key] is IsoFitting &&
              (resolved[e.key] as IsoFitting).symbolOnly)) {
        return null;
      }
      final dir = direction(e.value);
      if (dir == null) return null;
      resolved[e.key] = switch (resolved[e.key]) {
        IsoPipe(:final lengthMm) => IsoPipe(dir: dir, lengthMm: lengthMm),
        IsoTurn(:final dn, :final degrees) =>
          IsoTurn(toDir: dir, dn: dn, degrees: degrees),
        IsoFitting(:final tool, :final dn, :final dnOut) =>
          IsoFitting(tool, dn: dn, dnOut: dnOut, symbolOnly: true, dir: dir),
      };
    }
    var command = copyWith(steps: resolved, compassAt: const {});
    if (turnCompass case final compass?) {
      final dir = direction(compass);
      if (dir == null) return null;
      command = command.withTurnDir(dir);
    }
    return command;
  }

  @override
  String toString() => 'IsoCommand(${kind.name}, $steps'
      '${newSketch ? ', newSketch' : ''}${append ? ', append' : ''}'
      '${turnDir != null ? ', turnDir: ${turnDir!.name}' : ''}'
      '${turnCompass != null ? ', turnCompass: ${turnCompass!.name}' : ''}'
      '${compassAt.isNotEmpty ? ', compass: $compassAt' : ''}'
      '${warnings.isNotEmpty ? ', $warnings' : ''})';
}

// ═══════════════════════════════════════════════════════════════════════════
// Słowa
// ═══════════════════════════════════════════════════════════════════════════

enum _El { pipe, turn, tee, flange, cap, reducer, valve, weld, support }

/// Element, który zaczyna się od słowa [w], albo null.
_El? _element(String w) {
  if (w.startsWith('rurocia')) return null; // „rurociąg” — instalacja, nie rura
  if (w.startsWith('rur') ||
      w.startsWith('odcink') ||
      w == 'odcinek' ||
      w == 'pipe' ||
      w == 'pipes' ||
      w == 'tube') {
    return _El.pipe;
  }
  if (w.startsWith('kolan') ||
      w == 'luk' ||
      w == 'luku' ||
      w == 'luki' ||
      w == 'lukiem' ||
      w.startsWith('skret') ||
      w.startsWith('skrec') ||
      w == 'elbow' ||
      w == 'elbows' ||
      w == 'bend' ||
      w == 'turn') {
    return _El.turn;
  }
  if (w.startsWith('trojnik') ||
      w.startsWith('odgalez') ||
      w.startsWith('odejsci') ||
      w == 'tee' ||
      w == 'tees' ||
      w == 'olet' ||
      w == 'branch') {
    return _El.tee;
  }
  // „kołnierzowa” (zaślepka kołnierzowa) to przymiotnik, nie nowy kołnierz.
  if (w.startsWith('kolnierzow')) return null;
  if (w.startsWith('kolnierz') || w == 'flange' || w == 'flanges') {
    return _El.flange;
  }
  // „zaślepiający” (kołnierz zaślepiający) to przymiotnik.
  if (w.startsWith('zaslepiaj')) return null;
  if (w.startsWith('zaslep') ||
      w.startsWith('denn') ||
      w == 'cap' ||
      w == 'caps' ||
      w == 'endcap') {
    return _El.cap;
  }
  if (w.startsWith('redukc') ||
      w.startsWith('zwezk') ||
      w == 'reducer' ||
      w == 'reducers') {
    return _El.reducer;
  }
  if (w.startsWith('zawor') ||
      w.startsWith('zasuw') ||
      w.startsWith('przepustnic') ||
      w == 'valve' ||
      w == 'valves') {
    return _El.valve;
  }
  if (w.startsWith('spoin') || w == 'weld' || w == 'welds') return _El.weld;
  if (w.startsWith('podpor') ||
      w.startsWith('wspornik') ||
      w == 'support' ||
      w == 'supports') {
    return _El.support;
  }
  return null;
}

/// Rodzaj zaworu ze słowa (PL po rzeczowniku, EN przed nim).
String? _valveTypeOf(String w) {
  if (w.startsWith('kulow') || w == 'ball') return 'ballValve';
  if (w.startsWith('zasuw') || w == 'gate') return 'gateValve';
  if (w.startsWith('zwrotn') ||
      w == 'check' ||
      w == 'nonreturn' ||
      w == 'return') {
    return 'checkValve';
  }
  if (w.startsWith('grzybk') || w == 'globe') return 'globeValve';
  if (w.startsWith('przepustnic') ||
      w.startsWith('motylk') ||
      w == 'butterfly') {
    return 'butterflyValve';
  }
  return null;
}

bool _isBlindWord(String w) =>
    w.startsWith('zaslepiaj') ||
    w == 'slepy' ||
    w == 'slepa' ||
    w == 'slepego' ||
    w == 'blind' ||
    w.startsWith('kolnierzow');

bool _isFieldWord(String w) =>
    w.startsWith('montazow') || w == 'field' || w == 'site';

/// Słowa, które stoją PRZED swoim elementem (EN: „ball valve”, „blind
/// flange”, „field weld”, „end cap”).
bool _isLeadIn(String w, _El el) => switch (el) {
      _El.valve => _valveTypeOf(w) != null && !w.startsWith('zasuw'),
      _El.flange => w == 'blind',
      _El.weld => w == 'field' || w == 'site',
      _El.cap => w == 'end',
      _ => false,
    };

const Map<String, IsoDir> _dirWords = {
  'prawo': IsoDir.right, 'right': IsoDir.right, //
  'lewo': IsoDir.left, 'left': IsoDir.left,
  'gore': IsoDir.up, 'gora': IsoDir.up, 'gory': IsoDir.up, 'up': IsoDir.up,
  'upward': IsoDir.up, 'upwards': IsoDir.up,
  'dol': IsoDir.down, 'dolu': IsoDir.down, 'down': IsoDir.down,
  'downward': IsoDir.down, 'downwards': IsoDir.down,
  'przodu': IsoDir.forward, 'przod': IsoDir.forward,
  'naprzod': IsoDir.forward, 'forward': IsoDir.forward,
  'forwards': IsoDir.forward, 'ahead': IsoDir.forward,
  'tylu': IsoDir.back, 'tyl': IsoDir.back, 'back': IsoDir.back,
  'backward': IsoDir.back, 'backwards': IsoDir.back,
};

IsoCompass? _compassOf(String w) {
  if (w.startsWith('polnoc') || w == 'north' || w == 'northward') {
    return IsoCompass.north;
  }
  if (w.startsWith('poludni') || w == 'south' || w == 'southward') {
    return IsoCompass.south;
  }
  if (w.startsWith('wschod') || w == 'east' || w == 'eastward') {
    return IsoCompass.east;
  }
  if (w.startsWith('zachod') || w == 'west' || w == 'westward') {
    return IsoCompass.west;
  }
  return null;
}

Set<Object> _directionsIn(Iterable<SpokenItem> items) => {
      for (final it in items)
        if (!it.isNumber) ...[
          if (_dirWords[it.word] != null) _dirWords[it.word]!,
          if (_compassOf(it.word) != null) _compassOf(it.word)!,
        ],
    };

/// One unambiguous direction. Different physical/compass directions cannot
/// be resolved without the drawing's north arrow, so leave them unanswered.
(IsoDir?, IsoCompass?) _directionIn(Iterable<SpokenItem> items) {
  final values = _directionsIn(items);
  if (values.length != 1) return (null, null);
  final value = values.single;
  return value is IsoDir ? (value, null) : (null, value as IsoCompass);
}

IsoDir? isoDirectionOf(Utterance u) => _directionIn(u.items).$1;
IsoCompass? isoCompassOf(Utterance u) => _directionIn(u.items).$2;

/// Rodzaj zaworu z wypowiedzi („kulowy”, „zasuwa”, „check”) albo null.
String? isoValveTypeOf(Utterance u) {
  for (final it in u.items) {
    if (it.isNumber) continue;
    final t = _valveTypeOf(it.word);
    if (t != null) return t;
  }
  return null;
}

final RegExp _newSketchRe = RegExp(
    r'\b(?:nowy|nowa|nowe|nowym|nowej|nowego|czysty|czysta|czystym|czystej) '
    r'(?:rysun\w*|szkic\w*|arkusz\w*|izometri\w*|kartk\w*|zeszyt\w*)\b|'
    r'\bod nowa\b|\bzacznij od poczatku\b|'
    r'\bnew (?:drawing|sketch|sheet|iso|isometric)\b|\bstart over\b|'
    r'\bfresh (?:drawing|sketch|sheet)\b');

final RegExp _appendRe = RegExp(r'\bdorysuj\w*|\bdorysowa\w*|'
    r'\bdo (?:tego|ostatniego|starego|poprzedniego|obecnego|istniejacego) '
    r'(?:rysunku|szkicu|arkusza)\b|'
    r'\b(?:do|na) (?:rysunku|rysunek|szkicu|szkic)\b|'
    r'\b(?:to|on|into) (?:the |this |that |my )?(?:drawing|sketch|existing)\b|'
    r'\bexisting (?:drawing|sketch)\b|\bcontinue\b|\bappend\b');

final RegExp _drawVerbRe = RegExp(
    r'\b(?:narysuj\w*|rysuj\w*|dorysuj\w*|naszkicuj\w*|draw|sketch|append)\b');

final RegExp _drawPlaceRe = RegExp(
    r'\b(?:do|na|w) (?:rysunku|rysunek|szkicu|szkic|zeszycie|zeszytu|'
    r'izometrii|izometrie|arkuszu)\b|'
    r'\b(?:to|on|in|into) (?:the |this |my )?(?:drawing|sketch|notebook|iso)\b');

final RegExp _undoAtStartRe =
    RegExp(r'^(?:(?:prosze|hej|ok|okej|asystencie|asystent|please|hey)\s+)*'
        r'(?:cofnij|cofnac|undo)\b');

final RegExp _drawingNounRe =
    RegExp(r'\b(?:rysun\w*|rysowani\w*|szkic\w*|zeszyt\w*|drawing|sketch)\b');

final RegExp _changeVerbRe =
    RegExp(r'\b(?:zmien|popraw|przestaw|obroc|change|make|switch)\b');

final RegExp _questionRe = RegExp(
    r'^(?:(?:a|i|hej|ok|okej|prosze|powiedz|powiedz mi|tell me)\s+)*'
    r'(?:ile|jak\w*|co|czy|ktor\w*|gdzie|kiedy|dlaczego|czemu|po co|'
    r'what\w*|how|which|where|why|when|is|are|does|do you|can you|could)\b');

const Set<String> _questionWords = {
  'ile',
  'jaka',
  'jaki',
  'jakie',
  'jakiej',
  'jakiego',
  'jakim',
  'what',
  'whats',
  'how',
  'which',
};

final RegExp _foreignRe = RegExp(
    r'\b(?:oblicz\w*|policz\w*|przelicz\w*|skroc\w*|skrac\w*|przytn\w*|wylicz\w*|calculate|compute|convert|trim|cut|zapisz|zapamietaj|zanotuj|save|store|remember|record|log|'
    r'dziennik\w*|journal|projekt\w*|project|wps|raport\w*|report|'
    r'tig|mig|mag|mma|welding|welder|cen\w*|koszt\w*|price|cost)\b');

/// Słowa innego modułu — wtedy to nie jest polecenie rysowania.
bool _foreign(Utterance u) {
  if (_foreignRe.hasMatch(u.folded)) return true;
  if (mentionsWeight(u) || mentionsWall(u)) return true;
  if (u.hasStem(const [
    'amper',
    'prad',
    'spaw',
    'elektrod',
    'drut',
    'srednic',
    'diamet',
    'zewnetrz',
  ])) {
    return true;
  }
  // „80 A” — prąd.
  final items = u.items;
  for (var i = 0; i + 1 < items.length; i++) {
    if (items[i].isNumber &&
        !items[i + 1].isNumber &&
        (items[i + 1].word == 'a' || items[i + 1].word == 'v')) {
      return true;
    }
  }
  return false;
}

/// Słowa „neutralne” dla rysowania: spójniki, czasowniki poleceń, miejsca.
const Set<String> _vocabulary = {
  // PL
  'oraz', 'potem', 'nastepnie', 'dalej', 'pozniej', 'teraz', 'jeszcze',
  'prosze', 'hej', 'okej', 'asystent', 'asystencie', 'dobra', 'tak', 'tam',
  'tutaj', 'przez', 'pod', 'kat', 'kata', 'katem', 'dodaj', 'dopisz', 'wstaw',
  'postaw', 'zrob', 'daj', 'cofnij', 'cofnac', 'polecenie', 'element',
  'kierunek', 'kierunku', 'strone', 'strona', 'stronie', 'bok', 'tego', 'tej',
  'ten', 'jedna', 'jeden', 'jedno', 'prosta', 'prosto', 'zmien', 'popraw',
  'przestaw', 'obroc', 'nowy', 'nowa', 'nowe', 'nowym', 'nowej', 'nowego',
  'czysty', 'czysta', 'czystym', 'czystej', 'stary', 'starego', 'obecnego',
  'poprzedniego', 'istniejacego', 'zacznij', 'poczatku', 'idzie',
  'idaca', 'idacy', 'leci', 'biegnie', 'dwie', 'calej',
  // EN
  'and', 'then', 'next', 'now', 'please', 'hey', 'okay', 'the', 'with',
  'from', 'into', 'long', 'length', 'another', 'more', 'one', 'straight',
  'vertical', 'vertically', 'horizontal', 'horizontally', 'last', 'change',
  'make', 'switch', 'add', 'insert', 'put', 'place', 'drawing', 'notebook',
  'sheet', 'iso', 'isometric', 'new', 'start', 'over', 'fresh', 'undo',
  'this', 'that', 'existing', 'same', 'old', 'continue', 'append', 'going',
  'goes',
  'direction', 'way', 'side', 'end', 'field', 'site', 'blind', 'ball', 'gate',
  'check', 'globe', 'butterfly', 'nonreturn', 'return', 'non', 'draw',
  'sketch', 'lay', 'run', 'runs',
};

/// Rdzenie neutralne (odmiany i jednostki).
const List<String> _vocabularyStems = [
  'rysow',
  'rysun',
  'narysow',
  'dorysow',
  'narysuj',
  'rysuj',
  'dorysuj',
  'naszkicuj',
  'szkic',
  'zeszyt',
  'arkusz',
  'izometr',
  'kartk',
  'ostatni',
  'kolejn',
  'nastepn',
  'dlugos',
  'dlug',
  'pionow',
  'poziom',
  'metr',
  'milimet',
  'centymet',
  'stopn',
  'stopie',
  'meter',
  'metre',
  'millimet',
  'centimet',
  'inch',
  'degree',
  'cal',
  'kulow',
  'zwrotn',
  'grzybk',
  'motylk',
  'montazow',
  'zaslepiaj',
  'slep',
  'kolnierzow',
  'polnoc',
  'poludni',
  'wschod',
  'zachod',
  'north',
  'south',
  'east',
  'west',
];

final RegExp _digitsRe = RegExp(r'^[\d.]+$');
final RegExp _pairRe = RegExp(r'^(\d+)x(\d+)$');

bool _known(String w) =>
    w.length < 3 ||
    _digitsRe.hasMatch(w) ||
    _pairRe.hasMatch(w) ||
    _vocabulary.contains(w) ||
    w.startsWith('symbol') ||
    w.startsWith('umiesc') ||
    _dirWords.containsKey(w) ||
    _element(w) != null ||
    _valveTypeOf(w) != null ||
    _vocabularyStems.any(w.startsWith) ||
    isInchUnit(w);

// ═══════════════════════════════════════════════════════════════════════════
// Parser
// ═══════════════════════════════════════════════════════════════════════════

class _Seg {
  _Seg(this.el, this.at);
  final _El el;

  /// Indeks słowa-klucza.
  final int at;

  /// Indeksy elementów wypowiedzi należących do tego elementu (z kluczem).
  final List<int> idx = [];
}

/// Polecenie rysowania z wypowiedzi albo null, gdy to nie jest polecenie
/// rysowania (pytanie, zapis, inny moduł, brak elementów).
IsoCommand? parseIsoCommand(Utterance u) {
  if (referencesInstruction(u)) return null;
  if(RegExp(r'^(?:(?:prosze|please)\s+)*(?:(?:ustaw|zmien)\s+szczeline|(?:set|change)\s+(?:(?:weld|root)\s+)?gap)\b').hasMatch(u.folded)) {
    if(RegExp(r'[-−]\s*\d').hasMatch(u.raw)) return null;
    final match=RegExp(r'^(?:(?:prosze|please)\s+)*(?:(?:ustaw|zmien) szczeline (?:spoiny )?(?:w (?:tym )?(?:rysunku|szkicu|iso)|iso) na|(?:set|change) (?:(?:weld|root) )?gap (?:in|for) (?:the |this )?(?:drawing|sketch|iso) to) (\d+(?:[.,]\d+)?)\s*(mm|cm|m)$').firstMatch(u.folded);
    if(match==null) return null;
    final value=double.tryParse(match[1]!.replaceAll(',', '.'));
    final mm=value==null ? null : value * switch(match[2]) {'m'=>1000,'cm'=>10,_=>1};
    if(mm==null || !isValidSketchGapMm(mm)) return null;
    return IsoCommand(kind:IsoCommandKind.setRootGap,gapMm:mm,explicit:true,strong:true);
  }
  if (RegExp(r'^(?:(?:prosze|please)\s+)*(?:(?:nazwij|name|rename)\s+(?:(?:ten|te|to|this|the)\s+)?(?:rysunek|szkic|drawing|sketch|iso|izometrie)|zmien\s+nazwe\s+(?:rysunku|szkicu)\s+na)\b').hasMatch(u.folded)) {
    final match=RegExp(r'^(?:(?:proszę|prosze|please)\s+)*(?:(?:nazwij|name)\s+(?:(?:ten|tę|te|to|this|the)\s+)?(?:rysunek|szkic|drawing|sketch|iso|izometrię|izometrie)\s+|(?:zmień|zmien)\s+(?:nazwę|nazwe)\s+(?:rysunku|szkicu)\s+na\s+|rename\s+(?:(?:this|the)\s+)?(?:drawing|sketch|iso)\s+(?:to\s+)?)(.+)$',caseSensitive:false).firstMatch(u.raw.trim());
    if(match==null) return null;
    var name=match[1]!.trim();
    for(final (a,b) in [('"','"'),('„','”'),('“','”')]) {
      if(name.startsWith(a) && name.endsWith(b) && name.length>=2) {
        name=name.substring(1,name.length-1).trim();break;
      }
    }
    if(name.isEmpty || name.length>200 || RegExp(r'[\u0000-\u001f\u007f]').hasMatch(name)) return null;
    return IsoCommand(kind:IsoCommandKind.renameSketch,sketchName:name,explicit:true,strong:true);
  }
  if (RegExp(r'^(?:(?:prosze|please)\s+)*(?:(?:zmien|ustaw|popraw)\s+wymiar\s+iso|(?:set|change|correct)\s+(?:the\s+)?iso\s+dimension)\b').hasMatch(u.folded)) {
    if (RegExp(r'[-−]\s*\d').hasMatch(u.raw)) return null;
    final match=RegExp(r'^(?:(?:prosze|please)\s+)*(?:(?:zmien|ustaw|popraw) wymiar iso (?:ostatniej rury|rury numer (?<plIndex>[1-9]\d{0,3})) na|(?:set|change|correct) (?:the )?iso dimension of (?:the )?(?:last pipe|pipe (?:number )?(?<enIndex>[1-9]\d{0,3})) to) (?<value>\d+(?:[.,]\d+)?)\s*(?<unit>mm|cm|m)$').firstMatch(u.folded);
    if (match==null) return null;
    final value=double.tryParse(match.namedGroup('value')!.replaceAll(',', '.'));
    final mm=value==null ? null : value * switch(match.namedGroup('unit')) {'m'=>1000,'cm'=>10,_=>1};
    if (mm==null || !mm.isFinite || mm<=0) return null;
    return IsoCommand(kind:IsoCommandKind.setPipeDimension,dimensionMm:mm,
      pipeOrdinal:int.tryParse(match.namedGroup('plIndex') ?? match.namedGroup('enIndex') ?? ''),
      explicit:true,strong:true);
  }
  final branch = RegExp(
          r'^(?:(?:prosze|please)\s+)*(?:(?:narysuj|dorysuj|poprowadz|draw|add|continue)\s+)?(?:(?:odgalezienie|branch)\s+)?(?:od (?:ostatniego )?trojnika|from (?:the )?(?:last )?tee)\b\s*')
      .firstMatch(u.folded);
  if (branch != null) {
    final remainder = u.folded.substring(branch.end);
    final parsed = parseIsoCommand(u.withRaw('narysuj $remainder'));
    return parsed?.copyWith(
        fromLastTee: true,
        append: true,
        explicitLastTee:
            u.hasStem(const ['ostatni']) || u.hasAny(const ['last']));
  }
  final items = u.items;
  if (items.isEmpty) return null;
  final f = u.folded;
  final explicitValveTypes = {
    for (final it in items)
      if (!it.isNumber &&
          (it.word != 'return' || u.hasAny(const ['non return'])))
        if (_valveTypeOf(it.word) case final type?) type
  };
  final explicitValveAdd = explicitValveTypes.length == 1 &&
      RegExp(r'^(?:(?:prosze|please)\s+)*(?:dodaj|add)\b').hasMatch(f);
  final drawVerb = explicitValveAdd ||
      _drawVerbRe.hasMatch(f) ||
      (u.hasStem(const ['symbol']) &&
          RegExp(r'^(?:(?:prosze|please)\s+)*(?:wstaw|postaw|umiesc|dodaj|place|put|insert|add)\b')
              .hasMatch(f));
  final explicitPlace = _drawPlaceRe.hasMatch(f);

  // ── odrzucenia ──────────────────────────────────────────────────────────
  if (_questionRe.hasMatch(f)) return null;
  if (u.tokens.any(_questionWords.contains)) return null;
  if (!drawVerb && u.raw.trim().endsWith('?')) return null;
  if (_foreign(u)) return null;
  if (!drawVerb &&
      RegExp(r'^(?:otworz|pokaz|uruchom|wlacz|open|show|launch)\b')
          .hasMatch(f)) {
    return null;
  }

  final unknown = [
    for (final it in items)
      if (!it.isNumber && !_known(it.word)) it.word,
  ].length;
  if (unknown >= 3) return null;

  final newSketch = _newSketchRe.hasMatch(f);
  final append = _appendRe.hasMatch(f) && !newSketch;

  // ── cofnij ──────────────────────────────────────────────────────────────
  if (_undoAtStartRe.hasMatch(f)) {
    final object = _drawingNounRe.hasMatch(f) ||
        items.any((it) => !it.isNumber && _element(it.word) != null);
    return IsoCommand(
      kind: IsoCommandKind.undo,
      explicit: object,
      strong: true,
      unknownWords: unknown,
    );
  }

  // ── elementy ────────────────────────────────────────────────────────────
  final segs = <_Seg>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it.isNumber) continue;
    final el = _element(it.word);
    if (el == null) continue;
    // „zawór zasuwa” / „zawór kulowy”: rodzaj należy do zaworu przed nim.
    if (el == _El.valve &&
        segs.isNotEmpty &&
        segs.last.el == _El.valve &&
        _valveTypeOf(it.word) != null &&
        !_segHasValveType(items, segs.last.at, i)) {
      continue;
    }
    // „skręt kolana”, „elbow turn” — jedno kolano, nie dwa.
    if (el == _El.turn &&
        segs.isNotEmpty &&
        segs.last.el == _El.turn &&
        segs.last.at == i - 1) {
      continue;
    }
    segs.add(_Seg(el, i));
  }

  // ── zmień ostatnie kolano ───────────────────────────────────────────────
  final lastWord = u.hasStem(const ['ostatni']) || u.hasAny(const ['last']);
  final changeVerb = _changeVerbRe.hasMatch(f);
  if (segs.isNotEmpty &&
      segs.every((s) => s.el == _El.turn) &&
      (lastWord || changeVerb) &&
      !drawVerb) {
    final (d, c) = _directionIn(items);
    return IsoCommand(
      kind: IsoCommandKind.changeLastTurn,
      turnDir: d,
      turnCompass: c,
      explicit: true,
      strong: true,
      unknownWords: unknown,
    );
  }

  if (segs.isEmpty) {
    if (newSketch) {
      return IsoCommand(
        kind: IsoCommandKind.newSketch,
        newSketch: true,
        explicit: true,
        strong: true,
        unknownWords: unknown,
      );
    }
    return null;
  }

  // Przypisanie słów do elementów: od klucza do następnego klucza; słowa
  // stojące przed kluczem (EN „ball valve”, kąt „45 degree elbow”) idą do
  // swojego elementu.
  final owner = List<int>.filled(items.length, -1);
  for (var k = 0; k < segs.length; k++) {
    final end = k + 1 < segs.length ? segs[k + 1].at : items.length;
    for (var i = segs[k].at; i < end; i++) {
      owner[i] = k;
    }
  }
  for (var k = 0; k < segs.length; k++) {
    final s = segs[k];
    final floor = k == 0 ? 0 : segs[k - 1].at + 1;
    var j = s.at - 1;
    while (j >= floor && j >= s.at - 2) {
      final it = items[j];
      final take = it.isNumber
          ? s.el == _El.turn && _isAngleLeadIn(items, j, s.at)
          : _isLeadIn(it.word, s.el) ||
              (s.el == _El.turn && _isDegreeWord(it.word));
      if (!take) break;
      owner[j] = k;
      j--;
    }
  }
  for (var i = 0; i < items.length; i++) {
    if (owner[i] >= 0) segs[owner[i]].idx.add(i);
  }
  final preamble = [
    for (var i = 0; i < items.length; i++)
      if (owner[i] < 0) items[i],
  ];

  // ── kroki ───────────────────────────────────────────────────────────────
  final steps = <IsoStep>[];
  final compassAt = <int, IsoCompass>{};
  final warnings = <IsoParseWarning>[];
  final symbolOnly = u.hasStem(const ['symbol']) && segs.length == 1;
  int? pipeDn; // DN rury powiedziany przy rurze — dla następnej kształtki
  var strong = segs.length >= 2;

  for (var k = 0; k < segs.length; k++) {
    final s = segs[k];
    final segItems = [for (final i in s.idx) items[i]];
    final directionItems = [...segItems, if (k == 0) ...preamble];
    final (dir, compass) = _directionIn(directionItems);
    if (_directionsIn(directionItems).length > 1) {
      warnings.add(IsoParseWarning(IsoParseWarningKind.directionAmbiguous,
          step: steps.length));
    }
    if (dir != null || compass != null) strong = true;
    final sub = Utterance(_textOf(segItems), lang: u.lang);
    final index = steps.length;
    if (compass != null) compassAt[index] = compass;
    final axialSymbol =
        segs.length == 1 && (symbolOnly || dir != null || compass != null);
    final axial = const {
      _El.flange,
      _El.cap,
      _El.reducer,
      _El.valve,
      _El.weld,
      _El.support
    }.contains(s.el);
    var invalidAxialSize = false;
    final axialSizes = axial
        ? _sizes(segItems, s.idx.indexOf(s.at),
            onInvalid: () => invalidAxialSize = true)
        : <(int, bool)>[];
    final maxSizes = s.el == _El.reducer
        ? 2
        : (s.el == _El.weld || s.el == _El.support)
            ? 0
            : 1;
    if (axial && (invalidAxialSize || axialSizes.length > maxSizes)) {
      warnings.add(
          IsoParseWarning(IsoParseWarningKind.invalidSymbolSize, step: index));
    }
    if (axial && !axialSymbol && (dir != null || compass != null)) {
      warnings.add(IsoParseWarning(
          IsoParseWarningKind.axialDirectionRequiresPipe,
          step: index));
    }

    switch (s.el) {
      case _El.pipe:
        final len = sub.lengthMm();
        final assumed = sub.lengthAssumedMeters;
        final mm = len != null && len > 0 ? len : null;
        if (mm != null) strong = true;
        if (mm != null && assumed) {
          warnings.add(IsoParseWarning(IsoParseWarningKind.lengthAssumedMeters,
              step: index, value: mm));
        }
        final dn = _dnOf(sub);
        if (dn != null) {
          pipeDn = dn;
          strong = true;
        }
        steps.add(IsoPipe(dir: dir, lengthMm: mm));
      case _El.turn:
        // PL commonly puts the modifier after the noun; EN puts it before
        // ("mitred bend", "lobster back elbow"). Prefix words may belong to
        // the preamble or the preceding pipe segment, so inspect both sides.
        final bendWords = [
          ...segItems,
          for (var at = s.at - 3; at < s.at; at++)
            if (at >= 0) items[at],
        ];
        if (bendWords.any((item) =>
            !item.isNumber &&
            const [
              'segmentow',
              'segmented',
              'mitre',
              'miter',
              'lobster',
              'gored'
            ].any(item.word.startsWith))) {
          warnings.add(IsoParseWarning(
              IsoParseWarningKind.unsupportedSegmentedBend,
              step: index));
        }
        final angle = sub.angleDeg();
        final dn = _dnOf(sub) ?? pipeDn;
        pipeDn = null;
        if (symbolOnly && angle == 45) {
          steps.add(IsoFitting('elbow45', dn: dn, symbolOnly: true, dir: dir));
        } else if (angle == 45 && !symbolOnly) {
          steps.add(IsoTurn(toDir: dir, dn: dn, degrees: 45));
        } else if (angle != null && angle != 90) {
          warnings.add(IsoParseWarning(IsoParseWarningKind.unsupported45,
              step: index, value: angle));
          compassAt.remove(index);
          steps.add(IsoFitting('elbow45', dn: dn));
        } else {
          steps.add(IsoTurn(toDir: dir, dn: dn));
        }
      case _El.tee:
        final sizes = _sizes(segItems, s.idx.indexOf(s.at));
        if (!symbolOnly && (dir != null || compass != null)) {
          warnings.add(
              IsoParseWarning(IsoParseWarningKind.unsupportedTee, step: index));
        }
        if (!symbolOnly) compassAt.remove(index);
        if (sizes.length > 2 ||
            (sub.mentionsDn && sizes.isEmpty) ||
            sub.items.any((item) => item.isNumber && item.value! <= 0) ||
            sub.hasAny(const ['minus', 'negative'])) {
          warnings.add(IsoParseWarning(IsoParseWarningKind.invalidSymbolSize,
              step: index));
        }
        final outletOnly = sizes.firstOrNull?.$2 == true;
        steps.add(IsoFitting('tee',
            dn: outletOnly ? pipeDn : sizes.firstOrNull?.$1 ?? pipeDn,
            dnOut: sizes.length == 2
                ? sizes[1].$1
                : outletOnly
                    ? sizes.firstOrNull?.$1
                    : null,
            symbolOnly: symbolOnly,
            dir: symbolOnly ? dir : null));
        pipeDn = null;
      case _El.flange:
      case _El.cap:
        final sizes = axialSizes;
        final blind =
            segItems.any((it) => !it.isNumber && _isBlindWord(it.word));
        final tool = s.el == _El.cap
            ? (segItems.any(
                    (it) => !it.isNumber && it.word.startsWith('kolnierzow'))
                ? 'blindFlange'
                : 'cap')
            : (blind ? 'blindFlange' : 'flange');
        if (!axialSymbol) compassAt.remove(index);
        final dn = sizes.firstOrNull?.$1 ?? pipeDn;
        if (dn != null) strong = true;
        steps.add(IsoFitting(tool,
            dn: dn, symbolOnly: axialSymbol, dir: axialSymbol ? dir : null));
        pipeDn = null;
      case _El.reducer:
        final sizes = axialSizes;
        int? dn, out;
        if (sizes.length >= 2) {
          dn = sizes[0].$1;
          out = sizes[1].$1;
        } else if (sizes.length == 1) {
          // „redukcja na DN80” — wylot; „redukcja DN100” — wlot.
          if (sizes[0].$2) {
            out = sizes[0].$1;
            dn = pipeDn;
          } else {
            dn = sizes[0].$1;
          }
        } else {
          dn = pipeDn;
        }
        if (dn != null || out != null) strong = true;
        if (!axialSymbol) compassAt.remove(index);
        steps.add(IsoFitting('reducer',
            dn: dn,
            dnOut: out,
            symbolOnly: axialSymbol,
            dir: axialSymbol ? dir : null));
        pipeDn = null;
      case _El.valve:
        final sizes = axialSizes;
        String? type;
        for (final it in segItems) {
          if (it.isNumber) continue;
          type = _valveTypeOf(it.word);
          if (type != null) break;
        }
        if (type == null) {
          warnings.add(IsoParseWarning(IsoParseWarningKind.valveTypeMissing,
              step: index));
        }
        if (!axialSymbol) compassAt.remove(index);
        final dn = sizes.firstOrNull?.$1 ?? pipeDn;
        if (dn != null) strong = true;
        steps.add(IsoFitting(type ?? kIsoAnyValve,
            dn: dn, symbolOnly: axialSymbol, dir: axialSymbol ? dir : null));
        pipeDn = null;
      case _El.weld:
        final field =
            segItems.any((it) => !it.isNumber && _isFieldWord(it.word));
        if (!axialSymbol) compassAt.remove(index);
        steps.add(IsoFitting(field ? 'fieldWeld' : 'weld',
            symbolOnly: axialSymbol, dir: axialSymbol ? dir : null));
      case _El.support:
        if (!axialSymbol) compassAt.remove(index);
        steps.add(IsoFitting('support',
            symbolOnly: axialSymbol, dir: axialSymbol ? dir : null));
    }
  }

  if (symbolOnly) {
    final fitting = steps.whereType<IsoFitting>().firstOrNull;
    final invalid = u.items.any((item) => item.isNumber && item.value! <= 0) ||
        u.hasAny(const ['minus', 'negative']) ||
        (u.mentionsDn && fitting?.dn == null);
    if (invalid) {
      warnings
          .add(const IsoParseWarning(IsoParseWarningKind.invalidSymbolSize));
    }
  }
  // Standalone axial symbols retain their explicit orientation. In a routed
  // sequence their orientation follows the pipe; conflicting direction text
  // asks for an actual pipe/turn instead of being silently discarded.
  return IsoCommand(
    kind: IsoCommandKind.draw,
    steps: List.unmodifiable(steps),
    newSketch: newSketch,
    append: append,
    compassAt: Map.unmodifiable(compassAt),
    warnings: List.unmodifiable(warnings),
    explicit: drawVerb || explicitPlace || newSketch,
    strong: strong,
    unknownWords: unknown,
  );
}

bool _segHasValveType(List<SpokenItem> items, int from, int to) {
  for (var i = from; i < to; i++) {
    final it = items[i];
    if (it.isNumber) continue;
    if (i == from &&
        !it.word.startsWith('zasuw') &&
        !it.word.startsWith('przepustnic')) {
      continue;
    }
    if (_valveTypeOf(it.word) != null) return true;
  }
  return false;
}

bool _isDegreeWord(String w) =>
    w.startsWith('stopn') ||
    w.startsWith('stopie') ||
    w == 'deg' ||
    w.startsWith('degree');

/// Liczba tuż przed kolanem („45 elbow”, „45 degree elbow”) to kąt.
bool _isAngleLeadIn(List<SpokenItem> items, int j, int at) {
  final v = items[j].value!;
  if (j == at - 1) return const [11.25, 15, 22.5, 30, 45, 60, 90].contains(v);
  return j == at - 2 &&
      !items[at - 1].isNumber &&
      _isDegreeWord(items[at - 1].word);
}

String _textOf(List<SpokenItem> items) =>
    [for (final it in items) it.text].join(' ');

/// DN z fragmentu: „dn 50”, „de en 50”, „2 cale”.
int? _dnOf(Utterance sub) {
  final dn = sub.dn();
  if (dn != null) return dn;
  final nps = sub.npsInches();
  return nps == null ? null : dnForNps(nps);
}

/// Rozmiary kształtki po kolei: (DN, czy stoi po „na / to / do”). [keyAt] —
/// pozycja słowa-klucza w [items] (numery spoin itp. przed nim się nie
/// liczą). „dn 4 0” (dwuznaczne) nie daje rozmiaru.
List<(int, bool)> _sizes(List<SpokenItem> items, int keyAt,
    {void Function()? onInvalid}) {
  final out = <(int, bool)>[];
  final known = knownDns.toSet();
  var after = false;
  var i = keyAt + 1;
  while (i < items.length) {
    final it = items[i];
    if (!it.isNumber) {
      final w = it.word;
      final pair = _pairRe.firstMatch(w);
      if (pair != null) {
        out
          ..add((int.parse(pair[1]!), false))
          ..add((int.parse(pair[2]!), true));
        i++;
        continue;
      }
      if (w == 'na' || w == 'to' || w == 'into' || w == 'do') after = true;
      final marker = w == 'dn' ||
          ((w == 'de' || w == 'd' || w == 'dee') &&
              i + 1 < items.length &&
              !items[i + 1].isNumber &&
              (items[i + 1].word == 'en' || items[i + 1].word == 'n'));
      if (marker) {
        final j = w == 'dn' ? i + 1 : i + 2;
        if (j < items.length && items[j].isNumber) {
          final v = items[j].value!;
          final ambiguous = j + 1 < items.length &&
              items[j + 1].isNumber &&
              items[j + 1].value! < 10 &&
              v < 100;
          if (!ambiguous && v == v.roundToDouble() && v > 0) {
            out.add((v.toInt(), after));
            after = false;
          } else {
            onInvalid?.call();
          }
          i = ambiguous ? j + 2 : j + 1;
          continue;
        }
        onInvalid?.call();
      }
      i++;
      continue;
    }
    final v = it.value!;
    final next = i + 1 < items.length ? items[i + 1] : null;
    if (next != null && !next.isNumber && isInchUnit(next.word) ||
        it.fraction) {
      final dn = dnForNps(v);
      if (dn != null) {
        out.add((dn, after));
        after = false;
      }
      i += next != null && !next.isNumber && isInchUnit(next.word) ? 2 : 1;
      continue;
    }
    if (v == v.roundToDouble() && known.contains(v.toInt())) {
      out.add((v.toInt(), after));
      after = false;
    }
    i++;
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// Kroki ↔ pola ShowInModule
// ═══════════════════════════════════════════════════════════════════════════

/// Kroki jako lista map (pola `ShowInModule('iso_notebook', {'steps': …})`):
/// `{'kind': 'pipe'|'turn'|'fitting', 'dir', 'length_mm', 'dn', 'dn_out',
/// 'tool', 'degrees', 'symbol_only'}` — bez typów z biblioteki ekranu, do logów i zgłoszeń.
List<Map<String, Object?>> encodeIsoSteps(List<IsoStep> steps) => [
      for (final s in steps)
        switch (s) {
          IsoPipe() => {
              'kind': 'pipe',
              if (s.dir != null) 'dir': s.dir!.name,
              if (s.lengthMm != null) 'length_mm': s.lengthMm,
            },
          IsoTurn() => {
              'kind': 'turn',
              if (s.degrees != 90) 'degrees': s.degrees,
              if (s.toDir != null) 'dir': s.toDir!.name,
              if (s.dn != null) 'dn': s.dn,
            },
          IsoFitting() => {
              'kind': 'fitting',
              'tool': s.tool,
              if (s.symbolOnly) 'symbol_only': true,
              if (s.dir != null) 'dir': s.dir!.name,
              if (s.dn != null) 'dn': s.dn,
              if (s.dnOut != null) 'dn_out': s.dnOut,
            },
        },
    ];

/// Odwrotność [encodeIsoSteps]; przyjmuje też gotowe [IsoStep]. Null albo
/// brak pola = pusta lista. Zły format → [FormatException].
List<IsoStep> decodeIsoSteps(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) throw FormatException('steps: not a list', raw);
  IsoDir? dir(Object? v) {
    if (v == null) return null;
    if (v is IsoDir) return v;
    for (final d in IsoDir.values) {
      if (d.name == v) return d;
    }
    throw FormatException('steps: unknown direction', v);
  }

  int angle(Object? v) {
    if (v == null) return 90;
    if (v != 45 && v != 90) {
      throw FormatException('steps: unsupported bend angle', v);
    }
    return (v as num).toInt();
  }

  int? dn(Object? v) {
    if (v == null) return null;
    if (v is! num ||
        !v.isFinite ||
        v != v.roundToDouble() ||
        !kIsoNotebookDnChoices.contains(v.toInt())) {
      throw FormatException('steps: unsupported or inexact DN', v);
    }
    return v.toInt();
  }

  double? length(Object? v) {
    if (v == null) return null;
    if (v is! num || !v.isFinite || v <= 0) {
      throw FormatException('steps: length must be finite and positive', v);
    }
    return v.toDouble();
  }

  const fittingTools = {
    'elbow45',
    'tee',
    'olet',
    'flange',
    'blindFlange',
    'cap',
    'reducer',
    'gateValve',
    'ballValve',
    'checkValve',
    'globeValve',
    'butterflyValve',
    'weld',
    'fieldWeld',
    'support'
  };
  final result = <IsoStep>[];
  for (final item in raw) {
    final e = item is IsoStep ? encodeIsoSteps([item]).single : item;
    if (e is! Map) throw FormatException('steps: not a step', e);
    final allowed = switch (e['kind']) {
      'pipe' => const {'kind', 'dir', 'length_mm'},
      'turn' => const {'kind', 'dir', 'dn', 'degrees'},
      'fitting' => const {'kind', 'tool', 'dn', 'dn_out', 'dir', 'symbol_only'},
      _ => throw FormatException('steps: unknown kind', e['kind']),
    };
    if (e.keys.any((k) => !allowed.contains(k))) {
      throw FormatException('steps: unknown field', e);
    }
    switch (e['kind']) {
      case 'pipe':
        result
            .add(IsoPipe(dir: dir(e['dir']), lengthMm: length(e['length_mm'])));
      case 'turn':
        result.add(IsoTurn(
            toDir: dir(e['dir']),
            dn: dn(e['dn']),
            degrees: angle(e['degrees'])));
      case 'fitting':
        final tool = e['tool'], symbol = e['symbol_only'];
        if (tool is! String || !fittingTools.contains(tool)) {
          throw FormatException('steps: unsupported fitting', tool);
        }
        if (symbol != null && symbol is! bool) {
          throw FormatException('steps: symbol_only must be boolean', symbol);
        }
        final direction = dir(e['dir']);
        if (direction != null && symbol != true) {
          throw FormatException(
              'steps: fitting direction requires symbol_only', e);
        }
        final size = dn(e['dn']), out = dn(e['dn_out']);
        if (out != null && tool != 'tee' && tool != 'reducer') {
          throw FormatException(
              'steps: outlet DN is not supported by this fitting', e);
        }
        if (tool == 'tee' && out != null && (size == null || out > size)) {
          throw FormatException('steps: branch DN exceeds run DN', e);
        }
        result.add(IsoFitting(tool,
            dn: size, dnOut: out, symbolOnly: symbol == true, dir: direction));
    }
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Słowa dla montera (opis i wypowiedź zwrotna)
// ═══════════════════════════════════════════════════════════════════════════

String isoDirPl(IsoDir d) => switch (d) {
      IsoDir.right => 'w prawo',
      IsoDir.up => 'w górę',
      IsoDir.back => 'do tyłu',
      IsoDir.left => 'w lewo',
      IsoDir.down => 'w dół',
      IsoDir.forward => 'do przodu',
    };

String isoDirEn(IsoDir d) => switch (d) {
      IsoDir.right => 'right',
      IsoDir.up => 'up',
      IsoDir.back => 'back',
      IsoDir.left => 'left',
      IsoDir.down => 'down',
      IsoDir.forward => 'forward',
    };

String isoDir(IsoDir d, AppLanguage l) =>
    l == AppLanguage.en ? isoDirEn(d) : isoDirPl(d);

String isoCompassName(IsoCompass c, AppLanguage l) =>
    switch ((c, l == AppLanguage.en)) {
      (IsoCompass.north, false) => 'na północ',
      (IsoCompass.south, false) => 'na południe',
      (IsoCompass.east, false) => 'na wschód',
      (IsoCompass.west, false) => 'na zachód',
      (IsoCompass.north, true) => 'north',
      (IsoCompass.south, true) => 'south',
      (IsoCompass.east, true) => 'east',
      (IsoCompass.west, true) => 'west',
    };

/// Nazwa kształtki ([IsoFitting.tool]) dla montera.
String isoFittingName(String tool, AppLanguage l) {
  final en = l == AppLanguage.en;
  return switch (tool) {
    'flange' => en ? 'flange' : 'kołnierz',
    'blindFlange' => en ? 'blind flange' : 'kołnierz zaślepiający',
    'cap' => en ? 'cap' : 'zaślepka',
    'reducer' => en ? 'reducer' : 'redukcja',
    'gateValve' => en ? 'gate valve' : 'zasuwa',
    'ballValve' => en ? 'ball valve' : 'zawór kulowy',
    'checkValve' => en ? 'check valve' : 'zawór zwrotny',
    'globeValve' => en ? 'globe valve' : 'zawór grzybkowy',
    'butterflyValve' => en ? 'butterfly valve' : 'przepustnica',
    'weld' => en ? 'weld' : 'spoina',
    'fieldWeld' => en ? 'field weld' : 'spoina montażowa',
    'support' => en ? 'support' : 'podpora',
    'elbow45' => en ? '45° elbow' : 'kolano 45°',
    'tee' => en ? 'tee' : 'trójnik',
    kIsoAnyValve => en ? 'valve' : 'zawór',
    _ => tool,
  };
}

String _num(double v, AppLanguage l) {
  final r = v.roundToDouble();
  final s = (v - r).abs() < 1e-9
      ? r.toStringAsFixed(0)
      : v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return l == AppLanguage.en ? s : s.replaceAll('.', ',');
}

/// „2 m” / „1500 mm” (karta) albo „2 metry” / „1500 milimetrów” (mowa).
String isoLength(double mm, AppLanguage l, {bool spoken = false}) {
  final en = l == AppLanguage.en;
  final metres = mm % 1000 == 0;
  if (!spoken) return metres ? '${_num(mm / 1000, l)} m' : '${_num(mm, l)} mm';
  if (metres) {
    final m = (mm / 1000).round();
    if (en) return '$m ${m == 1 ? 'metre' : 'metres'}';
    return '$m ${_plForm(m, 'metr', 'metry', 'metrów')}';
  }
  if (en) return '${_num(mm, l)} millimetres';
  final n = mm.roundToDouble() == mm ? mm.toInt() : null;
  return '${_num(mm, l)} '
      '${n == null ? 'milimetra' : _plForm(n, 'milimetr', 'milimetry', 'milimetrów')}';
}

String _plForm(int n, String one, String few, String many) {
  if (n == 1) return one;
  final d = n % 10, t = n % 100;
  return d >= 2 && d <= 4 && (t < 12 || t > 14) ? few : many;
}

/// Jeden krok słowami: „rura 2 m w prawo”, „kolano DN50 w górę”,
/// „redukcja DN100 → DN80”.
String describeIsoStep(IsoStep s, AppLanguage l, {bool spoken = false}) {
  final en = l == AppLanguage.en;
  return switch (s) {
    IsoPipe() => [
        en ? 'pipe' : 'rura',
        if (s.lengthMm != null) isoLength(s.lengthMm!, l, spoken: spoken),
        if (s.dir != null) isoDir(s.dir!, l),
      ].join(' '),
    IsoTurn() => [
        en ? 'elbow' : 'kolano',
        if (s.degrees != 90)
          spoken
              ? '${s.degrees} ${en ? 'degrees' : 'stopni'}'
              : '${s.degrees}°',
        if (s.dn != null) 'DN${s.dn}',
        if (s.toDir != null) isoDir(s.toDir!, l),
      ].join(' '),
    IsoFitting() => [
        if (s.symbolOnly) en ? 'symbol of' : 'symbol',
        isoFittingName(s.tool, l),
        if ((s.tool == 'reducer' || s.tool == 'tee') &&
            s.dn != null &&
            s.dnOut != null)
          'DN${s.dn} → DN${s.dnOut}'
        else if (s.tool == 'reducer' && s.dnOut != null)
          '→ DN${s.dnOut}'
        else if (s.dn != null)
          'DN${s.dn}',
        if (s.symbolOnly && s.dir != null) isoDir(s.dir!, l),
      ].join(' '),
  };
}

/// Kroki słowami, po przecinku.
String describeIsoSteps(List<IsoStep> steps, AppLanguage l,
        {bool spoken = false}) =>
    [for (final s in steps) describeIsoStep(s, l, spoken: spoken)].join(', ');

/// Kroki z powrotem jako wypowiedź, którą [parseIsoCommand] czyta tak samo
/// (chipy „popraw…”): „narysuj rura 2000 mm w prawo kolano w górę rura”.
String isoStepsToUtterance(List<IsoStep> steps, AppLanguage l,
    {bool newSketch = false}) {
  final en = l == AppLanguage.en;
  String mm(double v) => '${_num(v, AppLanguage.en)} mm';
  final words = <String>[
    if (en) 'draw' else 'narysuj',
    if (newSketch) en ? 'on a new drawing' : 'na nowym rysunku',
  ];
  for (final s in steps) {
    switch (s) {
      case IsoPipe():
        words.add(en ? 'pipe' : 'rura');
        if (s.lengthMm != null) words.add(mm(s.lengthMm!));
        if (s.dir != null) words.add(isoDir(s.dir!, l));
      case IsoTurn():
        words.add(en ? 'elbow' : 'kolano');
        if (s.degrees != 90) {
          words.add('${s.degrees} ${en ? 'degrees' : 'stopni'}');
        }
        if (s.dn != null) words.add('dn ${s.dn}');
        if (s.toDir != null) words.add(isoDir(s.toDir!, l));
      case IsoFitting():
        if (s.symbolOnly) words.add('symbol');
        words.add(isoFittingName(s.tool, l));
        if (s.tool == 'reducer' || s.tool == 'tee') {
          if (s.dn != null) words.add('dn ${s.dn}');
          if (s.dnOut != null) words.add('${en ? 'to' : 'na'} dn ${s.dnOut}');
        } else if (s.dn != null) {
          words.add('dn ${s.dn}');
        }
        if (s.symbolOnly && s.dir != null) words.add(isoDir(s.dir!, l));
    }
  }
  return words.join(' ');
}
