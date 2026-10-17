// Gięcie rurek giętarką ręczną: ile uciąć i gdzie zaznaczyć gięcia, żeby po
// gięciu wymiary do punktów przecięcia osi się zgadzały. Dla montera rurek
// pomiarowych / hydrauliki (6–25 mm, 1/4"–1"), który dotąd liczył na kartce
// i wyrzucał drogą nierdzewkę.
//
// Trzy tryby: jedno gięcie, odsadzka (także przestrzenna) i rurka z wieloma
// gięciami. Matematyka: lib/domain/fitter/tube_bending.dart (czysty Dart,
// z testami). Ostatnia rurka zostaje w SharedPreferences
// (tube_bending_store.dart).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/fitter/tube_bending.dart';
import '../../domain/quotes/quote_calculator.dart' show formatQty;
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'tube_bending_store.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef TubeShareText = Future<void> Function(String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

class TubeBendingPage extends StatefulWidget {
  const TubeBendingPage({
    super.key,
    this.shareText = _defaultShareText,
    this.store = const TubeBendingStore(),
  });

  final TubeShareText shareText;
  final TubeBendingStore store;

  @override
  State<TubeBendingPage> createState() => _TubeBendingPageState();
}

/// Pole długości: tekst w bieżącej jednostce i wartość kanoniczna w mm.
/// `mm == null` — pole puste; `NaN` — tekst nieczytelny.
class _LenField {
  _LenField([this.mm]);

  final TextEditingController controller = TextEditingController();
  double? mm;
}

/// Wynik bieżącego trybu.
class _Outcome {
  final List<String> problems;
  final TubeRunResult? run;
  final TubeOffsetResult? offset;
  const _Outcome({this.problems = const [], this.run, this.offset});
}

class _TubeBendingPageState extends State<TubeBendingPage> {
  TubeBendingMode _mode = TubeBendingMode.multi;
  bool _inch = false;

  // Długości: wartość kanoniczna w mm ([_LenField.mm]) zmienia się TYLKO
  // przy edycji pola. Przełączenie mm ↔ cale przepisuje sam tekst — wynik
  // i zapis się nie zmieniają, choćby przełączać w kółko.

  // Giętarka. Domyślnie CLR 38 mm (giętarka do rurki 12 mm / 1/2").
  final _clr = _LenField(38);
  final _minStraight = _LenField();
  final _markerOffset = _LenField();
  final _springback = TextEditingController();

  // Jedno gięcie.
  final _sAngle = TextEditingController(text: '90');
  final _sA = _LenField(200);
  final _sB = _LenField(150);

  // Odsadzka.
  final _oH = _LenField(100);
  final _oSpread = _LenField();
  final _oAngle = TextEditingController(text: '45');
  final _oA = _LenField(200);
  final _oB = _LenField(200);

  // Wiele gięć: odcinki (n + 1), kąty i obroty (n).
  final List<_LenField> _segs = [
    for (final v in const [150.0, 200.0, 250.0, 120.0]) _LenField(v),
  ];
  final List<TextEditingController> _angles = [
    for (final v in const ['90', '45', '90']) TextEditingController(text: v),
  ];
  final List<TextEditingController> _rots = [
    for (var i = 0; i < 3; i++) TextEditingController(),
  ];

  bool _loaded = false;
  bool _touched = false;
  bool _readFailed = false;
  bool _damagedNotice = false;

  List<_LenField> get _lengthFields => [
        _clr,
        _minStraight,
        _markerOffset,
        _sA,
        _sB,
        _oH,
        _oSpread,
        _oA,
        _oB,
        ..._segs,
      ];

