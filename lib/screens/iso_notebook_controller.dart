part of 'iso_notebook_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STEROWANIE ZESZYTEM Z ZEWNĄTRZ — dla asystenta głosowego (spec §4.5).
//
// „Narysuj rura kolanko rura” → [IsoPipe(), IsoTurn(), IsoPipe()] →
// [IsoNotebookController.draw]. Model szkicu jest prywatny, więc kontroler
// jest częścią tej biblioteki; na zewnątrz wystają tylko prymitywy poniżej.
//
// Zasady:
//  * całe polecenie to JEDEN krok „Cofnij” (jedno `_undo.add`);
//  * polecenie jest najpierw planowane w całości. Problem (zawrócenie, skręt
//    na końcu, 45°, trójnik, wyjście nad górę siatki…) zatrzymuje je PRZED
//    rysowaniem — nic nie trafia ani do szkicu, ani do bazy;
//  * kolano powstaje samo na styku dwóch rur (`_maybeInsertElbows`), a
//    „kolano” w poleceniu to zamiar skrętu NASTĘPNEJ rury;
//  * animacja to osobny podgląd (`_ghost`, własna warstwa), niezależny od gestu
//    palca (`_dragA/_dragB`). Gest w trakcie animacji kończy polecenie od
//    razu, bez animacji — przerywa animację, nie zapis;
//  * polecenia idą przez kolejkę, jedno po drugim.
// ═══════════════════════════════════════════════════════════════════════════

/// Kierunek rury w słowach montera.
///
/// Indeks = kierunek siatki ([_isoHeadings]) w domyślnym odwzorowaniu osi:
/// 0 w prawo, 1 w górę (oś III = pion), 2 do tyłu, 3 w lewo, 4 w dół,
/// 5 do przodu. „W górę” rysuje w górę ekranu po osi, którą legenda osi
/// podpisuje „pion”; „do przodu” — w dół ekranu po drugiej osi poziomej.
///
/// Wyjątek: strzałka północy położona na osi III zamienia role osi — legenda
/// pokazuje wtedy „góra/dół” przy osi II. Kontroler idzie za legendą: w górę
/// = oś II w górę ekranu, do przodu/do tyłu = oś III. Prawo/lewo to zawsze
/// oś I (pozioma na ekranie).
enum IsoDir { right, up, back, left, down, forward }

/// Strona świata — działa tylko przy strzałce północy na rysunku
/// ([IsoNotebookController.dirForCompass]).
enum IsoCompass { north, south, east, west }

/// Jeden krok polecenia rysowania.
sealed class IsoStep {
  const IsoStep();
}

/// Rura od kursora. Bez [dir]: pierwsza w prawo, kolejna dalej prosto, po
/// [IsoTurn] — skręt domyślny. Bez [lengthMm]: 3 kroki siatki i bez wymiaru.
class IsoPipe extends IsoStep {
  const IsoPipe({this.dir, this.lengthMm});
  final IsoDir? dir;
  final double? lengthMm;

  @override
  bool operator ==(Object other) =>
      other is IsoPipe && other.dir == dir && other.lengthMm == lengthMm;

  @override
  int get hashCode => Object.hash(IsoPipe, dir, lengthMm);

  @override
  String toString() => 'IsoPipe(${[
        if (dir != null) 'dir: ${dir!.name}',
        if (lengthMm != null) 'lengthMm: $lengthMm',
      ].join(', ')})';
}

/// Zamiar skrętu dla NASTĘPNEJ rury. [degrees] to fizyczny kąt 45/90°.
/// Dla 45° [toDir] wskazuje stronę/płaszczyznę skrętu, a nie oś końcowej rury.
/// [dn] trafia do kolana (CTE z [isoStandardElbowCteMm] albo z pamięci
/// rysunku) i do pamięci ostatniego DN.
class IsoTurn extends IsoStep {
  const IsoTurn({this.toDir, this.dn, this.degrees = 90});
  final IsoDir? toDir;
  final int degrees;
  final int? dn;

  @override
  bool operator ==(Object other) =>
      other is IsoTurn &&
      other.toDir == toDir &&
      other.dn == dn &&
      other.degrees == degrees;

  @override
  int get hashCode => Object.hash(IsoTurn, toDir, dn, degrees);

  @override
  String toString() => 'IsoTurn(${[
        if (degrees != 90) 'degrees: $degrees',
        if (toDir != null) 'toDir: ${toDir!.name}',
        if (dn != null) 'dn: $dn',
      ].join(', ')})';
}

/// Kształtka osiowa stawiana na kursorze, ze specyfikacją z tablic (bez
/// okien dialogowych). [tool]: `flange`, `blindFlange`, `cap`, `reducer`,
/// `gateValve`, `ballValve`, `checkValve`, `globeValve`, `butterflyValve`,
/// `weld`, `fieldWeld`, `support`. `elbow45` → [IsoDrawProblem.unsupported45],
/// `tee` supports a straight run; `olet` → [IsoDrawProblem.unsupportedTee]. Explicit standalone
/// `symbolOnly` allows elbow45 and tee placement; it does not infer routing.
/// Inna nazwa to błąd
/// programisty ([ArgumentError]).
class IsoFitting extends IsoStep {
  const IsoFitting(this.tool,
      {this.dn, this.dnOut, this.symbolOnly = false, this.dir});
  final String tool;

  /// Explicit manual-style symbol placement, with no inferred sloping route.
  final bool symbolOnly;

  /// Orientation for explicit symbol placement.
  final IsoDir? dir;
  final int? dn;

  /// Reducer outlet or tee branch DN.
  final int? dnOut;

  @override
  bool operator ==(Object other) =>
      other is IsoFitting &&
      other.tool == tool &&
      other.dn == dn &&
      other.dnOut == dnOut &&
      other.symbolOnly == symbolOnly &&
      other.dir == dir;

  @override
  int get hashCode => Object.hash(IsoFitting, tool, dn, dnOut, symbolOnly, dir);

  @override
  String toString() => "IsoFitting('$tool'${[
        if (dn != null) ', dn: $dn',
        if (dnOut != null) ', dnOut: $dnOut',
        if (symbolOnly) ', symbolOnly: true',
        if (dir != null) ', dir: ${dir!.name}',
      ].join()})";
}

/// Dlaczego polecenie NIE zostało narysowane (nic nie zapisano).
enum IsoDrawProblem {
  /// Rura w kierunku przeciwnym do poprzedniej (zawrócenie).
  reversal,

  /// Po kolanie rura idzie dalej tym samym kierunkiem — to nie jest skręt.
  sameDirectionAfterTurn,

  /// Kolano bez rury za nim (na końcu polecenia albo tuż przed kształtką):
  /// „powiedz, dokąd idzie rura po kolanie”.
  trailingTurn,

  /// Kolano 45° — poza zakresem tej wersji, do narysowania palcem.
  unsupported45,

  /// A fitting on an oblique spatial ray needs a spatial orientation contract.
  spatialFitting,

  /// A spatial bend requires an explicit, geometrically valid target plane.
  invalidSpatialTurn,

  /// Unsupported branch grammar / olet; a tee run and explicit branch are supported.
  unsupportedTee,

  /// Invalid explicit run/branch sizes for a requested symbol.
  invalidFittingSize,

  /// Another non-weld component already occupies the symbol location.
  occupiedSymbol,

  /// No suitable tee/run or a branch is already present.
  invalidBranch,

  /// Rysunek wyszedłby nad górną krawędź siatki (wiersze < 0).
  outOfCanvas,

  /// Zmiana kierunku w punkcie, w którym stoi już kształtka (zawór, kołnierz,
  /// redukcja…): kolano nie ma gdzie stanąć. Potrzebna rura między nimi.
  /// Także: na wolnym końcu rysunku stoi już kolano — każda rura (i każda
  /// kształtka poza spoiną) z tego punktu; [IsoDrawReport.problemPl] mówi
  /// wtedy „na końcu stoi już kolano”.
  turnAtFitting,
}

/// Wynik [IsoNotebookController.draw].
@immutable
class IsoDrawReport {
  const IsoDrawReport({
    this.assumedPl = const [],
    this.assumedEn = const [],
    this.problem,
    this.problemStep,
    this.problemPl,
    this.problemEn,
    this.segments = 0,
    this.elbows = 0,
    this.fittings = 0,
  });

  /// Co kontroler przyjął sam (kierunek, skręt domyślny, DN, brak długości).
  /// Listy równoległe: PL i EN. Puste, gdy wystąpił [problem].
  final List<String> assumedPl, assumedEn;

  /// Null = narysowano. Inaczej nic nie zostało dodane ani zapisane.
  final IsoDrawProblem? problem;

  /// Indeks w liście kroków, którego dotyczy [problem] (przy problemach ze
  /// skrętem — indeks [IsoTurn]).
  final int? problemStep;

  /// [problem] jednym zdaniem dla montera (co zrobić dalej), PL i EN.
  final String? problemPl, problemEn;

  /// Ile dodano rur, kolan (wstawionych automatycznie) i kształtek.
  final int segments, elbows, fittings;

