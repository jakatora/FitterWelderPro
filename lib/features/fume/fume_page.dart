// Dymy spawalnicze i odciąg: co jest w dymie (materiał + proces, NDS),
// jak daleko od łuku może stać ssawka (równanie DallaValle), jaka ochrona
// dróg oddechowych jest minimum i lista kontrolna stanowiska. Logika,
// źródła i progi: lib/domain/fume/.
//
// Zasady ekranu: puste pole to komunikat, nie wynik; zasięg w dół do cm,
// wymagana wydajność w górę; prędkość uchwycenia tylko w górę od minimum
// procesu; poza zakresem równania nigdy zielono; brak odciągu — nigdy
// zielono; niezaznaczony punkt listy ≠ OK. Zmiana jednostki przelicza
// wpisane liczby (długość dokładnie, wydajność w dół). Ostatnie wejścia
// (bez listy kontrolnej) w SharedPreferences.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/fume/fume_assessment.dart';
import '../../domain/fume/fume_capture.dart';
import '../../domain/fume/fume_checklist.dart';
import '../../domain/fume/fume_hazards.dart';
import '../../domain/fume/fume_inputs.dart';
import '../../domain/fume/fume_sources.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'fume_input_store.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/fume/fume_reference.dart';

class FumePage extends StatefulWidget {
  const FumePage({super.key, this.store = const FumeInputStore()});

  /// Magazyn ostatnich wejść — wstrzykiwany w testach.
  final FumeInputStore store;

  @override
  State<FumePage> createState() => _FumePageState();
}

class _FumePageState extends State<FumePage> with ToolHandleHost<FumePage> {
  FumeAgent? _referenceAgent;
  final _scroll = ScrollController();
  @override
  String get toolId => 'fume';
  @override
  Set<String> get supportedFields => const {'reference_agent'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final a = FumeAgent.values
        .where((v) => v.name == fields['reference_agent'])
        .firstOrNull;
    if (fields.length != 1 || a == null) return fields.keys.toSet();
    setState(() {
      _referenceAgent = a;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
    return {};
  }

  FumeInputStore get _store => widget.store;

  final _flow = TextEditingController();
  final _diameter = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _velocity = TextEditingController();
  final _distance = TextEditingController();

  FumeMaterial? _material;
  FumeProcess? _process;
  FumeLevStatus? _lev;
  FumeRpe? _rpe;

  /// Maska noszona bez przerwy dłużej niż godzinę (null — brak odpowiedzi).
  bool? _longWear;
  FumeFlowUnit _flowUnit = FumeFlowUnit.m3h;
  FumeLengthUnit _lengthUnit = FumeLengthUnit.mm;
  FumeHoodShape _shape = FumeHoodShape.round;
  bool _flanged = false;
  final Map<String, FumeCheckState> _checks = {};

  /// Zapis był uszkodzony — pokazujemy informację.
  bool _corrupt = false;

  /// Spawacz zaczął wpisywać przed końcem odczytu — nie nadpisujemy.
  bool _touched = false;

  /// Odczyt zapisu zakończony. Wcześniej NIE zapisujemy — zapis domyślnych
  /// (pustych) wartości nadpisałby dane, które jeszcze się czytają.
  bool _loaded = false;

  /// Prędkość podniesiona do minimum po zmianie procesu.
  bool _velocityRaised = false;

  @override
  void initState() {
    super.initState();
    _velocity.text = _fmtField(kFumeCaptureDefaultMs);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_flow, _diameter, _width, _height, _velocity, _distance]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  // ── Zapis ──────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final FumeDecoded d;
    try {
      d = await _store.load();
    } finally {
      _loaded = true;
    }
    if (!mounted) return;
    markReady();
    if (_touched) return;
    final i = d.inputs;
    setState(() {
      _material = i.material;
      _process = i.process;
      _lev = i.lev;
      _rpe = i.rpe;
      _longWear = i.longWear;
      _flowUnit = i.flowUnit;
      _lengthUnit = i.lengthUnit;
      _shape = i.shape;
      _flanged = i.flanged;
      _flow.text = _fmtFieldOrEmpty(i.flow);
      _diameter.text = _fmtFieldOrEmpty(i.diameter);
      _width.text = _fmtFieldOrEmpty(i.width);
      _height.text = _fmtFieldOrEmpty(i.height);
      _distance.text = _fmtFieldOrEmpty(i.distance);
      _velocity.text = _fmtField(i.velocity);
      _corrupt = d.corrupt;
    });
  }

  /// Liczba do zapisu: tylko skończona i dodatnia (JSON nie zniesie NaN).
  double? _savable(TextEditingController c) {
    final v = _read(c);
    return v != null && v.isFinite && v > 0 ? v : null;
  }

  FumeInputs get _currentInputs {
    final v = _read(_velocity);
    final minV = fumeCaptureMinFor(_process);
    return FumeInputs(
      material: _material,
      process: _process,
      lev: _lev,
      rpe: _rpe,
      longWear: _longWear,
      flow: _savable(_flow),
      flowUnit: _flowUnit,
      shape: _shape,
      diameter: _savable(_diameter),
      width: _savable(_width),
      height: _savable(_height),
      lengthUnit: _lengthUnit,
      flanged: _flanged,
      velocity: v != null &&
              v.isFinite &&
              v >= minV - kFumeEps &&
              v <= kFumeMaxCaptureMs
          ? v
          : minV,
      distance: _savable(_distance),
    );
  }

  /// Każda zmiana wejścia: przerysuj i zapisz — ale dopiero po odczycie.
  void _changed(VoidCallback f) {
    _touched = true;
    setState(f);
    if (_loaded) unawaited(_store.save(_currentInputs));
  }

  // ── Pola ───────────────────────────────────────────────────────────────

  /// Pole: puste → null, nieczytelne → NaN (domena odróżnia oba).
  double? _read(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t) ?? double.nan;
  }

  String _fmtField(double v) =>
      formatFumeNumber(v, en: AppLanguageController.isEnglish, decimals: 6);
  String _fmtFieldOrEmpty(double? v) => v == null ? '' : _fmtField(v);

  String _n(double v, {int decimals = 2}) =>
      formatFumeNumber(v, en: _en, decimals: decimals);

  FumeCaptureInput get _captureInput => FumeCaptureInput(
        flow: _read(_flow),
        flowUnit: _flowUnit,
        shape: _shape,
        diameter: _read(_diameter),
        width: _read(_width),
        height: _read(_height),
        lengthUnit: _lengthUnit,
        flanged: _flanged,
        captureVelocity: _read(_velocity),
        minCaptureVelocity: fumeCaptureMinFor(_process),
        distance: _read(_distance),
      );

  void _setFlowUnit(FumeFlowUnit u) {
    if (u == _flowUnit) return;
    final v = _read(_flow);
    _changed(() {
      if (v != null && v.isFinite && v > 0) {
        _flow.text = _fmtField(convertFumeFlow(v, _flowUnit, u));
      }
      _flowUnit = u;
    });
  }

  void _setLengthUnit(FumeLengthUnit u) {
    if (u == _lengthUnit) return;
    _changed(() {
      for (final c in [_diameter, _width, _height, _distance]) {
        final v = _read(c);
        if (v != null && v.isFinite && v > 0) {
          c.text = _fmtField(convertFumeLength(v, _lengthUnit, u));
        }
      }
      _lengthUnit = u;
    });
  }