  @override
  void initState() {
    super.initState();
    for (final f in _lengthFields) {
      _show(f);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [
      for (final f in _lengthFields) f.controller,
      _springback,
      _sAngle,
      _oAngle,
      ..._angles,
      ..._rots,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Zapis i odczyt ───────────────────────────────────────────────────────

  Future<void> _load() async {
    final l = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _readFailed = l.readFailed;
      _damagedNotice = l.damaged && !_touched;
      final s = l.state;
      // Monter zaczął pisać, zanim odczyt się skończył — jego dane wygrywają.
      if (s != null && !_touched) _apply(s);
      _loaded = true;
    });
    // Edycja sprzed końca odczytu nie była zapisana (zapis czekał na
    // odczyt) — zapisz ją teraz, a nie dopiero przy następnej zmianie.
    if (_touched) await _save();
  }

  /// Kontrolery zdjęte z ekranu — pola trzymają je jeszcze w tej klatce.
  void _disposeLater(List<TextEditingController> cs) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in cs) {
        c.dispose();
      }
    });
  }

  /// Tekst pola długości z wartości kanonicznej w bieżącej jednostce
  /// (mm do 3 miejsc, cale do 4). Nieczytelny tekst (NaN) zostaje, jak
  /// go wpisano — monter ma go poprawić, nie zgubić.
  void _show(_LenField f) {
    final v = f.mm;
    if (v != null && v.isNaN) return;
    f.controller.text =
        v == null ? '' : numText(v / _scale, decimals: _inch ? 4 : 3);
  }

  /// Edycja pola długości: jedyne miejsce, które zmienia wartość kanoniczną.
  void _edited(_LenField f, String text) => _changed(() => f.mm =
      text.trim().isEmpty ? null : (parseDecimal(text) ?? double.nan) * _scale);

  String _deg2(double? v) => v == null || !v.isFinite ? '' : numText(v);

  void _apply(TubeBendingSaved s) {
    _mode = s.mode;
    _inch = s.unit == TubeUnit.inch;
    _clr.mm = s.clrMm;
    _minStraight.mm = s.minStraightMm;
    _markerOffset.mm = s.markerOffsetMm;
    _sA.mm = s.singleLegAMm;
    _sB.mm = s.singleLegBMm;
    _oH.mm = s.offsetHeightMm;
    _oSpread.mm = s.offsetSpreadMm;
    _oA.mm = s.offsetLegAMm;
    _oB.mm = s.offsetLegBMm;
    _springback.text = _deg2(s.springbackDeg);
    _sAngle.text = _deg2(s.singleAngleDeg);
    _oAngle.text = _deg2(s.offsetAngleDeg);
    _disposeLater([
      for (final f in _segs) f.controller,
      ..._angles,
      ..._rots,
    ]);
    _segs
      ..clear()
      ..addAll([for (final v in s.segmentsMm) _LenField(v)]);
    _angles
      ..clear()
      ..addAll([
        for (final v in s.anglesDeg) TextEditingController(text: _deg2(v)),
      ]);
    _rots
      ..clear()
      ..addAll([
        for (final v in s.rotationsDeg) TextEditingController(text: _deg2(v)),
      ]);
    for (final f in _lengthFields) {
      _show(f);
    }
  }

  double? _raw(TextEditingController c) => parseDecimal(c.text);

  TubeBendingSaved _snapshot() => TubeBendingSaved(
        mode: _mode,
        unit: _inch ? TubeUnit.inch : TubeUnit.mm,
        clrMm: _clr.mm,
        minStraightMm: _minStraight.mm,
        markerOffsetMm: _markerOffset.mm,
        springbackDeg: _raw(_springback),
        singleAngleDeg: _raw(_sAngle),
        singleLegAMm: _sA.mm,
        singleLegBMm: _sB.mm,
        offsetHeightMm: _oH.mm,
        offsetSpreadMm: _oSpread.mm,
        offsetAngleDeg: _raw(_oAngle),
        offsetLegAMm: _oA.mm,
        offsetLegBMm: _oB.mm,
        segmentsMm: [for (final f in _segs) f.mm],
        anglesDeg: [for (final c in _angles) _raw(c)],
        rotationsDeg: [for (final c in _rots) _raw(c)],
      );

  Future<void> _save() async {
    // Przed odczytem nie zapisujemy — nadpisalibyśmy zapis domyślnymi.
    if (!_loaded) return;
    final afterFailedRead = _readFailed;
    _readFailed = false;
    try {
      await widget.store.save(_snapshot(), afterFailedRead: afterFailedRead);
    } catch (e) {
      debugPrint('[tube_bending] save failed: $e');
    }
  }

  /// Każda zmiana pól: przelicz, schowaj komunikat o uszkodzonym zapisie,
  /// zapisz rurkę.
  void _changed([VoidCallback? f]) {
    setState(() {
      f?.call();
      _touched = true;
      _damagedNotice = false;
    });
    unawaited(_save());
  }

  // ── Jednostki i formatowanie ─────────────────────────────────────────────

  bool get _en => context.language == AppLanguage.en;
  double get _scale => _inch ? kMmPerInch : 1;
  String get _u => _inch ? 'in' : 'mm';
  TubeUnit get _unit => _inch ? TubeUnit.inch : TubeUnit.mm;

  String _num(double v, int d) {
    final s = formatQty(v, decimals: d);
    return _en ? s.replaceAll(',', '.') : s;
  }

  /// Wymiar geometryczny (bez zaokrąglania do kroku), bez jednostki.
  String _len(double mm) => _num(mm / _scale, _inch ? 3 : 2);
  String _lenU(double mm) => '${_len(mm)} $_u';

  /// Wartość zaokrąglona do kroku (0,5 mm / 1/32"), bez jednostki mm —
  /// w calach ułamek ze znakiem ".
  String _stepText(double roundedMm) =>
      _inch ? formatInchFraction(roundedMm / kMmPerInch) : _num(roundedMm, 1);
  String _stepU(double roundedMm) =>
      _inch ? _stepText(roundedMm) : '${_stepText(roundedMm)} mm';

  String _mark(double mm) => _stepU(roundMarkMm(mm, _unit));
  String _cut(TubeRunResult r) => _stepU(r.cutLengthMm(_unit));
  String _deg(double v) => '${_num(v, 1)}°';

  String get _stepName => _inch
      ? context.tr(pl: '1/32"', en: '1/32"')
      : context.tr(pl: '0,5 mm', en: '0.5 mm');

  /// Kanoniczna wartość pola w mm; puste → NaN (błąd), [optional] → 0.
  double _mmOf(_LenField f, {bool optional = false}) =>
      f.mm ?? (optional ? 0 : double.nan);

  double _degOf(TextEditingController c, {bool optional = false}) {
    if (optional && c.text.trim().isEmpty) return 0;
    return parseDecimal(c.text) ?? double.nan;
  }

  /// Zmienia tylko wyświetlanie: wartości kanoniczne w mm zostają.
  void _setUnit(bool inch) {
    if (inch == _inch) return;
    _changed(() {
      _inch = inch;
      for (final f in _lengthFields) {
        _show(f);
      }
    });
  }

  // ── Wejścia → domena ─────────────────────────────────────────────────────

  double get _clrMm => _mmOf(_clr);
  double get _minMm => _mmOf(_minStraight, optional: true);
  double get _offMm => _mmOf(_markerOffset, optional: true);
  double get _sbDeg => _degOf(_springback, optional: true);

  _Outcome _compute() {
    switch (_mode) {
      case TubeBendingMode.single:
        final i = TubeRunInput.single(
          clrMm: _clrMm,
          angleDeg: _degOf(_sAngle),
          legAMm: _mmOf(_sA),
          legBMm: _mmOf(_sB),
          minStraightMm: _minMm,
          markerOffsetMm: _offMm,
          springbackDeg: _sbDeg,
        );
        final p = i.problems;
        if (p.isNotEmpty) return _Outcome(problems: _texts(p));
        return _Outcome(run: computeTubeRun(i));
      case TubeBendingMode.offset:
        final i = TubeOffsetInput(
          clrMm: _clrMm,
          heightMm: _mmOf(_oH),
          spreadMm: _mmOf(_oSpread, optional: true),
          angleDeg: _degOf(_oAngle),
          legAMm: _mmOf(_oA),
          legBMm: _mmOf(_oB),
          minStraightMm: _minMm,
          markerOffsetMm: _offMm,
          springbackDeg: _sbDeg,
        );
        final p = i.problems;
        if (p.isNotEmpty) return _Outcome(problems: _texts(p));
        final r = computeTubeOffset(i);
        return _Outcome(offset: r, run: r?.run);
      case TubeBendingMode.multi:
        final i = TubeRunInput(
          clrMm: _clrMm,
          segmentsMm: [for (final c in _segs) _mmOf(c)],
          anglesDeg: [for (final c in _angles) _degOf(c)],
          rotationsDeg: [for (final c in _rots) _degOf(c, optional: true)],
          minStraightMm: _minMm,
          markerOffsetMm: _offMm,
          springbackDeg: _sbDeg,
        );
        final p = i.problems;
        if (p.isNotEmpty) return _Outcome(problems: _texts(p));
        return _Outcome(run: computeTubeRun(i));
    }
  }

  // ── Komunikaty ───────────────────────────────────────────────────────────

  List<String> _texts(List<TubeBendProblem> ps) =>
      {for (final p in ps) _problem(p)}.toList();

  String _segmentName(int index) => switch (_mode) {
        TubeBendingMode.single => index == 1
            ? context.tr(pl: 'Ramię A', en: 'Leg A')
            : context.tr(pl: 'Ramię B', en: 'Leg B'),
        TubeBendingMode.offset => index == 1
            ? context.tr(
                pl: 'Odcinek przed odsadzką', en: 'Length before the offset')
            : context.tr(
                pl: 'Odcinek za odsadzką', en: 'Length after the offset'),
        TubeBendingMode.multi =>
          context.tr(pl: 'Odcinek $index', en: 'Length $index'),
      };

  String _problem(TubeBendProblem p) => switch (p.kind) {
        TubeBendProblemKind.radius => context.tr(
            pl: 'Podaj promień gięcia po osi rurki CLR (z tabliczki lub '
                'instrukcji giętarki), większy od zera.',
            en: 'Enter the centreline bend radius CLR (from the bender plate '
                'or manual), greater than zero.'),
        TubeBendProblemKind.angle => _mode == TubeBendingMode.offset
            ? context.tr(
                pl: 'Kąt odsadzki: więcej niż 0° i najwyżej 90°.',
                en: 'Offset angle: more than 0° and at most 90°.')
            : context.tr(
                pl: '${_mode == TubeBendingMode.multi ? 'Gięcie ${p.index}: kąt' : 'Kąt'}'
                    ' gięcia od 0° do 180° (bez 0 i 180). Przy 180° (U) '
                    'nie ma punktu przecięcia osi — podaj kąt mniejszy.',
                en: '${_mode == TubeBendingMode.multi ? 'Bend ${p.index}: bend' : 'Bend'}'
                    ' angle between 0° and 180° (not 0 or 180). At 180° (U) '
                    'there is no centreline intersection — enter a smaller angle.'),
        TubeBendProblemKind.segment => context.tr(
            pl: '${_segmentName(p.index ?? 1)}: podaj długość większą od zera '
                '(do punktu przecięcia osi).',
            en: '${_segmentName(p.index ?? 1)}: enter a length greater than '
                'zero (to the centreline intersection).'),
        TubeBendProblemKind.minStraight => context.tr(
            pl: 'Minimalna prosta: liczba ≥ 0 (puste = bez sprawdzania).',
            en: 'Minimum straight: a number ≥ 0 (empty = not checked).'),
        TubeBendProblemKind.markerOffset => context.tr(
            pl: 'Przesunięcie znacznika: liczba, najwyżej ±1000 mm.',
            en: 'Marker offset: a number, at most ±1000 mm.'),
        TubeBendProblemKind.springback => context.tr(
            pl: 'Dogięcie na sprężynowanie: od 0° do 30°.',
            en: 'Springback overbend: 0° to 30°.'),
        TubeBendProblemKind.rotation => context.tr(
            pl: 'Gięcie ${p.index}: obrót musi być liczbą (puste = 0°).',
            en: 'Bend ${p.index}: the rotation must be a number (empty = 0°).'),
        TubeBendProblemKind.bendCount => context.tr(
            pl: 'Od 1 do $kMaxTubeBends gięć.',
            en: 'From 1 to $kMaxTubeBends bends.'),
        TubeBendProblemKind.offsetHeight => context.tr(
            pl: 'Podaj przesunięcie osi H większe od zera.',
            en: 'Enter an axis offset H greater than zero.'),
        TubeBendProblemKind.offsetSpread => context.tr(
            pl: 'Przesunięcie boczne: liczba ≥ 0 (puste = odsadzka płaska).',
            en: 'Side offset: a number ≥ 0 (empty = flat offset).'),
      };

  String _warning(TubeRunResult r, TubeBendWarning w) {
    final n = r.bends.length;
    final seg = w.kind == TubeBendWarningKind.markOutsideTube
        ? 0.0
        : r.input.segmentsMm[w.index - 1];
    final need = seg - w.straightMm;
    final name = _segmentName(w.index);
    return switch (w.kind) {
      TubeBendWarningKind.arcsOverlap => context.tr(
          pl: 'Łuki gięć ${w.index - 1} i ${w.index} zachodzą na siebie: '
              '${name.toLowerCase()} ma ${_lenU(seg)}, a potrzeba co najmniej '
              '${_lenU(need)} (suma odsunięć obu łuków). Takiej rurki nie da '
              'się wygiąć — wydłuż odcinek albo zmień kąt.',
          en: 'The arcs of bends ${w.index - 1} and ${w.index} overlap: '
              '${name.toLowerCase()} is ${_lenU(seg)}, at least ${_lenU(need)} '
              'is needed (both setbacks). This tube cannot be bent — lengthen '
              'it or change the angle.'),
      TubeBendWarningKind.arcPastEnd => context.tr(
          pl: 'Łuk gięcia ${w.index == 1 ? 1 : n} wychodzi poza koniec rurki: '
              '${name.toLowerCase()} ma ${_lenU(seg)}, a odsunięcie łuku to '
              '${_lenU(need)}. Wydłuż odcinek.',
          en: 'The arc of bend ${w.index == 1 ? 1 : n} runs past the tube end: '
              '${name.toLowerCase()} is ${_lenU(seg)}, the setback is '
              '${_lenU(need)}. Lengthen it.'),
      TubeBendWarningKind.straightTooShort => context.tr(
          pl: 'Prosta między gięciami ${w.index - 1} i ${w.index}: '
              '${_lenU(w.straightMm)} — mniej niż ${_lenU(w.requiredMm)} '
              'wymagane przez giętarkę.',
          en: 'Straight between bends ${w.index - 1} and ${w.index}: '
              '${_lenU(w.straightMm)} — less than the ${_lenU(w.requiredMm)} '
              'the bender needs.'),
      TubeBendWarningKind.endStraightTooShort => context.tr(
          pl: 'Prosta na ${w.index == 1 ? 'początku' : 'końcu'} rurki: '
              '${_lenU(w.straightMm)} — mniej niż ${_lenU(w.requiredMm)} '
              '(uchwyt giętarki, złączka). Zostaw dłuższy koniec i dotnij '
              'go po gięciu.',
          en: 'Straight at the ${w.index == 1 ? 'start' : 'end'} of the tube: '
              '${_lenU(w.straightMm)} — less than ${_lenU(w.requiredMm)} '
              '(bender grip, fitting). Leave the end longer and trim it '
              'after bending.'),
      TubeBendWarningKind.markOutsideTube => context.tr(
          pl: 'Znacznik gięcia ${w.index} wypada poza rurką '
              '(${_lenU(w.straightMm)}) — sprawdź przesunięcie znacznika.',
          en: 'The mark of bend ${w.index} falls outside the tube '
              '(${_lenU(w.straightMm)}) — check the marker offset.'),
    };
  }

  String _rotationText(double r) {
    if (r.abs() < 1e-9) {
      return context.tr(
          pl: 'bez obrotu (ta sama płaszczyzna i strona)',
          en: 'no rotation (same plane and side)');
    }
    if ((r - 180).abs() < 1e-9) {
      return context.tr(
          pl: 'obróć rurkę o 180° (gięcie w przeciwną stronę)',
          en: 'turn the tube 180° (bend the other way)');
    }
    return context.tr(
        pl: 'obróć rurkę o ${_deg(r)}', en: 'turn the tube ${_deg(r)}');
  }

  // ── Udostępnianie ────────────────────────────────────────────────────────

  String _shareTextOf(TubeRunResult r, TubeOffsetResult? o) {
    final b = StringBuffer();
    final i = r.input;
    b.writeln(context.tr(
        pl: 'Gięcie rurki — długość i znaczniki',
        en: 'Tube bending — length and marks'));
    b.writeln('CLR ${_lenU(i.clrMm)} · '
        '${context.tr(pl: 'gięć', en: 'bends')}: ${r.bends.length}');
    b.writeln(
        '${context.tr(pl: 'Odcinki do przecięcia osi', en: 'Lengths to centreline intersections')}: '
        '${i.segmentsMm.map(_len).join(' · ')} $_u');
    if (o != null) {
      b.writeln('${context.tr(pl: 'Odsadzka', en: 'Offset')} '
          '${_lenU(o.trueOffsetMm)} · ${_deg(o.input.angleDeg)} · '
          '${context.tr(pl: 'między gięciami', en: 'between bends')} '
          '${_lenU(o.travelMm)}');
    }
    b.writeln('${context.tr(pl: 'Długość cięcia', en: 'Cut length')}: '
        '${_cut(r)} (${context.tr(pl: 'dokładnie', en: 'exact')} '
        '${_lenU(r.developedMm)}; ${context.tr(pl: 'w górę do', en: 'rounded up to')} '
        '$_stepName)');
    b.writeln(context.tr(
        pl: 'Znaczniki od początku rurki (koniec A), '
            '${i.markerOffsetMm == 0 ? 'znacznik = początek łuku' : 'znacznik = początek łuku ${_signed(i.markerOffsetMm)}'}:',
        en: 'Marks from the tube start (end A), '
            '${i.markerOffsetMm == 0 ? 'mark = start of arc' : 'mark = start of arc ${_signed(i.markerOffsetMm)}'}:'));
    for (final m in r.bends) {
      final rot = m.number > 1 ? ', ${_rotationText(m.rotationDeg)}' : '';
      b.writeln('${m.number}. ${_deg(m.angleDeg)}$rot — '
          '${context.tr(pl: 'znacznik', en: 'mark')} ${_mark(m.markMm)} · '
          '${context.tr(pl: 'wierzchołek', en: 'vertex')} ${_mark(m.vertexMm)} · '
          '${context.tr(pl: 'środek łuku', en: 'middle of arc')} ${_mark(m.arcMiddleMm)} · '
          '${context.tr(pl: 'koniec łuku', en: 'end of arc')} ${_mark(m.arcEndMm)}'
          '${i.springbackDeg > 0 ? ' · ${context.tr(pl: 'gnij do', en: 'bend to')} ${_deg(m.bendToDeg)}' : ''}');
    }
    for (final w in r.warnings) {
      b.writeln('! ${_warning(r, w)}');
    }
    b.write(context.tr(
        pl: 'Długość cięcia zaokrąglona w górę, znaczniki do najbliższego $_stepName.',
        en: 'Cut length rounded up, marks to the nearest $_stepName.'));
    return b.toString();
  }

  String _signed(double mm) => mm >= 0 ? '+ ${_lenU(mm)}' : '− ${_lenU(-mm)}';

  Future<void> _share(String text) async {
    unawaited(Haptic.tap());
    try {
      await widget.shareText(
          text,
          context.tr(
              pl: 'Gięcie rurki — znaczniki', en: 'Tube bending — marks'));
    } catch (e) {
      debugPrint('[tube_bending] share failed: $e');
    }
  }

  // ── Budowa ekranu ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final out = _compute();
    final r = out.run;
    final shareable = out.problems.isEmpty && r != null && r.feasible;
    final share = shareable ? _shareTextOf(r, out.offset) : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Gięcie rurek', en: 'Tube bending')),
        actions: [
          IconButton(
            key: const ValueKey('tb-appbar-share'),
            tooltip: context.tr(pl: 'Udostępnij znaczniki', en: 'Share marks'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: share == null ? null : () => _share(share),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('tb-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (_damagedNotice)
            QuoteNotice(
              key: const ValueKey('tb-damaged'),
              text: context.tr(
                  pl: 'Zapis ostatniej rurki był uszkodzony — zaczynam od '
                      'wartości domyślnych. Kopia zapisu zostaje w pamięci '
                      'telefonu.',
                  en: 'The saved tube was damaged — starting from the '
                      'defaults. A copy of the save stays on the phone.'),
            ),
          _modeSection(),
          _benderSection(),
          ...switch (_mode) {
            TubeBendingMode.single => [_singleSection()],
            TubeBendingMode.offset => [_offsetSection()],
            TubeBendingMode.multi => [_multiSection()],
          },
          if (out.problems.isNotEmpty)
            QuoteNotice(
              key: const ValueKey('tb-problem'),
              color: kFail,
              icon: Icons.error_outline,
              text: out.problems.join('\n'),
            )
          else if (r != null) ...[
            if (r.warnings.isNotEmpty)
              QuoteNotice(
                key: const ValueKey('tb-warning'),
                color: r.feasible ? kWarn : kFail,
                icon: r.feasible
                    ? Icons.warning_amber_rounded
                    : Icons.error_outline,
                text: r.warnings.map((w) => _warning(r, w)).join('\n'),
              ),
            if (r.feasible) ...[
              _resultSection(r, out.offset),
              _marksSection(r),
              _orderSection(r),
              _referenceNotice(),
              FilledButton.icon(
                key: const ValueKey('tb-share'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: kArc,
                  foregroundColor: kOnArc,
                ),
                onPressed: share == null ? null : () => _share(share),
                icon: const Icon(Icons.share_outlined),
                label: Text(
                    context.tr(
                        pl: 'Udostępnij tabelę znaczników',
                        en: 'Share the marks table'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Wspólne pola ─────────────────────────────────────────────────────────

  /// Pole długości (mm / cale): edycja ustawia wartość kanoniczną w mm.
  Widget _lenField(_LenField f, String label,
          {required String key, String? helper, bool signed = false}) =>
      _numField(f.controller, label,
          key: key,
          helper: helper,
          signed: signed,
          onChanged: (t) => _edited(f, t));

  /// Pole niezależne od jednostki (kąty) — tekst jest wartością.
  Widget _numField(TextEditingController c, String label,
          {required String key,
          String? unit,
          String? helper,
          bool signed = false,
          ValueChanged<String>? onChanged}) =>
      TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: numberKeyboard(signed: signed),
        inputFormatters: numberInputFormatters(signed: signed),
        onChanged: onChanged ?? (_) => _changed(),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit ?? _u,
          helperText: helper,
          helperMaxLines: 4,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child:
            Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _angleChips(
          TextEditingController c, String prefix, List<int> values) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in values)
            ChoiceChip(
              key: ValueKey('$prefix-$a'),
              label: Text('$a°'),
              selected: parseDecimal(c.text) == a,
              onSelected: (_) => _changed(() => c.text = '$a'),
            ),
        ],
      );

  Widget _modeSection() {
    Widget chip(TubeBendingMode m, String pl, String en) => ChoiceChip(
          key: ValueKey('tb-mode-${m.name}'),
          label: Text(context.tr(pl: pl, en: en)),
          selected: _mode == m,
          onSelected: (_) => _changed(() => _mode = m),
        );
    return QuoteSection(
      title: context.tr(pl: 'Co gniesz', en: 'What you bend'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(TubeBendingMode.single, 'Jedno gięcie', 'Single bend'),
            chip(TubeBendingMode.offset, 'Odsadzka', 'Offset'),
            chip(TubeBendingMode.multi, 'Wiele gięć', 'Several bends'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(context.tr(pl: 'Jednostki:', en: 'Units:'),
                style: const TextStyle(color: kTextSec, fontSize: 13)),
            ChoiceChip(
              key: const ValueKey('tb-unit-mm'),
              label: const Text('mm'),
              selected: !_inch,
              onSelected: (_) => _setUnit(false),
            ),
            ChoiceChip(
              key: const ValueKey('tb-unit-in'),
              label: Text(context.tr(pl: 'cale', en: 'inches')),
              selected: _inch,
              onSelected: (_) => _setUnit(true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _benderSection() => QuoteSection(
        title: context.tr(pl: 'Giętarka', en: 'Bender'),
        children: [
          _lenField(
            _clr,
            context.tr(
                pl: 'Promień gięcia po osi CLR', en: 'Centreline radius CLR'),
            key: 'tb-clr',
            helper: context.tr(
                pl: 'Do osi rurki (nie wewnętrzny promień rolki) — z tabliczki '
                    'lub instrukcji giętarki.',
                en: 'To the tube centreline (not the inside die radius) — from '
                    'the bender plate or manual.'),
          ),
          const SizedBox(height: 12),
          _lenField(
            _minStraight,
            context.tr(
                pl: 'Minimalna prosta (uchwyt giętarki)',
                en: 'Minimum straight (bender grip)'),
            key: 'tb-min-straight',
            helper: context.tr(
                pl: 'Między gięciami i na końcach. Puste = bez sprawdzania.',
                en: 'Between bends and at the ends. Empty = not checked.'),
          ),
          const SizedBox(height: 12),
          _lenField(
            _markerOffset,
            context.tr(
                pl: 'Przesunięcie znacznika giętarki',
                en: 'Bender marker offset'),
            key: 'tb-marker-offset',
            signed: true,
            helper: context.tr(
                pl: 'Puste = znacznik na początku łuku. Wpisz z instrukcji '
                    'giętarki: + w stronę końca rurki, − w stronę początku.',
                en: 'Empty = mark at the start of the arc. Take it from the '
                    'bender manual: + towards the tube end, − towards the start.'),
          ),
          const SizedBox(height: 12),
          _numField(
            _springback,
            context.tr(
                pl: 'Dogięcie na sprężynowanie', en: 'Springback overbend'),
            key: 'tb-springback',
            unit: '°',
            helper: context.tr(
                pl: 'Informacyjnie: o tyle gnij dalej (zwykle 1–3°). Nie '
                    'zmienia długości cięcia ani znaczników.',
                en: 'For information: bend this much further (usually 1–3°). '
                    'Does not change the cut length or the marks.'),
          ),
        ],
      );

  Widget _singleSection() => QuoteSection(
        title: context.tr(pl: 'Jedno gięcie', en: 'Single bend'),
        subtitle: context.tr(
            pl: 'Ramiona mierzone do punktu przecięcia osi (wierzchołka).',
            en: 'Legs measured to the centreline intersection (vertex).'),
        children: [
          _angleChips(_sAngle, 'tb-s-angle', const [90, 45, 30, 60]),
          const SizedBox(height: 10),
          _numField(_sAngle, context.tr(pl: 'Kąt gięcia', en: 'Bend angle'),
              key: 'tb-s-angle', unit: '°'),
          const SizedBox(height: 12),
          _lenField(
              _sA,
              context.tr(
                  pl: 'Ramię A (od początku rurki)',
                  en: 'Leg A (from the tube start)'),
              key: 'tb-s-a'),
          const SizedBox(height: 12),
          _lenField(
              _sB,
              context.tr(
                  pl: 'Ramię B (do końca rurki)',
                  en: 'Leg B (to the tube end)'),
              key: 'tb-s-b'),
        ],
      );

  Widget _offsetSection() => QuoteSection(
        title: context.tr(pl: 'Odsadzka', en: 'Offset'),
        subtitle: context.tr(
            pl: 'Dwa gięcia o ten sam kąt w przeciwne strony. Z przesunięciem '
                'bocznym — odsadzka przestrzenna (jak „Rolling offset” dla rur).',
            en: 'Two bends of the same angle in opposite directions. With a '
                'side offset — a rolling offset (as in “Rolling offset” for pipe).'),
        children: [
          _lenField(
              _oH, context.tr(pl: 'Przesunięcie osi H', en: 'Axis offset H'),
              key: 'tb-o-h'),
          const SizedBox(height: 12),
          _lenField(
            _oSpread,
            context.tr(
                pl: 'Przesunięcie boczne (opcjonalnie)',
                en: 'Side offset (optional)'),
            key: 'tb-o-spread',
            helper: context.tr(
                pl: 'Prostopadle do H. Puste = odsadzka płaska.',
                en: 'Square to H. Empty = flat offset.'),
          ),
          _caption(context.tr(pl: 'Kąt gięć', en: 'Bend angle')),
          _angleChips(_oAngle, 'tb-o-angle', const [30, 45, 60]),
          const SizedBox(height: 10),
          _numField(_oAngle, context.tr(pl: 'Kąt odsadzki', en: 'Offset angle'),
              key: 'tb-o-angle', unit: '°'),
          const SizedBox(height: 12),
          _lenField(
              _oA,
              context.tr(
                  pl: 'Od początku rurki do gięcia 1',
                  en: 'Tube start to bend 1'),
              key: 'tb-o-a',
              helper: context.tr(
                  pl: 'Do punktu przecięcia osi.',
                  en: 'To the centreline intersection.')),
          const SizedBox(height: 12),
          _lenField(
              _oB,
              context.tr(
                  pl: 'Od gięcia 2 do końca rurki', en: 'Bend 2 to tube end'),
              key: 'tb-o-b'),
        ],
      );

  void _addBend() {
    if (_angles.length >= kMaxTubeBends) return;
    _changed(() {
      _angles.add(TextEditingController(text: '90'));
      _rots.add(TextEditingController());
      // Nowy odcinek: 100 mm albo 4" — okrągła liczba w bieżącej jednostce.
      final seg = _LenField(_inch ? 4 * kMmPerInch : 100);
      _show(seg);
      _segs.add(seg);
    });
  }

  void _removeBend(int k) {
    if (_angles.length <= 1) return;
    final removed = [
      _angles.removeAt(k),
      _rots.removeAt(k),
      _segs.removeAt(k + 1).controller,
    ];
    _changed();
    _disposeLater(removed);
  }

  Widget _multiSection() {
    final n = _angles.length;
    return QuoteSection(
      title: context.tr(
          pl: 'Rurka z wieloma gięciami', en: 'Tube with several bends'),
      subtitle: context.tr(
          pl: 'Odcinki jak na rysunku: do punktów przecięcia osi. Gięcia '
              'w jednej płaszczyźnie; obrót tylko informacyjnie.',
          en: 'Lengths as on the drawing: to the centreline intersections. '
              'Bends in one plane; the rotation is for information only.'),
      children: [
        _lenField(
            _segs[0],
            context.tr(
                pl: 'Odcinek 1: początek rurki → gięcie 1',
                en: 'Length 1: tube start → bend 1'),
            key: 'tb-seg-1'),
        for (var k = 0; k < n; k++) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _BendBadge(number: k + 1),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    context.tr(pl: 'Gięcie ${k + 1}', en: 'Bend ${k + 1}'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              if (n > 1)
                IconButton(
                  key: ValueKey('tb-remove-${k + 1}'),
                  tooltip: context.tr(
                      pl: 'Usuń gięcie ${k + 1}', en: 'Remove bend ${k + 1}'),
                  constraints: const BoxConstraints(
                      minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                  onPressed: () => _removeBend(k),
                  icon: const Icon(Icons.delete_outline, color: kTextSec),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _numField(_angles[k], context.tr(pl: 'Kąt', en: 'Angle'),
                    key: 'tb-angle-${k + 1}', unit: '°'),
              ),
              if (k > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _numField(
                      _rots[k], context.tr(pl: 'Obrót', en: 'Rotation'),
                      key: 'tb-rot-${k + 1}', unit: '°', signed: true),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _lenField(
              _segs[k + 1],
              k == n - 1
                  ? context.tr(
                      pl: 'Odcinek ${k + 2}: gięcie ${k + 1} → koniec rurki',
                      en: 'Length ${k + 2}: bend ${k + 1} → tube end')
                  : context.tr(
                      pl: 'Odcinek ${k + 2}: gięcie ${k + 1} → gięcie ${k + 2}',
                      en: 'Length ${k + 2}: bend ${k + 1} → bend ${k + 2}'),
              key: 'tb-seg-${k + 2}'),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('tb-add'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed: n >= kMaxTubeBends ? null : _addBend,
          icon: const Icon(Icons.add),
          label: Text(context.tr(
              pl: 'Dodaj gięcie (na końcu)', en: 'Add a bend (at the end)')),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
              pl: 'Obrót: o ile obrócić rurkę przed gięciem względem '
                  'poprzedniego (0° — ta sama strona, 180° — przeciwna). '
                  'Długości od niego nie zależą.',
              en: 'Rotation: how far to turn the tube before the bend relative '
                  'to the previous one (0° — same side, 180° — opposite). The '
                  'lengths do not depend on it.'),
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
      ],
    );
  }

  // ── Wyniki ───────────────────────────────────────────────────────────────

  Widget _kv(String k, String v, {String? key}) => CopyOnLongPress(
        key: key == null ? null : ValueKey(key),
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          // Wartość też się zawija — długie listy (proste po gięciu) na
          // wąskim ekranie z dużą czcionką nie mogą wypchnąć wiersza.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  flex: 3,
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(v,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _resultSection(TubeRunResult r, TubeOffsetResult? o) {
    final single = _mode == TubeBendingMode.single;
    final g = r.bends.first.geometry;
    return QuoteSection(
      title: context.tr(pl: 'Wynik', en: 'Result'),
      children: [
        Readout(
          key: const ValueKey('tb-cut'),
          label: context.tr(pl: 'Długość cięcia', en: 'Cut length'),
          value: _stepText(r.cutLengthMm(_unit)),
          unit: context.tr(
              pl: '${_inch ? 'cale' : 'mm'} · w górę do $_stepName',
              en: '${_inch ? 'inches' : 'mm'} · rounded up to $_stepName'),
          hot: true,
        ),
        const SizedBox(height: 12),
        _kv(context.tr(pl: 'Dokładnie', en: 'Exact'), _lenU(r.developedMm),
            key: 'tb-exact'),
        _kv(context.tr(pl: 'Suma odcinków', en: 'Sum of lengths'),
            _lenU(r.totalSegmentsMm),
            key: 'tb-sum'),
        _kv(context.tr(pl: 'Zysk z gięć (Σ gain)', en: 'Gain from bends (Σ)'),
            '− ${_lenU(r.totalGainMm)}',
            key: 'tb-gain-sum'),
        if (single) ...[
          _kv(context.tr(pl: 'Długość łuku', en: 'Arc length'), _lenU(g.arcMm),
              key: 'tb-arc'),
          _kv(context.tr(pl: 'Odsunięcie (setback)', en: 'Setback'),
              _lenU(g.setbackMm),
              key: 'tb-setback'),
          _kv(context.tr(pl: 'Zysk (gain)', en: 'Gain'), _lenU(g.gainMm),
              key: 'tb-gain'),
        ],
        if (o != null) ...[
          if (o.input.spreadMm > 0) ...[
            _kv(
                context.tr(
                    pl: 'Przesunięcie rzeczywiste √(H² + boczne²)',
                    en: 'True offset √(H² + side²)'),
                _lenU(o.trueOffsetMm),
                key: 'tb-o-true'),
            _kv(
                context.tr(
                    pl: 'Obrót płaszczyzny odsadzki od pionu',
                    en: 'Offset plane roll from vertical'),
                _deg(o.rollFromVerticalDeg),
                key: 'tb-o-roll'),
          ],
          _kv(
              context.tr(
                  pl: 'Między gięciami (po osi) = H / sin θ',
                  en: 'Between bends (centreline) = H / sin θ'),
              _lenU(o.travelMm),
              key: 'tb-o-travel'),
          _kv(
              context.tr(
                  pl: 'Postęp wzdłuż trasy', en: 'Advance along the run'),
              _lenU(o.advanceMm),
              key: 'tb-o-advance'),
          _kv(
              context.tr(
                  pl: 'Skrócenie trasy = H·tg(θ/2)',
                  en: 'Run shortening = H·tan(θ/2)'),
              _lenU(o.shrinkMm),
              key: 'tb-o-shrink'),
        ],
        _kv(context.tr(pl: 'Proste po gięciu', en: 'Straights after bending'),
            '${r.straightsMm.map(_len).join(' · ')} $_u',
            key: 'tb-straights'),
      ],
    );
  }

  Widget _marksSection(TubeRunResult r) {
    final off = r.input.markerOffsetMm;
    return QuoteSection(
      title: context.tr(pl: 'Znaczniki gięć', en: 'Bend marks'),
      subtitle: off == 0
          ? context.tr(
              pl: 'Od początku rurki (koniec A). Znacznik = początek łuku '
                  '(punkt styczności).',
              en: 'From the tube start (end A). Mark = start of the arc '
                  '(tangent point).')
          : context.tr(
              pl: 'Od początku rurki (koniec A). Znacznik = początek łuku '
                  '${_signed(off)} (przesunięcie giętarki).',
              en: 'From the tube start (end A). Mark = start of the arc '
                  '${_signed(off)} (bender offset).'),
      children: [
        for (final m in r.bends) _bendCard(r, m),
        _TubeSketch(key: const ValueKey('tb-sketch'), result: r),
        const SizedBox(height: 6),
        Text(
          context.tr(
              pl: 'Szkic w jednej płaszczyźnie: obrót 180° rysujemy jako '
                  'gięcie w przeciwną stronę, inne obroty — bez zmiany strony.',
              en: 'Sketch in one plane: a 180° rotation is drawn as a bend the '
                  'other way, other rotations without changing side.'),
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
      ],
    );
  }

  Widget _bendCard(TubeRunResult r, TubeBendMark m) {
    final g = m.geometry;
    return Padding(
      key: ValueKey('tb-mark-${m.number}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _BendBadge(number: m.number),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${context.tr(pl: 'Gięcie', en: 'Bend')} ${m.number} · '
                      '${_deg(m.angleDeg)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (m.number > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_rotationText(m.rotationDeg),
                      style: const TextStyle(fontSize: 12, color: kTextMut)),
                ),
              const SizedBox(height: 6),
              CopyOnLongPress(
                key: ValueKey('tb-mark-${m.number}-value'),
                value: _mark(m.markMm),
                label: context.tr(
                    pl: 'Znacznik gięcia ${m.number}',
                    en: 'Mark of bend ${m.number}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(context.tr(pl: 'Znacznik', en: 'Mark'),
                            style: const TextStyle(
                                fontSize: 13.5,
                                color: kText,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text(_mark(m.markMm),
                          style: const TextStyle(
                              fontSize: 18,
                              color: kArc,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
              ),
              _kv(
                  context.tr(
                      pl: 'Wierzchołek (przecięcie osi)',
                      en: 'Vertex (centreline intersection)'),
                  _mark(m.vertexMm)),
              _kv(context.tr(pl: 'Środek łuku', en: 'Middle of arc'),
                  _mark(m.arcMiddleMm)),
              _kv(context.tr(pl: 'Koniec łuku', en: 'End of arc'),
                  _mark(m.arcEndMm)),
              if (r.input.springbackDeg > 0)
                _kv(
                    context.tr(
                        pl: 'Gnij na giętarce do', en: 'Bend on the bender to'),
                    _deg(m.bendToDeg)),
              _kv(
                  context.tr(
                      pl: 'Łuk / odsunięcie / zysk',
                      en: 'Arc / setback / gain'),
                  '${_len(g.arcMm)} / ${_len(g.setbackMm)} / ${_len(g.gainMm)}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderSection(TubeRunResult r) {
    final steps = <String>[
      context.tr(
          pl: 'Utnij rurkę na ${_cut(r)} i oznacz koniec A — od niego mierzysz '
              'wszystkie znaczniki (zaznaczaj dookoła rurki).',
          en: 'Cut the tube to ${_cut(r)} and label end A — measure every mark '
              'from it (mark all round the tube).'),
      for (final m in r.bends)
        context.tr(
            pl: 'Gięcie ${m.number}: znacznik ${_mark(m.markMm)}'
                '${m.number > 1 ? ', ${_rotationText(m.rotationDeg)}' : ''}, '
                'gnij do ${_deg(m.bendToDeg)}.',
            en: 'Bend ${m.number}: mark ${_mark(m.markMm)}'
                '${m.number > 1 ? ', ${_rotationText(m.rotationDeg)}' : ''}, '
                'bend to ${_deg(m.bendToDeg)}.'),
      context.tr(
          pl: 'Gnij po kolei od końca A. Po każdym gięciu sprawdź taśmą wymiar '
              'do przecięcia osi — błąd poprawisz, zanim pójdzie dalej.',
          en: 'Bend in order from end A. After each bend check the dimension to '
              'the centreline intersection with a tape — fix an error before '
              'it carries on.'),
    ];
    return QuoteSection(
      title: context.tr(pl: 'Kolejność gięć', en: 'Bending order'),
      children: [
        for (final (i, s) in steps.indexed)
          Padding(
            key: ValueKey('tb-step-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${i + 1}.',
                      style: const TextStyle(
                          color: kTextSec, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                    child: Text(s,
                        style: const TextStyle(fontSize: 13.5, height: 1.35))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _referenceNotice() => QuoteNotice(
        key: const ValueKey('tb-reference'),
        text: context.tr(
            pl: 'Kreski giętarek nie są wspólne. Swagelok (MS-13-43, metoda '
                'Measure-Bend) ustawia pod kreską rolki dla danego kąta '
                'WIERZCHOŁEK — użyj wiersza „Wierzchołek”. RIDGID (instrukcja '
                'serii 300/400) dla 90° mierzy do osi drugiego ramienia (też '
                'wierzchołek), dla 45° do „Środka łuku”. Inne giętarki — wpisz '
                'przesunięcie z instrukcji albo zrób próbne gięcie na odpadzie. '
                'Tabele zysku producenta mogą różnić się od wzoru o 1–2 mm '
                '(promień nominalny ≠ rzeczywisty).',
            en: 'Bender marks are not standard. Swagelok (MS-13-43, '
                'Measure-Bend) lines the VERTEX up with the roll support mark '
                'for the angle — use the “Vertex” row. RIDGID (300/400 series '
                'sheet) measures to the centreline of the other leg at 90° '
                '(also the vertex) and to the “Middle of arc” at 45°. Other '
                'benders — enter the offset from the manual or make a test bend '
                'on scrap. Maker gain tables may differ from the formula by '
                '1–2 mm (nominal radius ≠ actual).'),
      );
}

class _BendBadge extends StatelessWidget {
  final int number;
  const _BendBadge({required this.number});

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: kArc, shape: BoxShape.circle),
        child: Text('$number',
            style: const TextStyle(
                color: kOnArc, fontWeight: FontWeight.w800, fontSize: 13)),
      );
}

/// Szkic rurki: proste i łuki CLR w jednej płaszczyźnie, numery gięć.
class _TubeSketch extends StatelessWidget {
  final TubeRunResult result;
  const _TubeSketch({super.key, required this.result});

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.6,
        child: CustomPaint(painter: _TubePainter(result)),
      );
}

class _TubePainter extends CustomPainter {
  final TubeRunResult r;
  _TubePainter(this.r);

  @override
  void paint(Canvas canvas, Size size) {
    final rad = r.input.clrMm;
    var p = Offset.zero;
    var heading = 0.0;
    var side = 1.0;
    final pts = <Offset>[p];
    final arcs = <List<Offset>>[];
    final labels = <(Offset, Offset)>[]; // środek łuku, kierunek na zewnątrz
    void straight(double len) {
      p = p + Offset(math.cos(heading), math.sin(heading)) * math.max(len, 0);
      pts.add(p);
    }

    for (final (k, b) in r.bends.indexed) {
      straight(r.straightsMm[k]);
      if (k > 0 && (b.rotationDeg - 180).abs() < 90) side = -side;
      final theta = b.angleDeg * math.pi / 180 * side;
      final normal = Offset(-math.sin(heading), math.cos(heading)) * side;
      final centre = p + normal * rad;
      final a0 = math.atan2(p.dy - centre.dy, p.dx - centre.dx);
      final arc = <Offset>[];
      const steps = 16;
      for (var s = 1; s <= steps; s++) {
        final a = a0 + theta * s / steps;
        arc.add(centre + Offset(math.cos(a), math.sin(a)) * rad);
      }
      final mid = a0 + theta / 2;
      final midPt = centre + Offset(math.cos(mid), math.sin(mid)) * rad;
      labels.add((midPt, (midPt - centre) / rad));
      arcs.add([p, ...arc]);
      pts.addAll(arc);
      p = arc.last;
      heading += theta;
    }
    straight(r.straightsMm.last);

    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final o in pts) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    const pad = 22.0;
    final s = math.min((size.width - 2 * pad) / math.max(maxX - minX, 1),
        (size.height - 2 * pad) / math.max(maxY - minY, 1));
    // Oś Y ekranu w dół — odwracamy.
    Offset map(Offset o) => Offset(
          pad +
              (o.dx - minX) * s +
              ((size.width - 2 * pad) - (maxX - minX) * s) / 2,
          size.height -
              pad -
              (o.dy - minY) * s -
              ((size.height - 2 * pad) - (maxY - minY) * s) / 2,
        );

    final tube = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = kTextSec;
    final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (final o in pts.skip(1)) {
      path.lineTo(map(o).dx, map(o).dy);
    }
    canvas.drawPath(path, tube);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = kArc;
    for (final a in arcs) {
      final ap = Path()..moveTo(map(a.first).dx, map(a.first).dy);
      for (final o in a.skip(1)) {
        ap.lineTo(map(o).dx, map(o).dy);
      }
      canvas.drawPath(ap, arcPaint);
    }

    void text(String t, Offset at, Color color, {Color? bg}) {
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      if (bg != null) {
        canvas.drawCircle(at, 10, Paint()..color = bg);
      }
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    for (final (k, (mid, out)) in labels.indexed) {
      // Ekranowy kierunek „na zewnątrz łuku” (Y odwrócone).
      final dir = Offset(out.dx, -out.dy);
      text('${k + 1}', map(mid) + dir * 16, kOnArc, bg: kArc);
    }
    final start = map(pts.first);
    canvas.drawCircle(start, 4, Paint()..color = kText);
    text('A', start + const Offset(0, -14), kText);
    text('B', map(pts.last) + const Offset(0, -14), kTextMut);
  }

  @override
  bool shouldRepaint(_TubePainter old) => old.r != r;
}