  bool get ok => problem == null;

  @override
  String toString() => problem != null
      ? 'IsoDrawReport(problem: ${problem!.name} @ $problemStep)'
      : 'IsoDrawReport(segments: $segments, elbows: $elbows, '
          'fittings: $fittings, assumed: $assumedPl)';
}

/// Sterowanie zamontowanym Zeszytem ISO. Jedna instancja na ekran; znajdziesz
/// ją przez [IsoNotebookController.active] (null, gdy zeszyt nie jest
/// otwarty) albo [activeListenable].
class IsoNotebookController extends ChangeNotifier {
  IsoNotebookController._(this._state);

  _IsoState? _state;

  // ── rejestr ────────────────────────────────────────────────────────────────

  static IsoNotebookController? _current;
  static final ValueNotifier<IsoNotebookController?> _activeNotifier =
      ValueNotifier<IsoNotebookController?>(null);

  /// Kontroler zamontowanego ekranu zeszytu albo null.
  static IsoNotebookController? get active => _current;

  /// To samo co [active], jako sygnał (np. „czekaj, aż zeszyt się otworzy”).
  /// Zmiana dochodzi w mikrozadaniu, nigdy w trakcie budowania drzewa.
  static ValueListenable<IsoNotebookController?> get activeListenable =>
      _activeNotifier;

  static void _publish() =>
      scheduleMicrotask(() => _activeNotifier.value = _current);

  void _attach() {
    _current = this;
    _publish();
  }

  /// Ekran znika: polecenie w toku kończy się od razu (dispose zapisze je
  /// razem z resztą), kolejne w kolejce dostaną [StateError].
  void _detach() {
    _finishNow();
    _state = null;
    if (identical(_current, this)) {
      _current = null;
      _publish();
    }
    for (final c in [_prefsLoaded, _sketchLoaded, _laidOut]) {
      if (!c.isCompleted) c.complete();
    }
  }

  // ── gotowość ───────────────────────────────────────────────────────────────

  final Completer<void> _prefsLoaded = Completer<void>();
  final Completer<void> _sketchLoaded = Completer<void>();
  final Completer<void> _laidOut = Completer<void>();
  late final Future<void> _ready = Future.wait<void>([
    _prefsLoaded.future,
    _sketchLoaded.future,
    _laidOut.future,
  ]).then((_) {});

  /// Ustawienia wczytane, ostatni szkic na ekranie, płótno ma rozmiar.
  /// [draw], [startNew] i [undo] z kolejki same na to czekają.
  Future<void> get ready => _ready;

  void _markPrefsLoaded() {
    if (!_prefsLoaded.isCompleted) _prefsLoaded.complete();
  }

  void _markSketchLoaded() {
    if (!_sketchLoaded.isCompleted) _sketchLoaded.complete();
  }

  void _awaitFirstLayout() {
    final s = _state;
    if (s == null || _laidOut.isCompleted) return;
    final size = s._canvasSize;
    if (size != null && !size.isEmpty) {
      _laidOut.complete();
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _awaitFirstLayout())
      ..scheduleFrame();
  }

  // ── stan ───────────────────────────────────────────────────────────────────

  /// Czy na arkuszu cokolwiek jest.
  bool get hasContent => _state?._items.isNotEmpty ?? false;

  /// Nazwa rysunku albo null (bez nazwy).
  String? get sketchName {
    final n = _state?._projectName ?? '';
    return n.isEmpty ? null : n;
  }

  /// Ostatnia zmiana rysunku na ekranie (z bazy przy otwarciu), null dla
  /// nowego, nietkniętego arkusza.
  DateTime? get lastEdited => _state?._lastEditedAt;

  /// Polecenie w toku albo w kolejce.
  bool get isBusy => _queued > 0;

  /// Kierunek montera dla strony świata — tylko gdy na rysunku jest strzałka
  /// północy (inaczej null). Odwzorowanie jak etykiety N/S/E/W na liniach.
  IsoDir? dirForCompass(IsoCompass c) {
    final s = _state;
    final m = s?._currentMapping;
    if (s == null || m == null) return null;
    final north = s._closestIsoHeading(m.northVec);
    final east = s._closestIsoHeading(m.eastVec);
    final grid = switch (c) {
      IsoCompass.north => north,
      IsoCompass.south => (north + 3) % 6,
      IsoCompass.east => east,
      IsoCompass.west => (east + 3) % 6,
    };
    return _semanticOf(grid, m);
  }

  void _changed() {
    if (_state == null) return;
    notifyListeners();
  }

  // ── kolejka ────────────────────────────────────────────────────────────────

  Future<void> _tail = Future<void>.value();
  int _queued = 0;
  _VoiceRun? _run;