  void _setProcess(FumeProcess p) {
    _changed(() {
      _process = p;
      // Próg tylko zaostrzalny: prędkość poniżej minimum nowego procesu
      // podnosimy do minimum (nigdy w dół).
      final minV = fumeCaptureMinFor(p);
      final v = _read(_velocity);
      if (v == null || !v.isFinite || v < minV - kFumeEps) {
        _velocity.text = _fmtField(minV);
        _velocityRaised = v != null;
      } else {
        _velocityRaised = false;
      }
    });
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final capture = _lev == FumeLevStatus.present
        ? computeFumeCapture(_captureInput)
        : null;
    final assessment = assessFume(
      material: _material,
      process: _process,
      lev: _lev,
      capture: capture,
      rpe: _rpe,
      checks: _checks,
      longWear: _longWear,
    );

    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Dymy spawalnicze i odciąg',
              en: 'Welding fume and extraction'))),
      body: ListView(
        key: const ValueKey('fume-list'),
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (_referenceAgent != null)
            Card(
                key: const ValueKey('fume-assistant-reference'),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                              fumeOelReference(_referenceAgent!, en: _en)),
                          TextButton(
                              onPressed: () =>
                                  setState(() => _referenceAgent = null),
                              child: Text(context.tr(
                                  pl: 'Zamknij informację',
                                  en: 'Close reference'))),
                        ]))),
          KeyedSubtree(
            key: const ValueKey('fume-intro'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.warning_amber_outlined,
              text: context.tr(
                  pl: 'Dym spawalniczy — także ze stali węglowej — jest '
                      'rakotwórczy dla ludzi (IARC, grupa 1, od 2017 r.). '
                      'Ramię odciągu odstawione za daleko nic nie daje: '
                      'prędkość ssania spada mniej więcej z kwadratem '
                      'odległości. Policz, jak blisko musi być ssawka.',
                  en: 'Welding fume — mild steel fume too — causes cancer in '
                      'humans (IARC group 1, since 2017). An extraction arm '
                      'parked too far away does nothing: suction speed falls '
                      'roughly with the square of the distance. Work out how '
                      'close the hood must be.'),
            ),
          ),
          if (_corrupt)
            KeyedSubtree(
              key: const ValueKey('fume-store-corrupt'),
              child: QuoteNotice(
                color: kWarn,
                icon: Icons.restore,
                text: context.tr(
                    pl: 'Zapisane dane były uszkodzone — przywrócono wartości '
                        'domyślne tam, gdzie nie dało się ich odczytać. '
                        'Sprawdź pola.',
                    en: 'The saved data was damaged — defaults restored '
                        'where it could not be read. Check the fields.'),
              ),
            ),
          _materialSection(),
          _hazardSection(),
          _levSection(capture),
          _rpeSection(assessment),
          _checklistSection(),
          _verdictSection(assessment),
          _notesSection(),
          _sourcesSection(),
        ],
      ),
    );
  }

  Widget _caption(String text, {Key? key, Color color = kTextMut}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: color, height: 1.35)),
      );

  Widget _chip(String key, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );

  Widget _field(TextEditingController c, String label,
          {required Key key,
          required String unit,
          String? helper,
          String? error}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: (_) => _changed(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 4,
          errorText: error,
          errorMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Color _levelColor(FumeLevel l) => switch (l) {
        FumeLevel.ok => kPass,
        FumeLevel.caution => kWarn,
        FumeLevel.stop => kFail,
        FumeLevel.incomplete => kTextSec,
      };

  IconData _levelIcon(FumeLevel l) => switch (l) {
        FumeLevel.ok => Icons.check_circle_outline,
        FumeLevel.caution => Icons.warning_amber_outlined,
        FumeLevel.stop => Icons.block,
        FumeLevel.incomplete => Icons.edit_outlined,
      };

  // ── Materiał i proces ──────────────────────────────────────────────────

  Widget _materialSection() {
    return QuoteSection(
      key: const ValueKey('fume-material-section'),
      title: context.tr(pl: 'Materiał i proces', en: 'Material and process'),
      children: [
        Text(context.tr(pl: 'Materiał', en: 'Material'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in FumeMaterial.values)
            _chip('fume-mat-${m.name}', m.label(en: _en), _material == m,
                () => _changed(() => _material = m)),
        ]),
        const SizedBox(height: 12),
        Text(context.tr(pl: 'Proces', en: 'Process'),
            style: const TextStyle(fontSize: 13, color: kTextSec)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in FumeProcess.values)
            _chip('fume-proc-${p.name}', p.label(en: _en), _process == p,
                () => _setProcess(p)),
        ]),
        if (_process != null)
          _caption(
              _en
                  ? fumeProcessNote(_process!).$2
                  : fumeProcessNote(_process!).$1,
              key: const ValueKey('fume-proc-note')),
      ],
    );
  }

  // ── Zagrożenia ─────────────────────────────────────────────────────────

  String _ndsText(FumeAgent a) => fumeNdsText(a, en: _en);

  Widget _hazardSection() {
    final m = _material;
    final p = _process;
    final children = <Widget>[];
    if (m == null || p == null) {
      children.add(KeyedSubtree(
        key: const ValueKey('fume-hazards-prompt'),
        child: QuoteNotice(
          color: kTextSec,
          icon: Icons.edit_outlined,
          text: context.tr(
              pl: 'Wybierz materiał i proces — pokażę, co jest w dymie, '
                  'z NDS.',
              en: 'Pick the material and the process — I will show what is '
                  'in the fume, with Polish OELs.'),
        ),
      ));
    } else {
      final hazards = fumeHazards(m, p);
      for (final h in hazards) {
        final a = h.agent;
        children.add(Padding(
          key: ValueKey('fume-agent-${a.name}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  h.emphasised
                      ? '${a.title(en: _en)} — ${context.tr(pl: 'szczególnie tu', en: 'especially here')}'
                      : a.title(en: _en),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: h.emphasised ? kFail : kText)),
              const SizedBox(height: 4),
              Text(a.effect(en: _en),
                  style: const TextStyle(
                      fontSize: 13, color: kTextSec, height: 1.4)),
              const SizedBox(height: 4),
              CopyOnLongPress(
                value: _ndsText(a),
                label: a.title(en: _en),
                child: Text(_ndsText(a),
                    key: ValueKey('fume-nds-${a.name}'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: kText,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
              ),
            ],
          ),
        ));
      }
      final agents = hazards.map((h) => h.agent).toSet();
      if (agents.contains(FumeAgent.crVI)) {
        children.add(KeyedSubtree(
          key: const ValueKey('fume-crvi-note'),
          child: QuoteNotice(
            color: kWarn,
            icon: Icons.history_edu_outlined,
            text: context.tr(pl: kFumeCrViNotePl, en: kFumeCrViNoteEn),
          ),
        ));
      }
      if (agents.contains(FumeAgent.cd)) {
        children.add(_caption(context.tr(pl: kFumeCdNotePl, en: kFumeCdNoteEn),
            key: const ValueKey('fume-cd-note')));
      }
      if (agents.contains(FumeAgent.pb)) {
        children.add(_caption(context.tr(pl: kFumePbNotePl, en: kFumePbNoteEn),
            key: const ValueKey('fume-pb-note')));
      }
    }
    return QuoteSection(
      key: const ValueKey('fume-hazards'),
      title: context.tr(pl: 'Co jest w dymie', en: 'What is in the fume'),
      subtitle: context.tr(pl: kFumeNdsLegalPl, en: kFumeNdsLegalEn),
      children: children,
    );
  }

  // ── Odciąg ─────────────────────────────────────────────────────────────

  String? _openingError(List<FumeCaptureProblem> p, double? v) {
    if (v == null) return null;
    if (!v.isFinite || v <= 0) {
      return context.tr(
          pl: 'Wpisz liczbę większą od 0.', en: 'Enter a number above 0.');
    }
    if (_lengthUnit.toM(v) > kFumeMaxOpeningM + kFumeEps) {
      return context.tr(
          pl: 'Za dużo — najwyżej ${_n(_lengthUnit.fromM(kFumeMaxOpeningM))} '
              '${_lengthUnit.symbol}. Sprawdź jednostkę.',
          en: 'Too large — at most '
              '${_n(_lengthUnit.fromM(kFumeMaxOpeningM))} '
              '${_lengthUnit.symbol}. Check the unit.');
    }
    return null;
  }

  Widget _levSection(FumeCaptureResult? r) {
    final children = <Widget>[
      Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(
            'fume-lev-present',
            context.tr(pl: 'Jest odciąg u źródła', en: 'Extraction at source'),
            _lev == FumeLevStatus.present,
            () => _changed(() => _lev = FumeLevStatus.present)),
        _chip(
            'fume-lev-absent',
            context.tr(pl: 'Brak odciągu', en: 'No extraction'),
            _lev == FumeLevStatus.absent,
            () => _changed(() => _lev = FumeLevStatus.absent)),
      ]),
    ];
    if (_lev == null) {
      children.add(_caption(context.tr(
          pl: 'Ssawka, ramię odciągowe, uchwyt z odciągiem, stół z odciągiem.',
          en: 'Hood, extraction arm, on-torch extraction, downdraft table.')));
    } else if (_lev == FumeLevStatus.absent) {
      children.add(const SizedBox(height: 10));
      children.add(KeyedSubtree(
        key: const ValueKey('fume-lev-absent-notice'),
        child: QuoteNotice(
          color: kFail,
          icon: Icons.block,
          text: context.tr(
              pl: 'Bez odciągu u źródła ocena nie będzie zielona. HSE (2019): '
                  'każde spawanie w pomieszczeniu, także stali węglowej, '
                  'wymaga środków technicznych — zwykle odciągu u źródła; '
                  'ochrona dróg oddechowych uzupełnia odciąg, gdy sam nie '
                  'wystarcza, a na zewnątrz, gdzie odciąg nie działa, jest '
                  'potrzebna zawsze. Minimum ŚOI bez odciągu: P3 albo TH3.',
              en: 'Without extraction at source the result will not be '
                  'green. HSE (2019): all indoor welding, mild steel '
                  'included, needs engineering control — usually extraction '
                  'at source; RPE adds to it where extraction alone is not '
                  'enough, and outdoors, where extraction does not work, it '
                  'is always needed. Minimum RPE without extraction: P3 or '
                  'TH3.'),
        ),
      ));
    } else {
      children.addAll(_calculator(r));
    }
    return QuoteSection(
      key: const ValueKey('fume-lev-section'),
      title: context.tr(pl: 'Odciąg u źródła', en: 'Extraction at source'),
      subtitle: context.tr(
          pl: 'Równanie DallaValle: Q = V·(10·X² + A); z kołnierzem '
              'Q = ${_n(kFumeFlangeFactor)}·V·(10·X² + A). Ważne do X ≤ '
              '${_n(kFumeDallaValleMaxXOverD, decimals: 1)}·D.',
          en: 'DallaValle equation: Q = V·(10·X² + A); flanged '
              'Q = ${_n(kFumeFlangeFactor)}·V·(10·X² + A). Valid up to '
              'X ≤ ${_n(kFumeDallaValleMaxXOverD, decimals: 1)}·D.'),
      children: children,
    );
  }

  List<Widget> _calculator(FumeCaptureResult? r) {
    final input = _captureInput;
    final problems = fumeCaptureProblems(input);
    final minV = fumeCaptureMinFor(_process);
    final grinding = _process == FumeProcess.grinding;
    final lu = _lengthUnit.symbol;
    String? flowError;
    if (problems.contains(FumeCaptureProblem.flowInvalid)) {
      flowError = context.tr(
          pl: 'Wpisz liczbę większą od 0.', en: 'Enter a number above 0.');
    } else if (problems.contains(FumeCaptureProblem.flowTooHigh)) {
      flowError = context.tr(
          pl: 'Za dużo — sprawdź liczbę i jednostkę.',
          en: 'Too high — check the number and unit.');
    }
    String? velocityError;
    if (problems.contains(FumeCaptureProblem.velocityBelowMin)) {
      velocityError = context.tr(
          pl: 'Nie mniej niż ${_n(minV)} m/s — próg można tylko podnieść.',
          en: 'Not below ${_n(minV)} m/s — the limit can only be raised.');
    } else if (problems.contains(FumeCaptureProblem.velocityInvalid) ||
        problems.contains(FumeCaptureProblem.velocityMissing)) {
      velocityError = context.tr(
          pl: 'Podaj prędkość uchwycenia (co najmniej ${_n(minV)} m/s).',
          en: 'Enter the capture velocity (at least ${_n(minV)} m/s).');
    } else if (problems.contains(FumeCaptureProblem.velocityTooHigh)) {
      velocityError = context.tr(
          pl: 'Za dużo — najwyżej ${_n(kFumeMaxCaptureMs)} m/s.',
          en: 'Too high — at most ${_n(kFumeMaxCaptureMs)} m/s.');
    }
    String? distanceError;
    if (problems.contains(FumeCaptureProblem.distanceInvalid)) {
      distanceError = context.tr(
          pl: 'Wpisz liczbę większą od 0.', en: 'Enter a number above 0.');
    } else if (problems.contains(FumeCaptureProblem.distanceTooFar)) {
      distanceError = context.tr(
          pl: 'Za daleko — najwyżej ${_n(_lengthUnit.fromM(kFumeMaxDistanceM))} '
              '$lu.',
          en: 'Too far — at most ${_n(_lengthUnit.fromM(kFumeMaxDistanceM))} '
              '$lu.');
    }
    final range = grinding ? kFumeGrindingRangeMs : kFumeWeldingRangeMs;

    final out = <Widget>[
      const SizedBox(height: 12),
      _field(
        _flow,
        context.tr(pl: 'Wydajność odciągu Q', en: 'Extraction airflow Q'),
        key: const ValueKey('fume-flow'),
        unit: _flowUnit.symbol,
        helper: context.tr(
            pl: 'Z tabliczki albo karty urządzenia — rzeczywista przy '
                'ssawce jest zwykle niższa (długie ramię, zapchany filtr).',
            en: 'From the rating plate or data sheet — the real flow at the '
                'hood is usually lower (long arm, clogged filter).'),
        error: flowError,
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final u in FumeFlowUnit.values)
          _chip('fume-flow-unit-${u.name}', u.symbol, _flowUnit == u,
              () => _setFlowUnit(u)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(
            'fume-shape-round',
            context.tr(pl: 'Otwór okrągły', en: 'Round opening'),
            _shape == FumeHoodShape.round,
            () => _changed(() => _shape = FumeHoodShape.round)),
        _chip(
            'fume-shape-rectangular',
            context.tr(pl: 'Prostokątny', en: 'Rectangular'),
            _shape == FumeHoodShape.rectangular,
            () => _changed(() => _shape = FumeHoodShape.rectangular)),
        for (final u in FumeLengthUnit.values)
          _chip('fume-len-${u.name}', u.symbol, _lengthUnit == u,
              () => _setLengthUnit(u)),
      ]),
      const SizedBox(height: 10),
      if (_shape == FumeHoodShape.round)
        _field(
          _diameter,
          context.tr(pl: 'Średnica otworu ssawki D', en: 'Hood opening Ø D'),
          key: const ValueKey('fume-diameter'),
          unit: lu,
          helper: context.tr(
              pl: 'Wylot ssawki (lejka), nie rury ramienia.',
              en: 'The hood mouth, not the arm duct.'),
          error: _openingError(problems, _read(_diameter)),
        )
      else ...[
        _field(
          _width,
          context.tr(pl: 'Szerokość otworu', en: 'Opening width'),
          key: const ValueKey('fume-width'),
          unit: lu,
          error: _openingError(problems, _read(_width)),
        ),
        const SizedBox(height: 10),
        _field(
          _height,
          context.tr(pl: 'Wysokość otworu', en: 'Opening height'),
          key: const ValueKey('fume-height'),
          unit: lu,
          error: _openingError(problems, _read(_height)),
        ),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _chip('fume-flange-no', context.tr(pl: 'Bez kołnierza', en: 'Plain'),
            !_flanged, () => _changed(() => _flanged = false)),
        _chip('fume-flange-yes', context.tr(pl: 'Z kołnierzem', en: 'Flanged'),
            _flanged, () => _changed(() => _flanged = true)),
      ]),
      _caption(context.tr(
          pl: 'Kołnierz — płaska kryza wokół otworu, szeroka mniej więcej '
              'na √A (przy okrągłej ok. 0,9·D); odcina zasysanie zza ssawki, '
              'więc ta sama wydajność sięga dalej (ok. 25 % mniej powietrza '
              'na tę samą odległość, ACGIH).',
          en: 'Flange — a flat rim around the opening, about √A wide (for a '
              'round one about 0.9·D); it stops air being drawn from behind, '
              'so the same airflow reaches further (about 25 % less air for '
              'the same distance, ACGIH).')),
      const SizedBox(height: 12),
      _field(
        _velocity,
        context.tr(pl: 'Prędkość uchwycenia V', en: 'Capture velocity V'),
        key: const ValueKey('fume-velocity'),
        unit: 'm/s',
        helper: grinding
            ? context.tr(
                pl: 'Szlifowanie: ${_n(range.$1)}–${_n(range.$2)} m/s '
                    '(ACGIH). Nie mniej niż ${_n(minV)}.',
                en: 'Grinding: ${_n(range.$1)}–${_n(range.$2)} m/s (ACGIH). '
                    'Not below ${_n(minV)}.')
            : context.tr(
                pl: 'Spawanie: ${_n(range.$1)}–${_n(range.$2)} m/s (ACGIH). '
                    'Przeciąg, otwarta brama, praca na zewnątrz — bliżej '
                    '${_n(range.$2)}. Nie mniej niż ${_n(minV)}.',
                en: 'Welding: ${_n(range.$1)}–${_n(range.$2)} m/s (ACGIH). '
                    'Draughts, an open door, outdoors — nearer '
                    '${_n(range.$2)}. Not below ${_n(minV)}.'),
        error: velocityError,
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final v in [range.$1, range.$2])
          ActionChip(
            key: ValueKey('fume-vel-${v.toStringAsFixed(1)}'),
            label: Text('${_n(v)} m/s'),
            onPressed: () => _changed(() {
              _velocity.text = _fmtField(v);
              _velocityRaised = false;
            }),
          ),
      ]),
      if (_velocityRaised)
        _caption(
            context.tr(
                pl: 'Prędkość podniesiona do minimum dla tego procesu.',
                en: 'Velocity raised to the minimum for this process.'),
            key: const ValueKey('fume-vel-raised'),
            color: kWarn),
      const SizedBox(height: 12),
      _field(
        _distance,
        context.tr(
            pl: 'Odległość ssawki od łuku X — teraz, na stanowisku',
            en: 'Hood-to-arc distance X — now, at the workplace'),
        key: const ValueKey('fume-distance'),
        unit: lu,
        helper: context.tr(
            pl: 'Zmierz, jak daleko ssawka stoi od łuku. Bez tego nie ma '
                'oceny — sam zasięg to tylko informacja.',
            en: 'Measure how far the hood is from the arc. Without it there '
                'is no verdict — the reach alone is just information.'),
        error: distanceError,
      ),
      const SizedBox(height: 12),
    ];
    if (r == null) {
      out.add(KeyedSubtree(
        key: const ValueKey('fume-capture-prompt'),
        child: QuoteNotice(
          color: kTextSec,
          icon: Icons.edit_outlined,
          text: context.tr(
              pl: 'Podaj wymiar otworu, prędkość, wydajność i odległość '
                  'ssawki od łuku — wtedy ocenię odciąg.',
              en: 'Enter the opening size, velocity, airflow and the '
                  'hood-to-arc distance to check the extraction.'),
        ),
      ));
      return out;
    }
    out.addAll(_captureResult(r));
    return out;
  }

  List<Widget> _captureResult(FumeCaptureResult r) {
    final out = <Widget>[];
    final limitCm = r.validityLimitCm;
    final dp = r.distanceProblem;
    if (dp != null) {
      final far = dp == FumeCaptureProblem.distanceTooFar;
      out.add(KeyedSubtree(
        key: const ValueKey('fume-distance-problem'),
        child: QuoteNotice(
          color: far ? kFail : kWarn,
          icon: far ? Icons.block : Icons.edit_outlined,
          text: far
              ? context.tr(
                  pl: 'Ssawka tak daleko od łuku nie łapie dymu — przysuń ją. '
                      'Ocena: STOP.',
                  en: 'A hood that far from the arc does not catch the fume '
                      '— move it closer. Verdict: STOP.')
              : context.tr(
                  pl: 'Odległość nieczytelna — popraw pole X. Bez niej odciąg '
                      'nie jest sprawdzony.',
                  en: 'The distance cannot be read — fix field X. Without it '
                      'the extraction is not checked.'),
        ),
      ));
    }
    if (r.isSlot) {
      out.add(KeyedSubtree(
        key: const ValueKey('fume-slot'),
        child: QuoteNotice(
          color: kWarn,
          icon: Icons.warning_amber_outlined,
          text: context.tr(
              pl: 'Otwór to szczelina (krótszy bok mniej niż '
                  '${_n(kFumeMinAspectRatio)} dłuższego) — równanie DallaValle '
                  'jej nie obejmuje. Wyniku nie podaję; użyj danych '
                  'producenta ssawki szczelinowej.',
              en: 'The opening is a slot (short side under '
                  '${_n(kFumeMinAspectRatio)} of the long side) — the '
                  'DallaValle equation does not cover it. No result; use '
                  'the slot hood maker’s data.'),
        ),
      ));
      return out;
    }
    final state = r.reachState;
    if (state != null) {
      if (state == FumeReachState.tooLowFlow) {
        out.add(KeyedSubtree(
          key: const ValueKey('fume-flow-too-low'),
          child: QuoteNotice(
            color: kFail,
            icon: Icons.block,
            text: context.tr(
                pl: 'Wydajność za mała — nawet tuż przy ssawce prędkość nie '
                    'osiąga ${_n(r.velocityMs)} m/s. Większy odciąg albo '
                    'mniejszy otwór.',
                en: 'Airflow too low — even right at the hood the speed does '
                    'not reach ${_n(r.velocityMs)} m/s. A bigger extractor or '
                    'a smaller opening.'),
          ),
        ));
      } else {
        out.add(Readout(
          key: const ValueKey('fume-reach'),
          label: context.tr(
              pl: 'Ssawka najdalej od łuku', en: 'Hood at most from the arc'),
          value: '${r.safeReachCm}',
          unit: context.tr(
              pl: 'cm · V ≥ ${_n(r.velocityMs)} m/s',
              en: 'cm · V ≥ ${_n(r.velocityMs)} m/s'),
          hot: true,
        ));
        out.add(const SizedBox(height: 10));
        if (state == FumeReachState.beyondValidity) {
          out.add(KeyedSubtree(
            key: const ValueKey('fume-out-of-range'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.warning_amber_outlined,
              text: context.tr(
                  pl: 'Poza zakresem równania — przyjmij bliżej. Równanie '
                      'daje ${r.reachCm} cm, ale jest wiarygodne tylko do '
                      '${_n(kFumeDallaValleMaxXOverD, decimals: 1)}·D = '
                      '$limitCm cm. Trzymaj ssawkę nie dalej niż $limitCm cm.',
                  en: 'Outside the equation’s range — keep it closer. The '
                      'equation gives ${r.reachCm} cm, but it holds only up to '
                      '${_n(kFumeDallaValleMaxXOverD, decimals: 1)}·D = '
                      '$limitCm cm. Keep the hood within $limitCm cm.'),
            ),
          ));
        } else {
          out.add(KeyedSubtree(
            key: const ValueKey('fume-capture-howto'),
            child: QuoteNotice(
              color: kTextSec,
              icon: Icons.info_outline,
              text: context.tr(
                  pl: 'Trzymaj ssawkę nie dalej niż ${r.safeReachCm} cm od '
                      'łuku i przesuwaj ją razem z pracą — dalej dym ucieka '
                      'obok.',
                  en: 'Keep the hood within ${r.safeReachCm} cm of the arc '
                      'and move it along with the work — further away the '
                      'fume escapes past it.'),
            ),
          ));
        }
        final oneD = fumeFloorCm(r.characteristicM);
        if ((r.safeReachCm ?? 0) > oneD) {
          out.add(_caption(
              context.tr(
                  pl: 'HSE (HSG258, WL3): w praktyce okap zwykle nie dalej '
                      'niż jedna jego średnica od spoiny — tu ok. $oneD cm.',
                  en: 'HSE (HSG258, WL3): in practice the hood is normally '
                      'no further than one hood diameter from the weld — '
                      'here about $oneD cm.'),
              key: const ValueKey('fume-hse-one-d')));
        }
        if (r.distanceMissing) {
          out.add(KeyedSubtree(
            key: const ValueKey('fume-distance-needed'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.straighten,
              text: context.tr(
                  pl: 'Podaj odległość ssawki od łuku (pole X) — sam zasięg '
                      'nie mówi, czy ssawka stoi dość blisko. Do tego czasu '
                      'odciąg liczy się jako niesprawdzony.',
                  en: 'Enter the hood-to-arc distance (field X) — the reach '
                      'alone does not say whether the hood is close enough. '
                      'Until then the extraction counts as unchecked.'),
            ),
          ));
        }
      }
    }
    final need = r.requiredFlowDisplay(_flowUnit);
    if (need != null) {
      final xText = _n(_lengthUnit.fromM(r.distanceM!));
      out.add(_kv(
          context.tr(
              pl: 'Potrzebna wydajność na $xText ${_lengthUnit.symbol}',
              en: 'Airflow needed at $xText ${_lengthUnit.symbol}'),
          '≥ $need ${_flowUnit.symbol}',
          valueKey: 'fume-required-flow'));
      final vx = r.velocityAtDistanceDisplay;
      if (vx != null) {
        out.add(_kv(
            context.tr(
                pl: 'Prędkość przy łuku z Twoją wydajnością',
                en: 'Speed at the arc with your airflow'),
            '${_n(vx)} m/s',
            valueKey: 'fume-velocity-at'));
      }
      if (r.distanceWithinValidity == false) {
        out.add(_caption(
            context.tr(
                pl: 'Odległość poza zakresem równania '
                    '(> ${_n(kFumeDallaValleMaxXOverD, decimals: 1)}·D = '
                    '$limitCm cm) — przysuń ssawkę; wymagana wydajność to '
                    'tylko szacunek.',
                en: 'Distance outside the equation’s range '
                    '(> ${_n(kFumeDallaValleMaxXOverD, decimals: 1)}·D = '
                    '$limitCm cm) — move the hood closer; the airflow '
                    'needed is only an estimate.'),
            key: const ValueKey('fume-distance-out-of-range'),
            color: kWarn));
      }
      final ok = r.flowSufficient;
      if (ok != null) {
        final level = r.level;
        out.add(const SizedBox(height: 8));
        out.add(KeyedSubtree(
          key: const ValueKey('fume-capture-verdict'),
          child: QuoteNotice(
            color: _levelColor(level),
            icon: _levelIcon(level),
            text: ok
                ? (level == FumeLevel.ok
                    ? context.tr(
                        pl: 'Wydajność wystarcza na tę odległość.',
                        en: 'The airflow is enough for this distance.')
                    : context.tr(
                        pl: 'Wydajność wystarcza wg równania, ale odległość '
                            'jest poza jego zakresem — przyjmij bliżej.',
                        en: 'The airflow is enough per the equation, but '
                            'the distance is outside its range — keep it '
                            'closer.'))
                : context.tr(
                    pl: 'Za mało powietrza na tę odległość — przysuń '
                        'ssawkę albo zwiększ wydajność do ≥ $need '
                        '${_flowUnit.symbol}.',
                    en: 'Not enough air for this distance — move the hood '
                        'closer or raise the airflow to ≥ $need '
                        '${_flowUnit.symbol}.'),
          ),
        ));
      }
    }
    if (_process?.gasShielded ?? false) {
      out.add(KeyedSubtree(
        key: const ValueKey('fume-shield-note'),
        child: QuoteNotice(
          color: r.shieldDraughtRisk ? kFail : kWarn,
          icon: Icons.air,
          text: r.shieldDraughtRisk
              ? context.tr(
                  pl: 'Przy łuku ok. ${_n(r.velocityAtDistanceDisplay!)} m/s '
                      '— ponad ${_n(kFumeShieldDraughtMs, decimals: 1)} m/s. '
                      'ACGIH: powyżej 0,5–1,0 m/s ciąg może zakłócać osłonę '
                      'gazową; HSE RR683: porowatość od ok. 1 m/s przy '
                      'niekorzystnych parametrach. Odsuń ssawkę na bok albo '
                      'zmniejsz wydajność tak, by zasięg wciąż sięgał łuku, i sprawdź '
                      'spoinę próbną.',
                  en: 'About ${_n(r.velocityAtDistanceDisplay!)} m/s at the '
                      'arc — over ${_n(kFumeShieldDraughtMs, decimals: 1)} '
                      'm/s. ACGIH: above 0.5–1.0 m/s the draught may disturb '
                      'the gas shield; HSE RR683: porosity from about 1 m/s '
                      'with unfavourable settings. Move the hood to the side '
                      'or reduce the airflow while keeping the reach, and check '
                      'a trial weld.')
              : context.tr(
                  pl: 'MIG/MAG, drut proszkowy, TIG: za silny ciąg tuż przy '
                      'łuku zdmuchuje osłonę gazową (porowatość). Ustaw '
                      'ssawkę z boku lub z tyłu, nieco powyżej — ma łapać '
                      'dym, a nie dmuchać na jeziorko; sprawdź spoinę próbną.',
                  en: 'MIG/MAG, flux-cored, TIG: too strong a draught right '
                      'at the arc blows the gas shield away (porosity). Put '
                      'the hood to the side or behind, slightly above — it '
                      'should catch the fume, not blow on the pool; check a '
                      'trial weld.'),
        ),
      ));
    }
    return out;
  }

  // ── Ochrona dróg oddechowych ───────────────────────────────────────────

  Widget _rpeSection(FumeAssessment a) {
    final req = a.requirement;
    final m = _material;
    final hazards = (m != null && _process != null)
        ? fumeHazards(m, _process!).map((h) => h.agent).toSet()
        : <FumeAgent>{};
    final gases = hazards.intersection(
        {FumeAgent.o3, FumeAgent.nox, FumeAgent.co, FumeAgent.coatingOrganics});
    final children = <Widget>[
      KeyedSubtree(
        key: const ValueKey('fume-hierarchy'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, (pl, en)) in kFumeHierarchy.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${i + 1}. ${_en ? en : pl}',
                    style: const TextStyle(
                        fontSize: 13, color: kTextSec, height: 1.4)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in FumeRpe.values)
          _chip('fume-rpe-${r.name}', r.label(en: _en), _rpe == r,
              () => _changed(() => _rpe = r)),
      ]),
      const SizedBox(height: 10),
    ];
    if (req == null) {
      children.add(_caption(
          context.tr(
              pl: 'Wybierz materiał — pokażę minimum ochrony.',
              en: 'Pick the material — I will show the minimum protection.'),
          key: const ValueKey('fume-rpe-min')));
    } else {
      final minText = req == FumeRpeRequirement.p3OrTh3
          ? context.tr(
              pl: 'co najmniej P3 (FFP3 / półmaska + P3) albo TH3',
              en: 'at least P3 (FFP3 / half mask + P3) or TH3')
          : context.tr(
              pl: 'APF co najmniej 20 — FFP3 / półmaska + P3, TH2 albo TH3',
              en: 'APF at least 20 — FFP3 / half mask + P3, TH2 or TH3');
      final why = m!.highHazard
          ? context.tr(
              pl: 'materiał z rakotwórczymi lub szczególnie toksycznymi '
                  'składnikami — razem z odciągiem u źródła, nie zamiast',
              en: 'material with carcinogenic or especially toxic '
                  'components — together with extraction, not instead')
          : a.levEffective
              ? context.tr(
                  pl: 'odciąg sprawdzony — ŚOI na dym resztkowy; HSE: APF '
                      'co najmniej 20 dla spawacza',
                  en: 'extraction checked — RPE for the residual fume; HSE: '
                      'APF at least 20 for welders')
              : context.tr(
                  pl: 'bez sprawdzonego odciągu u źródła',
                  en: 'without checked extraction at source');
      final meets = _rpe == null ? null : fumeRpeMeets(_rpe!, req);
      children.add(KeyedSubtree(
        key: const ValueKey('fume-rpe-min'),
        child: QuoteNotice(
          color: meets == null
              ? kTextSec
              : meets
                  ? kPass
                  : kFail,
          icon: meets == null
              ? Icons.masks_outlined
              : meets
                  ? Icons.check_circle_outline
                  : Icons.block,
          text: [
            context.tr(
                pl: 'Minimum: $minText ($why).',
                en: 'Minimum: $minText ($why).'),
            if (meets == true)
              context.tr(
                  pl: 'Wybrany sprzęt spełnia minimum.',
                  en: 'The chosen equipment meets the minimum.'),
            if (meets == false)
              context.tr(
                  pl: 'Wybrany sprzęt NIE spełnia minimum.',
                  en: 'The chosen equipment does NOT meet the minimum.'),
          ].join(' '),
        ),
      ));
    }
    if (_rpe == FumeRpe.th1 || _rpe == FumeRpe.p2) {
      children.add(_caption(
          context.tr(
              pl: 'FFP2 / P2 i TH1 mają APF 10 (HSE), a TH1 w DGUV 112-190 '
                  'tylko 5 i nie wolno go stosować przy substancjach '
                  'rakotwórczych — za mało przy spawaniu.',
              en: 'FFP2 / P2 and TH1 have APF 10 (HSE); DGUV 112-190 gives '
                  'TH1 only 5 and bars it against carcinogens — not enough '
                  'for welding.'),
          key: const ValueKey('fume-low-rpe-note'),
          color: kWarn));
    }
    if (_rpe?.tightFitting ?? false) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
            context.tr(
                pl: 'Czas w masce bez przerwy dłuższy niż 1 h?',
                en: 'More than 1 h in the mask without a break?'),
            key: const ValueKey('fume-wear-question'),
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: kText)),
      ));
      children.add(Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(
            'fume-wear-short',
            context.tr(pl: 'Nie — do 1 h', en: 'No — up to 1 h'),
            _longWear == false,
            () => _changed(() => _longWear = false)),
        _chip(
            'fume-wear-long',
            context.tr(pl: 'Tak — dłużej', en: 'Yes — longer'),
            _longWear == true,
            () => _changed(() => _longWear = true)),
      ]));
      if (_longWear == true) {
        children.add(const SizedBox(height: 8));
        children.add(KeyedSubtree(
          key: const ValueKey('fume-wear-long-notice'),
          child: QuoteNotice(
            color: kWarn,
            icon: Icons.timer_outlined,
            text: context.tr(
                pl: 'HSE: FFP3 / półmaska P3 — do ok. godziny pracy. Na '
                    'dłuższą pracę przyłbica spawalnicza z nawiewem TH2 albo '
                    'TH3 (APF co najmniej 20) — nie trzeba jej szczelnie '
                    'dopasowywać i nie męczy jak maska.',
                en: 'HSE: FFP3 / P3 half mask — for up to about an hour. For '
                    'longer work a powered welding helmet TH2 or TH3 (APF at '
                    'least 20) — it needs no tight fit and is less tiring than '
                    'a mask.'),
          ),
        ));
      } else {
        children.add(_caption(
            context.tr(
                pl: 'HSE: FFP3 / półmaska P3 — do ok. godziny pracy; dłużej '
                    'sprzęt z nawiewem (TH2/TH3).',
                en: 'HSE: FFP3 / P3 half mask — for up to about an hour; '
                    'longer, powered equipment (TH2/TH3).'),
            key: const ValueKey('fume-p3-note')));
      }
    }
    if (gases.isNotEmpty) {
      children.add(KeyedSubtree(
        key: const ValueKey('fume-gas-note'),
        child: QuoteNotice(
          color: kWarn,
          icon: Icons.cloud_outlined,
          text: context.tr(
              pl: 'Ozon, tlenki azotu, CO i opary z powłok to gazy — filtry '
                  'przeciwpyłowe (P2, P3, TH z filtrem P) ich nie zatrzymują. '
                  'Chroni odciąg i wentylacja; w ciasnym miejscu — sprzęt '
                  'z doprowadzeniem powietrza. Bez zaznaczenia punktu '
                  '„Gazy … ujęte odciągiem i wentylacją” na liście nie ma '
                  'zieleni.',
              en: 'Ozone, nitrogen oxides, CO and coating vapours are gases '
                  '— particle filters (P2, P3, TH with a P filter) do not '
                  'stop them. Extraction and ventilation protect; in a tight '
                  'space — air-fed equipment. No green until the checklist '
                  'item “Gases … removed by extraction and ventilation” is '
                  'ticked.'),
        ),
      ));
    }
    children.add(_apfTable());
    children.add(_caption(context.tr(pl: kFumeApfNotePl, en: kFumeApfNoteEn),
        key: const ValueKey('fume-apf-note')));
    return QuoteSection(
      key: const ValueKey('fume-rpe-section'),
      title: context.tr(
          pl: 'Ochrona dróg oddechowych', en: 'Respiratory protection'),
      subtitle: context.tr(
          pl: 'Kolejność środków — ŚOI są ostatnie, nie pierwsze:',
          en: 'Order of measures — RPE comes last, not first:'),
      children: children,
    );
  }

  Widget _apfTable() {
    TextStyle head = const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w800, color: kTextSec);
    TextStyle cell = const TextStyle(
        fontSize: 13,
        color: kText,
        fontFeatures: [FontFeature.tabularFigures()]);
    Widget row(String a, String b, String c, TextStyle s, {Key? key}) =>
        Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: Text(a, style: s)),
              Expanded(
                  flex: 2,
                  child: Text(b, style: s, textAlign: TextAlign.right)),
              Expanded(
                  flex: 2,
                  child: Text(c, style: s, textAlign: TextAlign.right)),
            ],
          ),
        );
    String v(int? x) => x == null ? '—' : '$x';
    return Padding(
      key: const ValueKey('fume-apf'),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(context.tr(pl: 'Sprzęt', en: 'Equipment'), 'HSE', 'DGUV', head),
          for (final r in kFumeApf)
            row(r.rpe.label(en: _en), v(r.hse), v(r.dguv), cell,
                key: ValueKey('fume-apf-${r.rpe.name}')),
        ],
      ),
    );
  }

  // ── Lista kontrolna ────────────────────────────────────────────────────

  FumeCheckContext get _checkCtx =>
      FumeCheckContext(material: _material, process: _process, rpe: _rpe);

  void _toggleCheck(FumeCheck c) {
    final s = fumeCheckState(c, _checks, _checkCtx);
    setState(() {
      _touched = true;
      _checks[c.id] =
          s == FumeCheckState.done ? FumeCheckState.open : FumeCheckState.done;
    });
  }

  void _toggleNa(FumeCheck c) {
    if (!c.naAllowed || fumeNaBlock(c, _checkCtx) != null) return;
    final s = fumeCheckState(c, _checks, _checkCtx);
    setState(() {
      _touched = true;
      _checks[c.id] = s == FumeCheckState.notApplicable
          ? FumeCheckState.open
          : FumeCheckState.notApplicable;
    });
  }

  Widget _checklistSection() {
    final ctx = _checkCtx;
    final open = fumeOpenChecks(_checks, ctx).length;
    final total = kFumeChecks.length;
    final children = <Widget>[
      Text(
        context.tr(
            pl: 'Otwarte: $open z $total. Niezaznaczony punkt to NIE „OK”. '
                'Lista nie jest zapisywana — sprawdzasz na każdym stanowisku.',
            en: 'Open: $open of $total. An unticked item is NOT “OK”. The '
                'list is not saved — check it at every workplace.'),
        key: const ValueKey('fume-check-count'),
        style: TextStyle(
            fontSize: 12.5,
            color: open == 0 ? kPass : kWarn,
            fontWeight: FontWeight.w700,
            height: 1.35),
      ),
      const SizedBox(height: 10),
    ];
    for (final g in FumeCheckGroup.values) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(g.label(en: _en),
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800, color: kText)),
      ));
      for (final c in fumeChecksIn(g)) {
        final s = fumeCheckState(c, _checks, ctx);
        final block = c.naAllowed ? fumeNaBlock(c, ctx) : null;
        children.add(_FumeCheckTile(
          check: c,
          checked: s == FumeCheckState.done,
          na: s == FumeCheckState.notApplicable,
          en: _en,
          naBlockedReason: block == null ? null : _naBlockText(block),
          onToggle: () => _toggleCheck(c),
          onNa: () => _toggleNa(c),
        ));
      }
    }
    return QuoteSection(
      key: const ValueKey('fume-checklist'),
      title: context.tr(
          pl: 'Lista kontrolna stanowiska', en: 'Workplace checklist'),
      children: children,
    );
  }

  String _naBlockText(FumeNaBlock b) => switch (b) {
        FumeNaBlock.coatedMaterial => context.tr(
            pl: '„nie dotyczy” niedostępne: wybrany materiał ma powłokę, '
                'ocynk albo nieznany skład',
            en: '“not applicable” unavailable: the chosen material is '
                'coated, galvanised or of unknown composition'),
        FumeNaBlock.notPowered => context.tr(
            pl: '„nie dotyczy” niedostępne: wybrany sprzęt to nie przyłbica '
                'z nawiewem',
            en: '“not applicable” unavailable: the chosen equipment is not '
                'a powered helmet'),
        FumeNaBlock.gasHazard => context.tr(
            pl: '„nie dotyczy” niedostępne: przy tym materiale i procesie '
                'powstają gazy',
            en: '“not applicable” unavailable: this material and process '
                'give off gases'),
      };

  // ── Ocena ──────────────────────────────────────────────────────────────

  String _reasonText(FumeReason r, FumeAssessment a) => switch (r.code) {
        FumeReasonCode.materialMissing =>
          context.tr(pl: 'Nie wybrano materiału.', en: 'No material chosen.'),
        FumeReasonCode.processMissing =>
          context.tr(pl: 'Nie wybrano procesu.', en: 'No process chosen.'),
        FumeReasonCode.levUnknown => context.tr(
            pl: 'Nie zaznaczono, czy jest odciąg u źródła.',
            en: 'Not stated whether there is extraction at source.'),
        FumeReasonCode.levAbsent => context.tr(
            pl: 'Brak odciągu u źródła — bez niego nigdy zielono.',
            en: 'No extraction at source — never green without it.'),
        FumeReasonCode.captureUnverified => context.tr(
            pl: 'Zasięg ssawki niesprawdzony — uzupełnij kalkulator '
                '(wydajność i wymiar otworu).',
            en: 'Hood reach not checked — fill in the calculator (airflow '
                'and opening size).'),
        FumeReasonCode.captureDistanceMissing => context.tr(
            pl: 'Podaj odległość ssawki od łuku — sam zasięg to nie '
                'potwierdzenie.',
            en: 'Enter the hood-to-arc distance — the reach alone is no '
                'confirmation.'),
        FumeReasonCode.captureDistanceInvalid => context.tr(
            pl: 'Odległość ssawki od łuku nieczytelna — popraw pole X.',
            en: 'The hood-to-arc distance cannot be read — fix field X.'),
        FumeReasonCode.captureDistanceTooFar => context.tr(
            pl: 'Ssawka za daleko od łuku — nie łapie dymu.',
            en: 'Hood too far from the arc — it does not catch the fume.'),
        FumeReasonCode.captureInsufficient => context.tr(
            pl: 'Odciąg za słaby albo za daleko od łuku.',
            en: 'Extraction too weak or too far from the arc.'),
        FumeReasonCode.captureOutOfRange => context.tr(
            pl: 'Wynik odciągu poza zakresem równania — przyjmij bliżej.',
            en: 'Extraction result outside the equation’s range — keep it '
                'closer.'),
        FumeReasonCode.rpeMissing => context.tr(
            pl: 'Nie wybrano ochrony dróg oddechowych.',
            en: 'No respiratory protection chosen.'),
        FumeReasonCode.rpeTooWeak => context.tr(
            pl: 'Ochrona dróg oddechowych poniżej minimum dla tego '
                'materiału.',
            en: 'Respiratory protection below the minimum for this '
                'material.'),
        FumeReasonCode.gasHazard => context.tr(
            pl: 'Gazy (ozon, tlenki azotu, CO, opary z powłok) — filtr P3 ich '
                'nie zatrzymuje; potwierdź na liście, że ujmuje je odciąg '
                'i wentylacja.',
            en: 'Gases (ozone, nitrogen oxides, CO, coating vapours) — a P3 '
                'filter does not stop them; confirm on the checklist that '
                'extraction and ventilation remove them.'),
        FumeReasonCode.wearTimeUnknown => context.tr(
            pl: 'Nie podano, czy maska jest noszona dłużej niż 1 h bez '
                'przerwy.',
            en: 'Not stated whether the mask is worn for more than 1 h '
                'without a break.'),
        FumeReasonCode.wearTooLong => context.tr(
            pl: 'Maska przylegająca ponad 1 h bez przerwy — HSE: na dłuższą '
                'pracę przyłbica z nawiewem TH2/TH3.',
            en: 'Tight-fitting mask for over 1 h without a break — HSE: for '
                'longer work a powered helmet TH2/TH3.'),
        FumeReasonCode.checklistOpen => context.tr(
            pl: 'Lista kontrolna: ${a.openChecks.length} punktów otwartych.',
            en: 'Checklist: ${a.openChecks.length} items open.'),
      };

  Widget _verdictSection(FumeAssessment a) {
    final level = a.level;
    final title = switch (level) {
      FumeLevel.ok => context.tr(pl: 'OK', en: 'OK'),
      FumeLevel.caution => context.tr(pl: 'OSTROŻNIE', en: 'CAUTION'),
      FumeLevel.stop => context.tr(pl: 'STOP', en: 'STOP'),
      FumeLevel.incomplete => context.tr(pl: 'UZUPEŁNIJ', en: 'INCOMPLETE'),
    };
    final summary = switch (level) {
      FumeLevel.ok => context.tr(
          pl: 'Odciąg sprawdzony, ŚOI spełnia minimum, lista kompletna — '
              'w zakresie, który aplikacja umie ocenić. Filtr P3 i nawiew '
              'z filtrem P chronią przed cząstkami dymu, nie przed gazami — '
              'gazy ujmuje odciąg i wentylacja. Pomiar stężeń w strefie '
              'oddychania rozstrzyga ostatecznie.',
          en: 'Extraction checked, RPE meets the minimum, checklist complete '
              '— as far as the app can judge. P3 filters and powered units '
              'with a P filter protect against fume particles, not gases — '
              'extraction and ventilation remove the gases. Breathing-zone '
              'measurements have the final word.'),
      FumeLevel.caution => context.tr(
          pl: 'Nie zielono — popraw to, co niżej.',
          en: 'Not green — fix what is listed below.'),
      FumeLevel.stop => context.tr(
          pl: 'Nie spawaj tak — ochrona nie wystarcza.',
          en: 'Do not weld like this — the protection is not enough.'),
      FumeLevel.incomplete => context.tr(
          pl: 'Brak danych to nie „OK” — uzupełnij.',
          en: 'Missing data is not “OK” — fill it in.'),
    };
    final color = _levelColor(level);
    return QuoteSection(
      key: const ValueKey('fume-verdict'),
      title: context.tr(pl: 'Ocena stanowiska', en: 'Workplace assessment'),
      children: [
        Row(children: [
          Icon(_levelIcon(level), color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                key: const ValueKey('fume-verdict-level'),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(summary,
            key: const ValueKey('fume-verdict-summary'),
            style: const TextStyle(fontSize: 13, color: kTextSec, height: 1.4)),
        const SizedBox(height: 8),
        for (final r in a.reasons)
          Padding(
            key: ValueKey('fume-reason-${r.code.name}'),
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_levelIcon(r.level),
                    size: 16, color: _levelColor(r.level)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_reasonText(r, a),
                      style: const TextStyle(
                          fontSize: 13, color: kText, height: 1.35)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Uwagi i źródła ─────────────────────────────────────────────────────

  Widget _note(String key, String title, String body) => Padding(
        key: ValueKey(key),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 4),
            Text(body,
                style: const TextStyle(
                    fontSize: 13, color: kTextSec, height: 1.4)),
          ],
        ),
      );

  Widget _notesSection() {
    return QuoteSection(
      key: const ValueKey('fume-notes'),
      title: context.tr(pl: 'Ważne', en: 'Important'),
      children: [
        _note(
          'fume-note-recirc',
          context.tr(
              pl: 'Recyrkulacja i klasy filtrów W1–W3',
              en: 'Recirculation and W1–W3 filter classes'),
          context.tr(pl: kFumeRecircNotePl, en: kFumeRecircNoteEn),
        ),
        _note(
          'fume-note-confined',
          context.tr(pl: 'Przestrzeń zamknięta', en: 'Confined space'),
          context.tr(
              pl: 'Zbiornik, kanał, wnętrze kadłuba albo skrzyni: dym '
                  'i gazy osłonowe zbierają się, a tlenu ubywa. Najpierw '
                  'moduł „Przestrzeń zamknięta: wejście i spawanie” (Spawacz '
                  '→ Kontrola i dokumentacja): pozwolenie, pomiar O₂/DGW/CO, '
                  'asekuracja, nawiew — dopiero potem ten ekran.',
              en: 'Tank, sewer, inside a hull or box section: fume and '
                  'shielding gas build up and oxygen runs short. First the '
                  '“Confined space: entry and welding” module (Welder → '
                  'Inspection and records): permit, O₂/LEL/CO readings, '
                  'attendant, forced air — only then this screen.'),
        ),
        _note(
          'fume-note-measure',
          context.tr(
              pl: 'Kalkulator to nie pomiar',
              en: 'A calculator is not a measurement'),
          context.tr(
              pl: 'Równanie zakłada spokojne powietrze i ssawkę w osi łuku. '
                  'Przeciąg, ruch rąk, gorąca smuga dymu i zapchany filtr '
                  'zmieniają wynik. Skuteczność potwierdza pomiar przepływu '
                  'przy ssawce i pomiar stężeń w strefie oddychania.',
              en: 'The equation assumes still air and the hood in line with '
                  'the arc. Draughts, arm movement, the hot plume and a '
                  'clogged filter change the result. Effectiveness is '
                  'confirmed by measuring airflow at the hood and '
                  'breathing-zone concentrations.'),
        ),
      ],
    );
  }

  Widget _sourcesSection() {
    return QuoteSection(
      key: const ValueKey('fume-sources'),
      title: context.tr(pl: 'Źródła', en: 'Sources'),
      subtitle: context.tr(
          pl: 'Orientacyjnie — wiąże ocena ryzyka zawodowego, instrukcja '
              'stanowiska i przepisy.',
          en: 'Guidance only — the occupational risk assessment, the '
              'workplace instruction and the law are binding.'),
      children: [
        for (final (i, s) in kFumeSources.indexed)
          Padding(
            key: ValueKey('fume-source-$i'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(s.label(en: _en),
                style: const TextStyle(
                    fontSize: 12, color: kTextSec, height: 1.4)),
          ),
      ],
    );
  }

  Widget _kv(String k, String v, {String? valueKey}) => CopyOnLongPress(
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(v,
                    key: valueKey == null ? null : ValueKey(valueKey),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kText,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );
}

/// Punkt listy: cały wiersz przełącza „zrobione”, osobny przycisk „n/d”
/// tylko przy punktach, które na to pozwalają.
class _FumeCheckTile extends StatelessWidget {
  const _FumeCheckTile({
    required this.check,
    required this.checked,
    required this.na,
    required this.en,
    required this.onToggle,
    required this.onNa,
    this.naBlockedReason,
  });

  final FumeCheck check;
  final bool checked;
  final bool na;
  final bool en;
  final VoidCallback onToggle;
  final VoidCallback onNa;

  /// „Nie dotyczy” przeczy wyborom na ekranie — przycisk nieaktywny,
  /// pod punktem wyjaśnienie.
  final String? naBlockedReason;

  @override
  Widget build(BuildContext context) {
    final borderColor = checked
        ? kPass.withValues(alpha: 0.6)
        : na
            ? kTextMut.withValues(alpha: 0.5)
            : kBorder;
    final hint = na ? check.naHint(en: en) : naBlockedReason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          checked: checked,
          child: InkWell(
            key: ValueKey('fume-check-${check.id}'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    Icon(
                      na
                          ? Icons.indeterminate_check_box_outlined
                          : checked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                      size: 30,
                      color: checked
                          ? kPass
                          : na
                              ? kTextSec
                              : kTextMut,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            check.label(en: en),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: checked || na ? kTextSec : kText,
                              decoration:
                                  na ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (hint != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(hint,
                                  style: const TextStyle(
                                      fontSize: 12, color: kTextSec)),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              check.source,
                              style: const TextStyle(
                                  fontSize: 11.5, color: kTextMut),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (check.naAllowed)
                      TextButton(
                        key: ValueKey('fume-na-${check.id}'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                          foregroundColor: naBlockedReason != null
                              ? kTextMut.withValues(alpha: 0.6)
                              : na
                                  ? kArc
                                  : kTextSec,
                        ),
                        // Zablokowane „n/d” nadal przejmuje dotknięcie
                        // (wyłączony przycisk przepuściłby je do wiersza
                        // i zaznaczył punkt) — i tylko wyjaśnia blokadę.
                        onPressed: naBlockedReason == null
                            ? onNa
                            : () => ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                  SnackBar(content: Text(naBlockedReason!))),
                        child: Text(en ? 'n/a' : 'n/d'),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