  Future<T> _enqueue<T>(Future<T> Function(_IsoState s) op) {
    _queued++;
    final result = _tail.then((_) async {
      try {
        await ready;
        final s = _state;
        if (s == null) {
          throw StateError('IsoNotebookScreen is no longer mounted');
        }
        return await op(s);
      } finally {
        _queued--;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  // ── API ────────────────────────────────────────────────────────────────────

  /// Zapisuje bieżący szkic i otwiera pusty arkusz (bez wpisu w bazie —
  /// wpis powstaje przy pierwszym elemencie). Pusty, zapisany wcześniej
  /// arkusz zostaje usunięty. [StateError], gdy zapis się nie udał (wtedy
  /// nic się nie zmienia).
  Future<void> startNew() => _enqueue(_startNew);

  Future<void> _startNew(_IsoState s) async {
    if (!await s._flushSave()) {
      throw StateError('Could not save the current sketch');
    }
    if (_state == null) {
      throw StateError('IsoNotebookScreen is no longer mounted');
    }
    await s._dropCurrentIfBlank();
    if (_state == null) {
      throw StateError('IsoNotebookScreen is no longer mounted');
    }
    s._startBlankSketch(persist: false);
  }

  /// Synchronous preview with the same empty geometry and per-sheet settings
  /// as startNew. The active drawing, undo history and persistence stay intact.
  _VoicePlan _planOnBlank(_IsoState s, List<IsoStep> steps) {
    final items = List<_Item>.from(s._items);
    final dimensions = Map.of(s._compDimCache);
    final sizes = Map.of(s._lastDnByTool);
    final gap = s._gapMm;
    try {
      s._items.clear();
      s._compDimCache.clear();
      s._lastDnByTool.clear();
      s._gapMm = 0;
      return _plan(s, steps);
    } finally {
      s._items
        ..clear()
        ..addAll(items);
      s._compDimCache
        ..clear()
        ..addAll(dimensions);
      s._lastDnByTool
        ..clear()
        ..addAll(sizes);
      s._gapMm = gap;
    }
  }

  /// Wykonuje sekwencję jako JEDEN krok Cofnij; zatrzymuje się na pierwszym
  /// problemie (bez częściowego zapisu). Każda rura rośnie w podglądzie w 4
  /// krokach co [stepDelay] (zero = bez animacji), potem trafia do szkicu.
  /// Na koniec widok dopasowuje się tak, żeby cały rysunek był widoczny.
  List<IsoStep>? _lastVoiceSteps;
  int? _lastVoiceVersion;
  bool _lastVoiceFromTee = false;
  bool _lastVoiceExplicitTee = false;
  bool get lastCorrectionChangesBranchOrigin =>
      _lastVoiceFromTee &&
      !(_lastVoiceSteps?.any((step) => step is IsoTurn) ?? false);

  /// With [newSketch], validate against a blank sheet before saving or
  /// switching the active drawing. Invalid sequences leave the old sheet intact.
  Future<IsoDrawReport> draw(List<IsoStep> steps,
      {Duration stepDelay = const Duration(milliseconds: 300),
      bool newSketch = false,
      bool fromLastTee = false,
      bool explicitLastTee = false}) {
    final copy = List<IsoStep>.unmodifiable(steps);
    return _enqueue((s) async {
      if (newSketch && fromLastTee) {
        final (pl, en) = _problemText(IsoDrawProblem.invalidBranch);
        return IsoDrawReport(
            problem: IsoDrawProblem.invalidBranch,
            problemPl: pl,
            problemEn: en);
      }
      if (newSketch) {
        final preview = _planOnBlank(s, copy);
        if (preview.problem case final problem?) {
          final (pl, en) = _problemText(problem, elbow: preview.elbowAtCursor);
          return IsoDrawReport(
              problem: problem,
              problemStep: preview.problemStep,
              problemPl: pl,
              problemEn: en);
        }
        if (preview.ops.isEmpty) {
          return IsoDrawReport(
              assumedPl: preview.assumedPl, assumedEn: preview.assumedEn);
        }
        await _startNew(s);
      }
      final report = await _draw(s, copy, stepDelay,
          fromLastTee: fromLastTee, explicitLastTee: explicitLastTee);
      if (report.ok) {
        _lastVoiceFromTee = fromLastTee;
        _lastVoiceExplicitTee = explicitLastTee;
        _lastVoiceSteps = copy;
        _lastVoiceVersion = s._version;
      }
      return report;
    });
  }

  /// Correct the latest voice turn only if no manual edit intervened.
  /// The complete replacement is validated before touching the drawing.
  Future<IsoDrawReport?> redirectLastTurn(IsoDir direction) =>
      _enqueue((s) async {
        final last = _lastVoiceSteps;
        if (last == null ||
            s._version != _lastVoiceVersion ||
            s._undo.isEmpty) {
          return null;
        }
        final index = last.lastIndexWhere((step) => step is IsoTurn);
        if (index < 0 && !_lastVoiceFromTee) return null;
        final steps = List<IsoStep>.from(last);
        if (index < 0 && steps.first is IsoPipe) {
          final pipe = steps.first as IsoPipe;
          steps[0] = IsoPipe(dir: direction, lengthMm: pipe.lengthMm);
        } else {
          final turn = steps[index] as IsoTurn;
          steps[index] =
              IsoTurn(toDir: direction, dn: turn.dn, degrees: turn.degrees);
          for (var i = index + 1; i < steps.length; i++) {
            if (steps[i] case final IsoPipe pipe) {
              steps[i] = IsoPipe(dir: direction, lengthMm: pipe.lengthMm);
              break;
            }
          }
        }
        final current = List<_Item>.from(s._items);
        final before = List<_Item>.from(s._undo.last);
        late final _VoicePlan preview;
        try {
          s._items
            ..clear()
            ..addAll(before);
          preview = _plan(s, steps,
              fromLastTee: _lastVoiceFromTee,
              explicitLastTee: _lastVoiceExplicitTee);
        } finally {
          s._items
            ..clear()
            ..addAll(current);
        }
        if (preview.problem case final problem?) {
          final (pl, en) = _problemText(problem, elbow: preview.elbowAtCursor);
          return IsoDrawReport(
              problem: problem,
              problemStep: preview.problemStep,
              problemPl: pl,
              problemEn: en);
        }
        s._undo.removeLast();
        s._mutate(() => s._items
          ..clear()
          ..addAll(before));
        final report = await _draw(s, steps, const Duration(milliseconds: 150),
            fromLastTee: _lastVoiceFromTee,
            explicitLastTee: _lastVoiceExplicitTee);
        if (report.ok) {
          _lastVoiceSteps = List.unmodifiable(steps);
          _lastVoiceVersion = s._version;
        }
        return report;
      });

  /// Cofa ostatni krok (całe polecenie [draw] naraz). Gdy w kolejce czekają
  /// polecenia, cofnięcie ustawia się za nimi.
  void undo() {
    final s = _state;
    if (s == null) return;
    if (_queued == 0) {
      s._undoAction();
      return;
    }
    unawaited(_enqueue((st) async => st._undoAction())
        .then<void>((_) {}, onError: (Object _) {}));
  }

  // ── testy ──────────────────────────────────────────────────────────────────

  /// Podgląd animacji (rosnąca rura) albo null.
  @visibleForTesting
  ({Offset a, Offset b})? get debugGhost {
    final g = _state?._ghost.value;
    return g == null ? null : (a: g.$1, b: g.$2);
  }

  /// Ile razy ekran zeszytu wykonał `build` (podgląd nie może go wołać).
  @visibleForTesting
  int get debugScreenBuilds => _state?._debugBuilds ?? 0;

  /// Ile razy warstwa podglądu się narysowała (wszystkie ekrany).
  @visibleForTesting
  static int get debugGhostPaints => _GhostPainter.debugPaints;

  /// Widoczny fragment płótna we współrzędnych rysunku.
  @visibleForTesting
  Rect? get debugVisibleWorld => _state?._visibleWorld;

  /// Etykieta osi na każdej rurze — dokładnie to, co rysuje płótno (I/II/III,
  /// a przy strzałce N: N/S/E/W/↑/↓).
  @visibleForTesting
  List<String> get debugPipeAxisTags {
    final s = _state;
    if (s == null) return const [];
    final m = s._currentMapping;
    return [
      for (final it in s._items)
        if (it is _Seg && it.t == _Tool.pipe) _pipeAxisTagText(it, m),
    ];
  }

  // ── rysowanie ──────────────────────────────────────────────────────────────

  Future<IsoDrawReport> _draw(_IsoState s, List<IsoStep> steps, Duration delay,
      {bool fromLastTee = false, bool explicitLastTee = false}) async {
    final plan = _plan(s, steps,
        fromLastTee: fromLastTee, explicitLastTee: explicitLastTee);
    final problem = plan.problem;
    if (problem != null) {
      final (pl, en) = _problemText(problem, elbow: plan.elbowAtCursor);
      return IsoDrawReport(
        problem: problem,
        problemStep: plan.problemStep,
        problemPl: pl,
        problemEn: en,
      );
    }
    if (plan.ops.isEmpty) {
      return IsoDrawReport(
          assumedPl: plan.assumedPl, assumedEn: plan.assumedEn);
    }
    for (final op in plan.ops.whereType<_PlannedFitting>()) {
      if (op.tool != _Tool.elbow45 && op.tool != _Tool.tee) continue;
      if (plan.ops.whereType<_PlannedFitting>().any((other) =>
          !identical(other, op) && !other.tool.isWeld && other.at == op.at)) {
        final (pl, en) = _problemText(IsoDrawProblem.occupiedSymbol);
        return IsoDrawReport(
            problem: IsoDrawProblem.occupiedSymbol,
            problemStep: op.step,
            problemPl: pl,
            problemEn: en);
      }
      final at = plan.world(op.at);
      if (s._items.any((item) =>
          item is _Comp &&
          !item.t.isWeld &&
          (item.pos - at).distance < _IsoState._s * .45)) {
        final (pl, en) = _problemText(IsoDrawProblem.occupiedSymbol);
        return IsoDrawReport(
            problem: IsoDrawProblem.occupiedSymbol,
            problemStep: op.step,
            problemPl: pl,
            problemEn: en);
      }
    }
    final run = _VoiceRun(plan);
    // The whole command is ONE undo step — taken here, not through _push(),
    // which would finish this very run.
    s._undo.add(List<_Item>.from(s._items));
    _run = run;
    // Fit before drawing, so the fitter watches the route grow.
    s._showWorldRect(plan.boundsWith(s._drawingBounds()),
        fallback: plan.bounds);
    try {
      final animate = delay > Duration.zero;
      while (!run.done && !run.interrupted) {
        final op = plan.ops[run.next];
        if (animate && op is _PlannedPipe) {
          final a = plan.world(op.from), b = plan.world(op.to);
          for (var q = 1; q <= 4 && !run.interrupted; q++) {
            _state?._setGhost(a, Offset.lerp(a, b, q / 4));
            await Future<void>.delayed(delay);
          }
          if (run.interrupted) break;
          s._setGhost(null, null);
        }
        _commitNext(s, run);
        if (animate && op is _PlannedFitting && !run.done) {
          await Future<void>.delayed(delay);
        }
      }
    } finally {
      if (identical(_run, run)) _run = null;
    }
    if (!run.interrupted && _state != null) {
      s._showWorldRect(plan.boundsWith(s._drawingBounds()),
          fallback: plan.bounds);
    }
    _changed();
    return IsoDrawReport(
      assumedPl: plan.assumedPl,
      assumedEn: plan.assumedEn,
      segments: run.segments,
      elbows: run.elbows,
      fittings: run.fittings,
    );
  }

  /// Gest palca, Cofnij, wyjście z ekranu albo inny szkic w trakcie
  /// animacji: reszta polecenia trafia do szkicu od razu, bez animacji.
  void _finishNow() {
    final run = _run;
    if (run == null) return;
    _run = null;
    run.interrupted = true;
    final s = _state;
    if (s == null) return;
    s._setGhost(null, null);
    while (!run.done) {
      _commitNext(s, run);
    }
  }

  void _commitNext(_IsoState s, _VoiceRun run) {
    final plan = run.plan;
    final op = plan.ops[run.next++];
    switch (op) {
      case _PlannedSpatialBranch():
        s._mutate(() {
          final index = s._items.indexOf(op.tee);
          if (index >= 0) s._items[index] = op.tee.withSpatialTee(op.geometry);
          s._addSpatialWeldsAt(op.tee.pos,
              [op.geometry.run, op.geometry.run * -1, op.geometry.branch!]);
        });
      case _PlannedBranch():
        s._mutate(() {
          final index = s._items.indexOf(op.tee);
          if (index >= 0) {
            s._items[index] =
                op.tee.withTeeDirections(branch: op.branch, run: op.run);
          }
          s._addAutoWeldsAt(op.tee.pos, [op.branch, op.run, (op.run + 3) % 6]);
        });
      case _PlannedPipe():
        final dn = op.elbowDn;
        if (dn != null && op.spatialDirection == null) {
          // Through the drawing's take-out memory, exactly like a DN typed
          // in the elbow sheet: _maybeInsertElbows picks it up from there.
          final cte = s._recallCompDim(_Tool.elbow90, dn) ??
              isoStandardElbowCteMm(dn, 'lr90');
          s._rememberCompDim(_Tool.elbow90, dn, cte);
        }
        final seg = _Seg(plan.world(op.from), plan.world(op.to), _Tool.pipe,
            calc: op.calc, spatialDirection: op.spatialDirection);
        final before = _elbowCount(s);
        s._mutate(() => s._items.add(seg));
        if (op.spatialDirection == null) {
          s._maybeInsertElbows(seg);
        } else if (op.spatialBend != null) {
          final bend = op.spatialBend!;
          final is45 = (bend.degrees - 45).abs() < 1e-7;
          final tool = is45 ? _Tool.elbow45 : _Tool.elbow90;
          final subtype = is45 ? _ElbowSubtype.lr45 : _ElbowSubtype.lr90;
          final cte = dn == null
              ? null
              : (s._recallCompDim(tool, dn) ??
                  isoStandardElbowCteMm(dn, subtype.name));
          s._mutate(() => s._items.add(_Comp(seg.a, tool,
              dir: s._closestIsoHeading(seg.a - seg.b),
              dn: dn,
              elbowSubtype: subtype,
              cteMm: cte,
              spatialBend: bend)));
          s._mutate(() =>
              s._addSpatialWeldsAt(seg.a, [bend.incoming * -1, bend.outgoing]));
          if (dn != null && cte != null) s._rememberCompDim(tool, dn, cte);
        }
        run.segments++;
        run.elbows += _elbowCount(s) - before;
      case _PlannedFitting():
        final pos = plan.world(op.at);
        s._mutate(() {
          var comp = _Comp(pos, op.tool,
              dir: op.dir,
              label: op.tool.isWeld ? '${s._nextWeldNo()}' : op.label,
              spatialDirection: op.spatialDirection,
              spatialTee: op.spatialTee);
          final dn = op.dn;
          if (dn != null && op.tool == _Tool.elbow45) {
            comp = comp.withElbowSpec(
                dn: dn, subtype: _ElbowSubtype.lr45, cte: op.cte);
          } else if (dn != null && op.tool == _Tool.tee) {
            comp = comp.withTeeSpec(dn: dn, dnBranch: op.dnOut, cte: op.cte);
          } else if (dn != null) {
            comp = comp.withPhysicalSpec(
              dn: dn,
              dnOut: op.dnOut,
              physicalLengthMm: op.lengthMm,
              endA: op.endA,
              endB: op.endB,
            );
          }
          s._items.add(comp);
          _weldFitting(s, op, pos);
        });
        run.fittings++;
    }
    if (run.done) {
      // A fitting placed before its pipe (e.g. a flange at the very start)
      // had nothing to weld to yet; the weld pass is idempotent.
      for (final f in plan.ops.whereType<_PlannedFitting>()) {
        if (f.spatialTee == null && (f.dn == null || f.endA == null)) continue;
        final pos = plan.world(f.at);
        final count = s._items.length;
        _weldFitting(s, f, pos);
        if (s._items.length != count) s._mutate(() {});
      }
    }
  }

  static void _weldFitting(_IsoState s, _PlannedFitting f, Offset pos) {
    if (f.spatialTee case final tee?) {
      final expected = [
        tee.run,
        tee.run * -1,
        if (tee.branch != null) tee.branch!
      ];
      final connected = <IsoSpatialVector>[];
      for (final pipe
          in s._items.whereType<_Seg>().where((p) => p.t == _Tool.pipe)) {
        if ((pipe.a - pos).distance >= _IsoState._s * .25 &&
            (pipe.b - pos).distance >= _IsoState._s * .25) {
          continue;
        }
        final ray = s._spatialOutgoing(pipe, pos);
        if (ray != null && expected.any((e) => e.dot(ray) > 1 - 1e-8)) {
          connected.add(ray);
        }
      }
      s._addSpatialWeldsAt(pos, connected);
      return;
    }
    final a = f.endA, b = f.endB;
    if (f.dn == null || a == null || b == null) return;
    if (f.spatialDirection case final ray?) {
      if (!s._pipeTouches(pos)) return;
      s._addSpatialWeldsAt(
          pos, [if (a.producesWeld) ray * -1, if (b.producesWeld) ray]);
    } else {
      s._addPhysicalCompWelds(pos: pos, dir: f.dir, endA: a, endB: b);
    }
  }

  static int _elbowCount(_IsoState s) =>
      s._items.where((it) => it is _Comp && it.isElbow).length;

  // ── planowanie (bez skutków ubocznych) ─────────────────────────────────────

  static const Map<String, _Tool> _kFittings = {
    'tee': _Tool.tee,
    'flange': _Tool.flange,
    'blindFlange': _Tool.blindFlange,
    'cap': _Tool.cap,
    'reducer': _Tool.reducer,
    'gateValve': _Tool.gateValve,
    'ballValve': _Tool.ballValve,
    'checkValve': _Tool.checkValve,
    'globeValve': _Tool.globeValve,
    'butterflyValve': _Tool.butterflyValve,
    'weld': _Tool.weld,
    'fieldWeld': _Tool.fieldWeld,
    'support': _Tool.support,
  };

  _VoicePlan _plan(_IsoState s, List<IsoStep> steps,
      {bool fromLastTee = false, bool explicitLastTee = false}) {
    final m = s._currentMapping;
    final cursor = _cursor(s);
    final teeTarget =
        s._items.whereType<_Comp>().where((c) => c.t == _Tool.tee).lastOrNull;
    final spatial = fromLastTee
        ? teeTarget?.spatialTee != null ||
            (teeTarget != null &&
                s._items.whereType<_Seg>().any((p) =>
                    _hasSpatialSlope(p) &&
                    ((p.a - teeTarget.pos).distance < _IsoState._s * .25 ||
                        (p.b - teeTarget.pos).distance < _IsoState._s * .25)))
        : steps.any((step) => step is IsoTurn && step.degrees != 90) ||
            cursor?.spatialDirection != null;
    if (spatial) {
      return _planSpatial(s, steps,
          fromLastTee: fromLastTee, explicitLastTee: explicitLastTee);
    }
    final pl = <String>[], en = <String>[];
    void assume(String p, String e) {
      if (pl.contains(p)) return;
      pl.add(p);
      en.add(e);
    }

    var start = _cursor(s);
    _Comp? branchTee;
    int? branchRun;
    if (fromLastTee) {
      if (steps.isEmpty ||
          steps.first is! IsoPipe ||
          (steps.first as IsoPipe).dir == null) {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      final tees =
          s._items.whereType<_Comp>().where((c) => c.t == _Tool.tee).toList();
      if (tees.length > 1 && !explicitLastTee) {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      branchTee = tees.lastOrNull;
      if (branchTee == null) {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      final legs = <int>{};
      for (final pipe
          in s._items.whereType<_Seg>().where((p) => p.t == _Tool.pipe)) {
        if ((pipe.a - branchTee.pos).distance < _IsoState._s * .25) {
          legs.add(s._closestIsoHeading(pipe.b - pipe.a));
        }
        if ((pipe.b - branchTee.pos).distance < _IsoState._s * .25) {
          legs.add(s._closestIsoHeading(pipe.a - pipe.b));
        }
      }
      branchRun = legs.where((g) => legs.contains((g + 3) % 6)).firstOrNull;
      final g = _gridDirOf((steps.first as IsoPipe).dir!, m);
      if (branchRun == null ||
          legs.length != 2 ||
          g == branchRun ||
          g == (branchRun + 3) % 6) {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      start = (point: branchTee.pos, heading: g, spatialDirection: null);
    }
    final relative = start == null;
    var cur = relative ? (row: 0, half: 0) : _worldToLat(start.point);
    int? heading = start?.heading;
    // A non-weld component on the cursor blocks the automatic elbow there.
    var blocked = !relative && _blockingCompAt(s, start.point);
    // An elbow already standing on the free end: `_maybeInsertElbows` would
    // keep it (in its old orientation) and add nothing, so neither a pipe
    // nor a fitting may start there.
    final elbowHere = !relative && _elbowAt(s, start.point);
    int? runDn = branchTee?.dnOut ?? branchTee?.dn;
    IsoTurn? turn;
    var turnAt = -1;
    var noLength = 0;
    final ops = <_PlannedOp>[
      if (branchTee != null)
        _PlannedBranch(0,
            at: cur, tee: branchTee, run: branchRun!, branch: heading!),
    ];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      switch (step) {
        case IsoTurn():
          if (turn == null) {
            turn = step;
            turnAt = i;
          } else {
            turn = IsoTurn(
                toDir: step.toDir ?? turn.toDir, dn: step.dn ?? turn.dn);
            assume('Dwa kolana pod rząd policzyłem jako jedno.',
                'Two elbows in a row counted as one.');
          }
        case IsoFitting():
          final tool = _kFittings[step.tool] ??
              (step.symbolOnly && steps.length == 1
                  ? switch (step.tool) {
                      'elbow45' => _Tool.elbow45,
                      'tee' => _Tool.tee,
                      _ => null
                    }
                  : null);
          if (tool == null) {
            if (step.tool == 'elbow45') {
              return _VoicePlan.failed(IsoDrawProblem.unsupported45, i);
            }
            if (step.tool == 'tee' || step.tool == 'olet') {
              return _VoicePlan.failed(IsoDrawProblem.unsupportedTee, i);
            }
            throw ArgumentError.value(step.tool, 'IsoFitting.tool',
                'not an axial fitting the notebook can place');
          }
          if (turn != null) {
            return _VoicePlan.failed(IsoDrawProblem.trailingTurn, turnAt);
          }
          if (elbowHere && !tool.isWeld) {
            return _VoicePlan.failed(IsoDrawProblem.turnAtFitting, i,
                elbowAtCursor: true);
          }
          if (tool == _Tool.tee &&
              step.dnOut != null &&
              (step.dn == null || step.dnOut! > step.dn!)) {
            return _VoicePlan.failed(IsoDrawProblem.invalidFittingSize, i);
          }
          if (step.symbolOnly &&
              ((step.dn != null && !_IsoState._dnChoices.contains(step.dn)) ||
                  (step.dnOut != null &&
                      !_IsoState._dnChoices.contains(step.dnOut)))) {
            return _VoicePlan.failed(IsoDrawProblem.invalidFittingSize, i);
          }
          final f = _planFitting(
            s,
            tool: tool,
            step: step,
            index: i,
            at: cur,
            heading: step.symbolOnly && step.dir != null
                ? _gridDirOf(step.dir!, m)
                : heading ?? _lookAheadDir(steps, i, m),
            atStart: heading == null,
            runDn: runDn,
            assume: assume,
          );
          ops.add(f);
          if (f.dnAfter != null) runDn = f.dnAfter;
          if (!tool.isWeld) blocked = true;
        case IsoPipe():
          final IsoDir dir;
          final pd = step.dir;
          if (turn != null) {
            final td = turn.toDir;
            if (heading == null) {
              assume('Kolano na początku pominąłem — przed nim nie ma rury.',
                  'Skipped the elbow at the start — there is no pipe before it.');
              dir = pd ?? td ?? IsoDir.right;
              if (pd == null && td == null) {
                assume('Pierwsza rura bez kierunku: przyjąłem w prawo.',
                    'First pipe without a direction: drawn to the right.');
              }
            } else if (pd != null && td != null && pd != td) {
              dir = pd;
              assume(
                  'Kolano i rura miały różne kierunki — przyjąłem kierunek '
                      'rury (${_dirPl(pd)}).',
                  'The elbow and the pipe named different directions — '
                      'used the pipe’s (${_dirEn(pd)}).');
            } else if (pd != null || td != null) {
              dir = (pd ?? td)!;
            } else {
              dir = _defaultTurn(_semanticOf(heading, m));
              assume('Kolano bez kierunku: przyjąłem skręt ${_dirPl(dir)}.',
                  'Elbow without a direction: turned ${_dirEn(dir)}.');
            }
          } else if (pd != null) {
            dir = pd;
          } else if (heading == null) {
            dir = IsoDir.right;
            assume('Pierwsza rura bez kierunku: przyjąłem w prawo.',
                'First pipe without a direction: drawn to the right.');
          } else {
            dir = _semanticOf(heading, m);
            assume(
                'Rura bez kierunku: przyjąłem dalej prosto (${_dirPl(dir)}).',
                'Pipe without a direction: carried straight on '
                    '(${_dirEn(dir)}).');
          }
          final g = _gridDirOf(dir, m);
          if (elbowHere) {
            return _VoicePlan.failed(
                IsoDrawProblem.turnAtFitting, turn != null ? turnAt : i,
                elbowAtCursor: true);
          }
          if (heading != null) {
            final about = turn != null ? turnAt : i;
            final spatialAngle = isoSpatialGridTurnDegrees(heading, g);
            if ((spatialAngle - 180).abs() < 1e-8) {
              return _VoicePlan.failed(IsoDrawProblem.reversal, about);
            }
            if (turn != null && spatialAngle.abs() < 1e-8) {
              return _VoicePlan.failed(
                  IsoDrawProblem.sameDirectionAfterTurn, turnAt);
            }
            if (g != heading && blocked) {
              return _VoicePlan.failed(IsoDrawProblem.turnAtFitting, about);
            }
          }
          final len = step.lengthMm;
          final hasLen = len != null && len.isFinite && len > 0;
          final n = hasLen ? (len / 500).round().clamp(2, 8) : 3;
          if (!hasLen) noLength++;
          final to = _latMove(cur, g, n);
          if (!relative && to.row < 0) {
            return _VoicePlan.failed(IsoDrawProblem.outOfCanvas, i);
          }
          final corner = heading != null && g != heading;
          final turnDn = _validDn(turn?.dn);
          if (turnDn != null) runDn = turnDn;
          ops.add(_PlannedPipe(
            i,
            from: cur,
            to: to,
            calc: hasLen ? _CutCalc(isoLengthExpression(len)) : null,
            elbowDn: corner ? runDn : null,
          ));
          cur = to;
          heading = g;
          turn = null;
          blocked = false;
      }
    }
    if (turn != null) {
      return _VoicePlan.failed(IsoDrawProblem.trailingTurn, turnAt);
    }
    if (noLength > 0) {
      assume(
          'Bez długości: $noLength ${_pipesPl(noLength)} — wymiar do '
              'uzupełnienia.',
          'No length: $noLength pipe${noLength == 1 ? '' : 's'} — dimension '
              'still to enter.');
    }
    final origin = relative ? _originFor(s, ops) : (row: 0, half: 0);
    return _VoicePlan(ops: ops, origin: origin, assumedPl: pl, assumedEn: en);
  }

  /// Plans genuine spatial rays. Paper coordinates are never quantized back
  /// to a grid heading: two different physical rays can share a projection.
  _VoicePlan _planSpatial(_IsoState s, List<IsoStep> steps,
      {required bool fromLastTee, required bool explicitLastTee}) {
    final cursor = _cursor(s);
    var relative = cursor == null;
    final m = s._currentMapping;
    var point = cursor?.point ?? Offset.zero;
    IsoSpatialVector? ray = cursor == null
        ? null
        : (cursor.spatialDirection ??
            IsoSpatialVector.gridHeading(cursor.heading));
    var blocked = cursor != null && _blockingCompAt(s, point);
    var elbowHere = cursor != null && _elbowAt(s, point);
    IsoTurn? turn;
    var turnAt = -1;
    int? runDn;
    var noLength = 0;
    final ops = <_PlannedOp>[];
    final pl = <String>[], en = <String>[];
    _Lat at(Offset p) => (row: p.dy / _kRowH, half: p.dx / _kHalfStep);
    void assume(String p, String e) {
      if (!pl.contains(p)) {
        pl.add(p);
        en.add(e);
      }
    }

    int? grid(IsoSpatialVector v) {
      for (var i = 0; i < 6; i++) {
        if ((v - IsoSpatialVector.gridHeading(i)).magnitude < 1e-8) return i;
      }
      return null;
    }

    if (fromLastTee) {
      final tees =
          s._items.whereType<_Comp>().where((c) => c.t == _Tool.tee).toList();
      final tee = tees.lastOrNull;
      final pipe = steps.firstOrNull;
      var original = tee?.spatialTee;
      if (tee == null ||
          original?.branch != null ||
          (tees.length > 1 && !explicitLastTee) ||
          pipe is! IsoPipe ||
          pipe.dir == null) {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      final touching = s._items
          .whereType<_Seg>()
          .where((p) =>
              p.t == _Tool.pipe &&
              ((p.a - tee.pos).distance < _IsoState._s * .25 ||
                  (p.b - tee.pos).distance < _IsoState._s * .25))
          .toList();
      final rays = touching.map((p) => s._spatialOutgoing(p, tee.pos)).toList();
      if (original == null &&
          rays.length == 2 &&
          rays.every((r) => r != null) &&
          rays[0]!.dot(rays[1]!) < -1 + 1e-8) {
        original = IsoSpatialTee(run: rays[0]! * -1);
      }
      final run = original?.run;
      if (run == null ||
          rays.length != 2 ||
          rays.any((r) => r == null) ||
          !rays.any((r) => r!.dot(run) > 1 - 1e-8) ||
          !rays.any((r) => r!.dot(run) < -1 + 1e-8)) {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      final branch = IsoSpatialVector.gridHeading(_gridDirOf(pipe.dir!, m));
      IsoSpatialTee geometry;
      try {
        geometry = IsoSpatialTee(run: run, branch: branch);
      } on ArgumentError {
        return _VoicePlan.failed(IsoDrawProblem.invalidBranch, 0);
      }
      point = tee.pos;
      ray = branch;
      relative = false;
      blocked = false;
      elbowHere = false;
      runDn = tee.dnOut ?? tee.dn;
      ops.add(_PlannedSpatialBranch(0,
          at: at(point), tee: tee, geometry: geometry));
    }
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      switch (step) {
        case IsoTurn():
          if (turn != null ||
              ray == null ||
              (step.degrees != 45 && step.degrees != 90)) {
            return _VoicePlan.failed(IsoDrawProblem.invalidSpatialTurn, i);
          }
          turn = step;
          turnAt = i;
        case IsoPipe():
          final incoming = ray;
          IsoSpatialVector next;
          if (turn != null) {
            final target = step.dir ?? turn.toDir;
            if (target == null ||
                (step.dir != null &&
                    turn.toDir != null &&
                    step.dir != turn.toDir)) {
              return _VoicePlan.failed(
                  IsoDrawProblem.invalidSpatialTurn, turnAt);
            }
            try {
              next = incoming!.turnTowards(
                  IsoSpatialVector.gridHeading(_gridDirOf(target, m)),
                  turn.degrees.toDouble());
            } on ArgumentError {
              return _VoicePlan.failed(
                  IsoDrawProblem.invalidSpatialTurn, turnAt);
            }
          } else if (step.dir != null) {
            next = IsoSpatialVector.gridHeading(_gridDirOf(step.dir!, m));
          } else {
            next = incoming ?? IsoSpatialVector.gridHeading(0);
            if (incoming == null) {
              assume('Pierwsza rura bez kierunku: przyjąłem w prawo.',
                  'First pipe without a direction: drawn to the right.');
            }
          }
          final angle = incoming?.angleTo(next) ?? 0;
          if ((angle - 180).abs() < 1e-7) {
            return _VoicePlan.failed(IsoDrawProblem.reversal, i);
          }
          if (turn != null && angle < 1e-7) {
            return _VoicePlan.failed(
                IsoDrawProblem.sameDirectionAfterTurn, turnAt);
          }
          final corner = angle > 1e-7;
          if (corner &&
              (angle - 45).abs() > 1e-7 &&
              (angle - 90).abs() > 1e-7) {
            return _VoicePlan.failed(IsoDrawProblem.invalidSpatialTurn, i);
          }
          if (elbowHere || (blocked && corner)) {
            return _VoicePlan.failed(IsoDrawProblem.turnAtFitting, i,
                elbowAtCursor: elbowHere);
          }
          final len = step.lengthMm;
          final hasLen = len != null && len.isFinite && len > 0;
          final n = hasLen ? (len / 500).round().clamp(2, 8) : 3;
          if (!hasLen) noLength++;
          final projected = next.projected;
          final end =
              point + Offset(projected.x, projected.y) * (_IsoState._s * n);
          if (!relative && end.dy < 0) {
            return _VoicePlan.failed(IsoDrawProblem.outOfCanvas, i);
          }
          IsoSpatialElbow? bend;
          if (corner) {
            try {
              bend = IsoSpatialElbow(incoming: incoming!, outgoing: next);
            } on ArgumentError {
              return _VoicePlan.failed(IsoDrawProblem.invalidSpatialTurn, i);
            }
          }
          final dn = _validDn(turn?.dn);
          if (dn != null) runDn = dn;
          ops.add(_PlannedPipe(i,
              from: at(point),
              to: at(end),
              calc: hasLen ? _CutCalc(isoLengthExpression(len)) : null,
              elbowDn: corner ? runDn : null,
              spatialDirection: next,
              spatialBend: bend));
          point = end;
          ray = next;
          turn = null;
          blocked = false;
        case IsoFitting():
          if (turn != null) {
            return _VoicePlan.failed(IsoDrawProblem.trailingTurn, turnAt);
          }
          if (step.symbolOnly && steps.length == 1) {
            final tool = switch (step.tool) {
              'elbow45' => _Tool.elbow45,
              'tee' => _Tool.tee,
              _ => _kFittings[step.tool],
            };
            if (tool == null) {
              return _VoicePlan.failed(IsoDrawProblem.spatialFitting, i);
            }
            if ((step.dn != null && !_IsoState._dnChoices.contains(step.dn)) ||
                (step.dnOut != null &&
                    !_IsoState._dnChoices.contains(step.dnOut)) ||
                (tool == _Tool.tee &&
                    step.dnOut != null &&
                    (step.dn == null || step.dnOut! > step.dn!))) {
              return _VoicePlan.failed(IsoDrawProblem.invalidFittingSize, i);
            }
            ops.add(_planFitting(s,
                tool: tool,
                step: step,
                index: i,
                at: at(point),
                heading: _gridDirOf(step.dir ?? IsoDir.right, m),
                atStart: ray == null,
                runDn: runDn,
                assume: assume));
            continue;
          }
          final heading = ray == null ? _lookAheadDir(steps, i, m) : grid(ray);
          final tool = _kFittings[step.tool];
          if (tool == null || step.symbolOnly) {
            return _VoicePlan.failed(IsoDrawProblem.spatialFitting, i);
          }
          if (elbowHere && !tool.isWeld) {
            return _VoicePlan.failed(IsoDrawProblem.turnAtFitting, i,
                elbowAtCursor: true);
          }
          if (tool == _Tool.tee &&
              step.dnOut != null &&
              (step.dn == null || step.dnOut! > step.dn!)) {
            return _VoicePlan.failed(IsoDrawProblem.invalidFittingSize, i);
          }
          final fitting = _planFitting(s,
              tool: tool,
              step: step,
              index: i,
              at: at(point),
              heading: heading ??
                  s._closestIsoHeading(
                      Offset(ray!.projected.x, ray.projected.y)),
              spatialDirection:
                  heading == null && tool != _Tool.tee ? ray : null,
              spatialTee: heading == null && tool == _Tool.tee
                  ? IsoSpatialTee(run: ray!)
                  : null,
              atStart: ray == null,
              runDn: runDn,
              assume: assume);
          ops.add(fitting);
          if (fitting.dnAfter != null) runDn = fitting.dnAfter;
          if (!tool.isWeld) blocked = true;
      }
    }
    if (turn != null) {
      return _VoicePlan.failed(IsoDrawProblem.trailingTurn, turnAt);
    }
    if (noLength > 0) {
      assume(
          'Bez długości: $noLength ${_pipesPl(noLength)} — wymiar do uzupełnienia.',
          'No length: $noLength pipes — dimension still to enter.');
    }
    return _VoicePlan(
        ops: ops,
        origin: relative ? _originFor(s, ops) : (row: 0, half: 0),
        assumedPl: pl,
        assumedEn: en);
  }

  _PlannedFitting _planFitting(
    _IsoState s, {
    required _Tool tool,
    required IsoFitting step,
    required int index,
    required _Lat at,
    required int heading,
    IsoSpatialVector? spatialDirection,
    IsoSpatialTee? spatialTee,
    required bool atStart,
    required int? runDn,
    required void Function(String pl, String en) assume,
  }) {
    // A flange / cap at the START of a run faces away from its pipe: the
    // weld side (end A, −heading) must look at the pipe leaving it.
    final terminal =
        tool == _Tool.flange || tool == _Tool.blindFlange || tool == _Tool.cap;
    final dir =
        atStart && terminal && !step.symbolOnly ? (heading + 3) % 6 : heading;
    final axis = atStart && terminal && !step.symbolOnly
        ? spatialDirection == null
            ? null
            : spatialDirection * -1
        : spatialDirection;
    if (tool.isWeld || tool == _Tool.support) {
      return _PlannedFitting(index,
          spatialDirection: axis,
          spatialTee: spatialTee,
          at: at,
          tool: tool,
          dir: dir);
    }
    final namePl = _IsoState.compName(tool, true);
    final nameEn = _IsoState.compName(tool, false);
    var dn = _validDn(step.dn);
    if (dn == null) {
      dn = runDn ?? s._lastDnByTool[tool] ?? s._lastDnByTool[_Tool.elbow90];
      if (dn != null) {
        assume('$namePl: przyjąłem DN$dn.', '$nameEn: assumed DN$dn.');
      } else {
        assume('$namePl: bez średnicy — uzupełnij DN.',
            '$nameEn: no size — enter the DN.');
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: dir);
      }
    }
    switch (tool) {
      case _Tool.elbow45:
        final value =
            kElbowTakeouts.where((row) => row.dn == dn).firstOrNull?.lr45;
        final cte = value != null && value > 0 ? value : null;
        if (cte == null) _noTableLength(assume, namePl, nameEn, dn);
        assume(
            'Umieściłem symbol kolana 45° we wskazanej orientacji. Pochylenie i dalszą trasę trzeba określić osobno.',
            'Placed a 45° elbow symbol in the specified orientation. Specify slope and further routing separately.');
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: heading,
            dn: dn,
            cte: cte,
            dnAfter: dn);
      case _Tool.tee:
        final cte = TakeoutCatalog.tee[dn];
        if (cte == null) _noTableLength(assume, namePl, nameEn, dn);
        if (spatialTee != null) {
          assume(
              'Przelot trójnika biegnie wzdłuż rury. Znak „?” oznacza nieustawiony kierunek odgałęzienia; podaj go poleceniem „od trójnika rura…”.',
              'The tee run follows the pipe. “?” marks an unspecified branch direction; specify it with “from the tee pipe…”.');
        } else {
          assume(
              'Umieściłem symbol trójnika we wskazanej orientacji. Odgałęzienie nie ma jeszcze narysowanej rury.',
              'Placed a tee symbol in the specified orientation. Its branch pipe is not drawn yet.');
        }
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: heading,
            dn: dn,
            dnOut: step.dnOut,
            cte: cte,
            dnAfter: dn);
      case _Tool.reducer:
        var out = _validDn(step.dnOut);
        if (out == null) {
          for (final d in _IsoState._dnChoices.reversed) {
            if (d < dn) {
              out = d;
              break;
            }
          }
          if (out == null) {
            assume('$namePl: bez średnicy wylotu — uzupełnij.',
                '$nameEn: no outlet size — enter it.');
            return _PlannedFitting(index,
                spatialDirection: axis,
                spatialTee: spatialTee,
                at: at,
                tool: tool,
                dir: dir);
          }
          assume('$namePl: przyjąłem DN$dn na DN$out.',
              '$nameEn: assumed DN$dn to DN$out.');
        }
        final hi = math.max(dn, out), lo = math.min(dn, out);
        final len = _IsoState._reducerLenDefault[hi];
        if (len == null) _noTableLength(assume, namePl, nameEn, hi);
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: dir,
            dn: hi,
            dnOut: lo,
            lengthMm: len,
            endA: EndConnection.buttWeld,
            endB: EndConnection.buttWeld,
            label: len != null ? 'DN$hi→DN$lo · $len mm' : 'DN$hi→DN$lo',
            dnAfter: lo);
      case _Tool.flange:
      case _Tool.blindFlange:
        // The flange sheet's defaults: weld neck, blind = slip-on.
        final type = tool == _Tool.blindFlange
            ? EndConnection.slipOn
            : EndConnection.weldNeck;
        final len = isoFlangeAxialLengthMm(dn: dn, type: type);
        if (len == null) _noTableLength(assume, namePl, nameEn, dn);
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: dir,
            dn: dn,
            lengthMm: len,
            endA: type,
            endB: EndConnection.none,
            label: 'DN$dn · ${type.code}',
            dnAfter: dn);
      case _Tool.cap:
        final len = TakeoutCatalog.cap[dn];
        if (len == null) _noTableLength(assume, namePl, nameEn, dn);
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: dir,
            dn: dn,
            lengthMm: len,
            endA: EndConnection.buttWeld,
            endB: EndConnection.none,
            label: 'DN$dn',
            dnAfter: dn);
      default:
        // Valves — the per-kind B16.10 / wafer tables.
        final len = isoValveFaceToFaceMm(tool.name, dn);
        if (len == null) _noTableLength(assume, namePl, nameEn, dn);
        return _PlannedFitting(index,
            spatialDirection: axis,
            spatialTee: spatialTee,
            at: at,
            tool: tool,
            dir: dir,
            dn: dn,
            lengthMm: len,
            endA: EndConnection.buttWeld,
            endB: EndConnection.buttWeld,
            label: 'DN$dn',
            dnAfter: dn);
    }
  }

  static void _noTableLength(void Function(String pl, String en) assume,
          String namePl, String nameEn, int dn) =>
      assume(
          '$namePl DN$dn: brak długości w tablicy — wpisz ją z karty '
              'katalogowej.',
          '$nameEn DN$dn: no table length — enter it from the datasheet.');

  static int? _validDn(int? dn) => dn != null && dn > 0 ? dn : null;

  /// Grid heading of the first pipe after step [i] — orients a fitting that
  /// is placed before any pipe exists.
  static int _lookAheadDir(List<IsoStep> steps, int i, _AxisMapping? m) {
    IsoDir? turnDir;
    for (var j = i + 1; j < steps.length; j++) {
      final s = steps[j];
      if (s is IsoTurn) turnDir = s.toDir ?? turnDir;
      if (s is IsoPipe) return _gridDirOf(s.dir ?? turnDir ?? IsoDir.right, m);
    }
    return _gridDirOf(IsoDir.right, m);
  }

  /// Free end of the last pipe and the heading it arrives with, or null
  /// when the sheet has no pipe yet.
  static ({Offset point, int heading, IsoSpatialVector? spatialDirection})?
      _cursor(_IsoState s) {
    final tol = _IsoState._s * 0.25;
    _Seg? last;
    for (var i = s._items.length - 1; i >= 0; i--) {
      final it = s._items[i];
      if (it is _Seg && it.t == _Tool.pipe) {
        last = it;
        break;
      }
    }
    if (last == null) return null;
    final self = last;
    bool shared(Offset p) => s._items.any((it) =>
        it is _Seg &&
        it.t == _Tool.pipe &&
        !identical(it, self) &&
        ((it.a - p).distance < tol || (it.b - p).distance < tol));
    final fromA = shared(self.b) && !shared(self.a);
    final free = fromA ? self.a : self.b;
    final other = fromA ? self.b : self.a;
    return (
      point: free,
      heading: s._closestIsoHeading(free - other),
      spatialDirection: self.spatialDirection == null
          ? null
          : (fromA ? self.spatialDirection! * -1 : self.spatialDirection)
    );
  }

  static bool _elbowAt(_IsoState s, Offset p) => s._items.any((it) =>
      it is _Comp && it.isElbow && (it.pos - p).distance < _IsoState._s * 0.45);

  /// Same rule as `_maybeInsertElbows`: any component but a weld keeps the
  /// automatic elbow out of [p] (an elbow there is [_elbowAt]'s case).
  static bool _blockingCompAt(_IsoState s, Offset p) => s._items.any((it) =>
      it is _Comp &&
      !it.t.isWeld &&
      !it.isElbow &&
      (it.pos - p).distance < _IsoState._s * 0.45);

  /// Origin for a route drawn on a sheet without pipes: centred in the
  /// visible canvas, pushed down so no point lands above grid row 1.
  static _Lat _originFor(_IsoState s, List<_PlannedOp> ops) {
    final pts = [for (final op in ops) ...op.points];
    if (pts.isEmpty) return (row: 0, half: 0);
    var minRow = pts.first.row, maxRow = minRow;
    var minHalf = pts.first.half, maxHalf = minHalf;
    for (final p in pts) {
      minRow = math.min(minRow, p.row);
      maxRow = math.max(maxRow, p.row);
      minHalf = math.min(minHalf, p.half);
      maxHalf = math.max(maxHalf, p.half);
    }
    final view = s._visibleWorld ?? const Rect.fromLTWH(0, 0, 320, 320);
    final cx = (minHalf + maxHalf) / 2 * _kHalfStep;
    final cy = (minRow + maxRow) / 2 * _kRowH;
    var row = ((view.center.dy - cy) / _kRowH).round();
    var half = ((view.center.dx - cx) / _kHalfStep).round();
    if (row + minRow < 1) row = (1 - minRow).ceil();
    // Grid parity: odd rows sit half a step to the right.
    if ((half - row).isOdd) half += 1;
    return (row: row, half: half);
  }
}

// ── kierunki ─────────────────────────────────────────────────────────────────

/// Grid heading (index into [_isoHeadings]) for a fitter's direction.
///
/// Up/down = the axis the compass legend calls vertical (III, or II when a
/// North arrow lies on III), up = towards the top of the screen; forward /
/// back = the other horizontal axis, forward = towards the bottom of the
/// screen (towards the viewer); right / left = axis I. Without a North arrow
/// this is exactly `dir.index`.
int _gridDirOf(IsoDir d, _AxisMapping? m) {
  final vertical = m?.upAxis ?? _Axis.iii;
  final horizontal = vertical == _Axis.iii ? _Axis.ii : _Axis.iii;
  int on(_Axis axis, {required bool screenUp}) {
    for (var i = 0; i < 6; i++) {
      if (_isoAxisByDir[i] != axis) continue;
      final h = _isoHeadings[i];
      if (screenUp ? h.dy < 0 : h.dy > 0) return i;
    }
    return 0;
  }

  return switch (d) {
    IsoDir.right => 0,
    IsoDir.left => 3,
    IsoDir.up => on(vertical, screenUp: true),
    IsoDir.down => on(vertical, screenUp: false),
    IsoDir.forward => on(horizontal, screenUp: false),
    IsoDir.back => on(horizontal, screenUp: true),
  };
}

IsoDir _semanticOf(int grid, _AxisMapping? m) => IsoDir.values
    .firstWhere((d) => _gridDirOf(d, m) == grid, orElse: () => IsoDir.right);

/// Skręt domyślny: z poziomu I na II, z II na I, z pionu na I.
IsoDir _defaultTurn(IsoDir from) => switch (from) {
      IsoDir.right || IsoDir.left => IsoDir.forward,
      IsoDir.forward || IsoDir.back => IsoDir.right,
      IsoDir.up || IsoDir.down => IsoDir.right,
    };

String _dirPl(IsoDir d) => switch (d) {
      IsoDir.right => 'w prawo',
      IsoDir.up => 'w górę',
      IsoDir.back => 'do tyłu',
      IsoDir.left => 'w lewo',
      IsoDir.down => 'w dół',
      IsoDir.forward => 'do przodu',
    };

String _dirEn(IsoDir d) => switch (d) {
      IsoDir.right => 'right',
      IsoDir.up => 'up',
      IsoDir.back => 'back',
      IsoDir.left => 'left',
      IsoDir.down => 'down',
      IsoDir.forward => 'forward',
    };

/// One sentence per problem — what is wrong and what to do next.
(String, String) _problemText(IsoDrawProblem p, {bool elbow = false}) =>
    switch (p) {
      IsoDrawProblem.reversal => (
          'Rura zawraca w kierunku, z którego przyszła — powiedz inny '
              'kierunek.',
          'The pipe doubles back the way it came — name another direction.',
        ),
      IsoDrawProblem.sameDirectionAfterTurn => (
          'Po kolanie rura idzie dalej prosto, a to nie jest skręt — powiedz, '
              'dokąd skręca.',
          'After the elbow the pipe carries straight on, which is no turn — '
              'say where it turns.',
        ),
      IsoDrawProblem.trailingTurn => (
          'Po kolanie brakuje rury — powiedz, dokąd idzie rura po kolanie.',
          'There is no pipe after the elbow — say where the pipe goes after '
              'it.',
        ),
      IsoDrawProblem.invalidSpatialTurn => (
          'Podaj kierunek skrętu kolana; kąt musi pasować do przestrzennej trasy i płaszczyzny skrętu.',
          'Specify the elbow target direction; its angle must fit the spatial route and bend plane.',
        ),
      IsoDrawProblem.spatialFitting => (
          'Ta kształtka wymaga jeszcze określenia przestrzennego przelotu i odgałęzienia. Możesz osobno umieścić jej symbol.',
          'This fitting still needs a spatial run and branch orientation. You can place its standalone symbol separately.',
        ),
      IsoDrawProblem.unsupported45 => (
          'Podaj kolano 45° jako skręt z kierunkiem i rurą za nim albo poproś o sam symbol kolana.',
          'Specify the 45° elbow as a turn with a target direction and a following pipe, or ask for its standalone symbol.',
        ),
      IsoDrawProblem.unsupportedTee => (
          'Trasa z odgałęzieniem wymaga dalszego określenia. Sam symbol dodasz poleceniem „wstaw symbol trójnika DN50”.',
          'Branch routing needs further specification. To place only the symbol, say “place tee symbol DN50”.',
        ),
      IsoDrawProblem.invalidFittingSize => (
          'Podaj DN z listy zeszytu; DN odgałęzienia nie może być większe od przelotu.',
          'Choose a notebook DN; the branch DN cannot exceed the run DN.',
        ),
      IsoDrawProblem.occupiedSymbol => (
          'W tym miejscu jest już kształtka. Nie nakładam symboli; dodaj odcinek rury albo wybierz nowy arkusz.',
          'A fitting already occupies this location. Add a pipe segment or choose a new sheet before placing another symbol.',
        ),
      IsoDrawProblem.invalidBranch => (
          'Wybierz kierunek odgałęzienia od trójnika z narysowanym prostym przelotem. Przy kilku trójnikach wskaż „od ostatniego trójnika”. Kierunek musi być prostopadły w przestrzeni do przelotu, a odgałęzienie jeszcze puste.',
          'Choose a branch direction from a tee with a drawn straight run. With several tees, say “from the last tee”. The direction must be perpendicular to the run in space and the branch must still be empty.',
        ),
      IsoDrawProblem.outOfCanvas => (
          'Rysunek wyszedłby nad górną krawędź arkusza — zacznij nowy rysunek '
              'albo rysuj w inną stronę.',
          'The drawing would go past the top of the sheet — start a new one '
              'or draw another way.',
        ),
      IsoDrawProblem.turnAtFitting when elbow => (
          'Na końcu stoi już kolano — powiedz „cofnij” albo narysuj palcem.',
          'An elbow already stands at the end — say “undo” or draw it with '
              'your finger.',
        ),
      IsoDrawProblem.turnAtFitting => (
          'Kolano nie ma gdzie stanąć — w tym punkcie jest już kształtka. '
              'Dodaj rurę między nimi.',
          'The elbow has nowhere to go — a fitting already sits there. Add a '
              'pipe between them.',
        ),
    };

String _pipesPl(int n) {
  if (n == 1) return 'rura';
  final d = n % 10, t = n % 100;
  return d >= 2 && d <= 4 && (t < 12 || t > 14) ? 'rury' : 'rur';
}

// ── siatka (wiersz, pół-kolumna) ─────────────────────────────────────────────
//
// Axis routes retain integer grid coordinates and their original parity.
// Spatial routes use fractional grid coordinates: snapping them back to
// integers would change the physical direction and break joined endpoints.

typedef _Lat = ({num row, num half});

const double _kHalfStep = _IsoState._s / 2.0;
final double _kRowH = _IsoState._s * math.sqrt(3) / 2.0;

/// (Δrow, Δhalf) of one grid step along each heading of [_isoHeadings].
const List<(int, int)> _kLatStep = [
  (0, 2),
  (-1, 1),
  (-1, -1),
  (0, -2),
  (1, -1),
  (1, 1),
];

_Lat _latMove(_Lat p, int dir, int n) => (
      row: p.row + _kLatStep[dir].$1 * n,
      half: p.half + _kLatStep[dir].$2 * n,
    );

_Lat _worldToLat(Offset o) =>
    (row: (o.dy / _kRowH).round(), half: (o.dx / _kHalfStep).round());

Offset _latToWorld(_Lat p) =>
    Offset((p.half * _kHalfStep).toDouble(), (p.row * _kRowH).toDouble());

// ── plan polecenia ───────────────────────────────────────────────────────────

sealed class _PlannedOp {
  const _PlannedOp(this.step);

  /// Index of the [IsoStep] this op comes from.
  final int step;

  Iterable<_Lat> get points;
}

final class _PlannedPipe extends _PlannedOp {
  const _PlannedPipe(super.step,
      {required this.from,
      required this.to,
      this.calc,
      this.elbowDn,
      this.spatialDirection,
      this.spatialBend});
  final _Lat from, to;
  final IsoSpatialVector? spatialDirection;
  final IsoSpatialElbow? spatialBend;
  final _CutCalc? calc;

  /// DN for the elbow at [from] (null = the drawing's memory decides).
  final int? elbowDn;

  @override
  Iterable<_Lat> get points => [from, to];
}

final class _PlannedBranch extends _PlannedOp {
  const _PlannedBranch(super.step,
      {required this.at,
      required this.tee,
      required this.run,
      required this.branch});
  final _Lat at;
  final _Comp tee;
  final int run, branch;
  @override
  Iterable<_Lat> get points => [at];
}

final class _PlannedSpatialBranch extends _PlannedOp {
  const _PlannedSpatialBranch(super.step,
      {required this.at, required this.tee, required this.geometry});
  final _Lat at;
  final _Comp tee;
  final IsoSpatialTee geometry;
  @override
  Iterable<_Lat> get points => [at];
}

final class _PlannedFitting extends _PlannedOp {
  const _PlannedFitting(
    super.step, {
    required this.at,
    required this.tool,
    required this.dir,
    this.dn,
    this.dnOut,
    this.lengthMm,
    this.endA,
    this.endB,
    this.label = '',
    this.dnAfter,
    this.cte,
    this.spatialDirection,
    this.spatialTee,
  });
  final _Lat at;
  final IsoSpatialVector? spatialDirection;
  final IsoSpatialTee? spatialTee;
  final _Tool tool;
  final int dir;
  final int? dn, dnOut, lengthMm, cte;
  final EndConnection? endA, endB;
  final String label;

  /// DN of the run downstream of this fitting.
  final int? dnAfter;

  @override
  Iterable<_Lat> get points => [at];
}

class _VoicePlan {
  _VoicePlan({
    required this.ops,
    required this.origin,
    required this.assumedPl,
    required this.assumedEn,
  })  : problem = null,
        problemStep = null,
        elbowAtCursor = false;

  _VoicePlan.failed(IsoDrawProblem this.problem, int this.problemStep,
      {this.elbowAtCursor = false})
      : ops = const [],
        origin = (row: 0, half: 0),
        assumedPl = const [],
        assumedEn = const [];

  final List<_PlannedOp> ops;
  final _Lat origin;
  final List<String> assumedPl, assumedEn;
  final IsoDrawProblem? problem;
  final int? problemStep;

  /// [problem] is an elbow already standing on the free end.
  final bool elbowAtCursor;

  Offset world(_Lat p) =>
      _latToWorld((row: p.row + origin.row, half: p.half + origin.half));

  /// World bounds of the new route.
  Rect get bounds {
    Rect? r;
    for (final op in ops) {
      for (final p in op.points) {
        final w = world(p);
        final pr = Rect.fromLTRB(w.dx, w.dy, w.dx, w.dy);
        r = r == null ? pr : r.expandToInclude(pr);
      }
    }
    return r ?? Rect.zero;
  }

  Rect boundsWith(Rect? drawing) =>
      drawing == null ? bounds : drawing.expandToInclude(bounds);
}

class _VoiceRun {
  _VoiceRun(this.plan);
  final _VoicePlan plan;
  int next = 0;
  bool interrupted = false;
  int segments = 0, elbows = 0, fittings = 0;

  bool get done => next >= plan.ops.length;
}
