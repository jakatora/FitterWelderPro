// Nośność spoiny pachwinowej (EN 1993-1-8): ile udźwignie spoina przy
// wsporniku, uchu, podporze i jakie a wystarczy dla danej siły. Metoda
// uproszczona (4.5.3.3) i kierunkowa (4.5.3.2), spoina liniowa albo obwodowa
// (rura do blachy). Logika i źródła: domain/welding/fillet_weld_strength.dart.
//
// Werdykt „wystarczy” tylko przy F_Ed ≤ F_Rd dokładnie; liczby obok werdyktu
// zaokrąglane na niekorzyść (F_Rd w dół, F_Ed / wykorzystanie / wymagane a
// w górę), więc nie przeczą kolorowi. Puste lub nieczytelne pole to
// komunikat, nie wynik.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/welding/fillet_weld_strength.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef FilletShareText = Future<void> Function(String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

/// Kierunek siły w metodzie kierunkowej (spoina liniowa).
enum _Direction { along, across, angle }

class FilletStrengthPage extends StatefulWidget {
  const FilletStrengthPage({super.key, this.shareText = _defaultShareText});

  final FilletShareText shareText;

  @override
  State<FilletStrengthPage> createState() => _FilletStrengthPageState();
}

class _FilletStrengthPageState extends State<FilletStrengthPage> {
  // Wspornik z blachy 10 mm na dwie spoiny a4 po 100 mm — typowy start.
  final _size = TextEditingController(text: '4');
  final _t = TextEditingController(text: '10');
  final _length = TextEditingController(text: '100');
  final _tube = TextEditingController(text: '60,3');
  final _angle = TextEditingController(text: '45');
  final _force = TextEditingController();

  WeldSteelGrade _steel = WeldSteelGrade.s235;

  /// true — pole wymiaru to bok z (a = z/√2), false — grubość a.
  bool _legMode = false;
  WeldLayout _layout = WeldLayout.linear;
  int _welds = 2;
  FilletMethod _method = FilletMethod.simplified;
  _Direction _direction = _Direction.across;
  ForceKind _forceKind = ForceKind.design;
  bool _sharing = false;

  @override
  void dispose() {
    for (final c in [_size, _t, _length, _tube, _angle, _force]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  String _n(double v, int d) => formatFixed(v, d, en: _en);
  String _v(double v) => formatInput(v, en: _en);

  /// Liczba z pola; puste albo nieczytelne → NaN (domena zgłosi problem).
  double _val(TextEditingController c) => parseDecimal(c.text) ?? double.nan;

  /// Grubość obliczeniowa a [mm] — WARTOŚĆ ŹRÓDŁOWA wymiaru spoiny. Zmienia
  /// ją tylko edycja pola ([_onSizeChanged]); przełączenie a ↔ z zmienia
  /// wyłącznie to, co pole pokazuje, więc a 4 zostaje 4 po dowolnej liczbie
  /// przełączeń. NaN — pole puste albo nieczytelne.
  double _throatMm = 4;

  void _onSizeChanged(String text) {
    final x = parseDecimal(text) ?? double.nan;
    setState(() => _throatMm = _legMode ? x / math.sqrt2 : x);
  }

  double get _angleDeg => switch (_direction) {
        _Direction.along => 0,
        _Direction.across => 90,
        _Direction.angle => _val(_angle),
      };

  FilletWeldInput get _input => FilletWeldInput(
        steel: _steel,
        throatMm: _throatMm,
        maxPartThicknessMm: _val(_t),
        layout: _layout,
        lengthMm: _val(_length),
        welds: _welds,
        tubeOdMm: _val(_tube),
        method: _method,
        angleDeg: _angleDeg,
      );

  /// Przełączenie a ↔ z: pole pokazuje wartość źródłową w nowym trybie
  /// (W DÓŁ do 0,01 mm), ale [_throatMm] się nie zmienia — zaokrąglenie
  /// pola nie wraca do obliczeń, dopóki użytkownik go nie edytuje.
  /// Programowa zmiana tekstu nie woła onChanged. Wołane wewnątrz setState.
  void _setLegMode(bool leg) {
    if (leg == _legMode) return;
    if (_throatMm.isFinite && _throatMm > 0) {
      _size.text = sizeFieldText(_throatMm, leg: leg, en: _en);
    }
    _legMode = leg;
  }

  // ── Komunikaty ─────────────────────────────────────────────────────────

  String _problemText(FilletProblem p, FilletWeldInput i) {
    switch (p) {
      case FilletProblem.throat:
        return _legMode
            ? context.tr(
                pl: 'Podaj długość boku spoiny z (> 0 mm).',
                en: 'Enter the weld leg length z (> 0 mm).')
            : context.tr(
                pl: 'Podaj grubość obliczeniową spoiny a (> 0 mm).',
                en: 'Enter the weld throat thickness a (> 0 mm).');
      case FilletProblem.throatBelowMin:
        final a = formatThroat(i.throatMm, en: _en);
        return context.tr(
            pl: 'a = $a mm — mniej niż 3 mm. EN 1993-1-8 p. 4.5.2: spoina '
                'pachwinowa przenosząca obciążenie ma a ≥ 3 mm '
                '(z ≥ ${_n(ceilTo(3 * math.sqrt2, 2), 2)} mm).',
            en: 'a = $a mm — less than 3 mm. EN 1993-1-8 cl. 4.5.2: a '
                'load-carrying fillet weld has a ≥ 3 mm '
                '(z ≥ ${_n(ceilTo(3 * math.sqrt2, 2), 2)} mm).');
      case FilletProblem.thickness:
        return context.tr(
            pl: 'Podaj grubość najgrubszej łączonej części (> 0 mm).',
            en: 'Enter the thickness of the thickest part joined (> 0 mm).');
      case FilletProblem.thicknessOver40:
        return context.tr(
            pl: 'Moduł ma fu z tabeli dla części do 40 mm (EN 1993-1-1 '
                'tabl. 3.1). Grubsze części mają niższe fu — policz '
                'z konstruktorem.',
            en: 'The module uses table fu for parts up to 40 mm (EN 1993-1-1 '
                'Table 3.1). Thicker parts have a lower fu — ask a '
                'structural engineer.');
      case FilletProblem.length:
        return context.tr(
            pl: 'Podaj długość spoiny l (> 0 mm).',
            en: 'Enter the weld length l (> 0 mm).');
      case FilletProblem.lengthTooShort:
        final a = i.throatMm;
        final min = minEffectiveLengthMm(a);
        final leff = effectiveLengthPerWeldMm(i.layout,
            lengthMm: i.lengthMm, tubeOdMm: i.tubeOdMm, throatMm: a);
        return i.layout == WeldLayout.linear
            ? context.tr(
                pl: 'Za krótka spoina: l_eff = l − 2a = ${_n(floorTo(leff, 1), 1)} mm, '
                    'a potrzeba co najmniej max(30 mm; 6a) = ${_n(ceilTo(min, 1), 1)} mm '
                    '(EN 1993-1-8 p. 4.5.1). Krótsza spoina nie przenosi obciążeń — '
                    'wydłuż ją albo zmniejsz a.',
                en: 'Weld too short: l_eff = l − 2a = ${_n(floorTo(leff, 1), 1)} mm, '
                    'at least max(30 mm; 6a) = ${_n(ceilTo(min, 1), 1)} mm is needed '
                    '(EN 1993-1-8 cl. 4.5.1). A shorter weld carries no load — '
                    'lengthen it or reduce a.')
            : context.tr(
                pl: 'Za krótka spoina: π·D = ${_n(floorTo(leff, 1), 1)} mm, a potrzeba '
                    'co najmniej max(30 mm; 6a) = ${_n(ceilTo(min, 1), 1)} mm '
                    '(EN 1993-1-8 p. 4.5.1).',
                en: 'Weld too short: π·D = ${_n(floorTo(leff, 1), 1)} mm, at least '
                    'max(30 mm; 6a) = ${_n(ceilTo(min, 1), 1)} mm is needed '
                    '(EN 1993-1-8 cl. 4.5.1).');
      case FilletProblem.welds:
        return context.tr(
            pl: 'Liczba spoin od 1 do 8.', en: 'From 1 to 8 welds.');
      case FilletProblem.tubeOd:
        return context.tr(
            pl: 'Podaj średnicę zewnętrzną rury D (> 0 mm).',
            en: 'Enter the tube outside diameter D (> 0 mm).');
      case FilletProblem.angle:
        return context.tr(
            pl: 'Kąt siły do osi spoiny: od 0° (wzdłuż) do 90° (w poprzek).',
            en: 'Force angle to the weld axis: 0° (along) to 90° (across).');
      case FilletProblem.tooLongForThroat:
        return context.tr(
            pl: 'Spoina dłuższa niż 900·a: wg EN 1993-1-8 p. 4.11 nośność '
                'długiego połączenia zakładkowego spada do zera. Zwiększ a '
                'albo podziel połączenie — policz z konstruktorem.',
            en: 'Weld longer than 900·a: per EN 1993-1-8 cl. 4.11 the '
                'resistance of a long lap joint drops to zero. Increase a or '
                'split the joint — ask a structural engineer.');
    }
  }

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _share(FilletWeldResult r, double? force) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final text = filletShareText(
        result: r,
        en: _en,
        forceInput: force,
        forceKind: _forceKind,
        legInput: _legMode,
      );
      unawaited(Haptic.tap());
      await widget.shareText(
          text,
          context.tr(
              pl: 'Nośność spoiny pachwinowej',
              en: 'Fillet weld resistance'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się udostępnić wyniku.',
              en: 'Could not share the result.'))));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final input = _input;
    final problems = filletProblems(input);
    final geometryOk = filletGeometryProblems(input).isEmpty;
    final result = computeFilletWeld(input);

    // Siła: puste pole — brak werdyktu (to nie błąd); nieczytelne albo ≤ 0 —
    // komunikat przy polu.
    final forceText = _force.text.trim();
    final forceParsed = parseDecimal(forceText);
    final forceEmpty = forceText.isEmpty;
    final forceValid = forceParsed != null && forceParsed > 0;
    final fEd = forceValid ? designForceKn(forceParsed, _forceKind) : null;
    // Liczby wyniku — te same na ekranie i w tekście do udostępnienia.
    final figures = result == null
        ? null
        : FilletFigures(result, en: _en, designForceKn: fEd);

    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Nośność spoiny pachwinowej',
              en: 'Fillet weld resistance'))),
      body: ListView(
        key: const ValueKey('fillet-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _materialSection(),
          _weldSection(input),
          _methodSection(),
          _forceSection(
              forceEmpty: forceEmpty,
              forceValid: forceValid,
              fEd: fEd,
              figures: figures),
          if (problems.isNotEmpty)
            KeyedSubtree(
              key: const ValueKey('fillet-problems'),
              child: QuoteNotice(
                color: kFail,
                icon: Icons.error_outline,
                text: problems.map((p) => _problemText(p, input)).join('\n'),
              ),
            ),
          if (figures != null) _resultSection(figures),
          if (geometryOk && fEd != null) _requiredSection(input, fEd, figures),
          if (figures != null) ..._warnings(figures),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                key: const ValueKey('fillet-share'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: kArc,
                  foregroundColor: kOnArc,
                ),
                onPressed: _sharing
                    ? null
                    : () => unawaited(_share(result, forceValid ? forceParsed : null)),
                icon: const Icon(Icons.share_outlined),
                label: Text(
                    context.tr(pl: 'Udostępnij wynik', en: 'Share the result'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          KeyedSubtree(
            key: const ValueKey('fillet-disclaimer'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.engineering_outlined,
              text: filletDisclaimer(en: _en),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {required Key key,
          String? unit,
          String? helper,
          String? error,
          ValueChanged<String>? onChanged}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: onChanged ?? (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _caption(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _chips(List<Widget> chips) =>
      Wrap(spacing: 6, runSpacing: 6, children: chips);

  Widget _choice(String key, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(onTap),
      );

  // ── Wejście ────────────────────────────────────────────────────────────

  Widget _materialSection() {
    final s = _steel;
    return QuoteSection(
      title: context.tr(pl: 'Stal', en: 'Steel'),
      subtitle: context.tr(
          pl: 'Gatunek słabszej z łączonych części.',
          en: 'Grade of the weaker of the parts joined.'),
      children: [
        _chips([
          for (final g in WeldSteelGrade.values)
            _choice('fillet-steel-${g.name}', g.label, _steel == g,
                () => _steel = g),
        ]),
        _caption(
          context.tr(
              pl: 'fu = ${_n(s.fuMpa, 0)} MPa (EN 1993-1-1 tabl. 3.1, t ≤ 40 mm), '
                  'βw = ${_n(s.betaW, 2)} (EN 1993-1-8 tabl. 4.1), γM2 = '
                  '${_n(kWeldGammaM2, 2)}. Stale S275 N/M i S355 M/ML mają niższe fu '
                  '(370–470 MPa) — wtedy wynik jest za wysoki.',
              en: 'fu = ${_n(s.fuMpa, 0)} MPa (EN 1993-1-1 Table 3.1, t ≤ 40 mm), '
                  'βw = ${_n(s.betaW, 2)} (EN 1993-1-8 Table 4.1), γM2 = '
                  '${_n(kWeldGammaM2, 2)}. S275 N/M and S355 M/ML steels have a '
                  'lower fu (370–470 MPa) — the result would then be too high.'),
          key: const ValueKey('fillet-steel-caption'),
        ),
        const SizedBox(height: 12),
        _field(
          _t,
          context.tr(
              pl: 'Grubość najgrubszej części t',
              en: 'Thickest part thickness t'),
          key: const ValueKey('fillet-t'),
          unit: 'mm',
          helper: context.tr(
              pl: 'Do 40 mm — dla grubszych fu jest niższe.',
              en: 'Up to 40 mm — thicker parts have a lower fu.'),
        ),
      ],
    );
  }

  Widget _weldSection(FilletWeldInput input) {
    // Z wartości źródłowej, nie z tekstu pola — te same liczby co w wyniku
    // i w tekście do udostępnienia.
    final a = _throatMm;
    final conversion = a.isFinite && a > 0
        ? (_legMode
            ? 'a = z/√2 = ${formatThroat(a, en: _en)} mm'
            : 'z = a·√2 = ${formatLeg(a, en: _en)} mm')
        : null;
    final leff = _layout == WeldLayout.linear
        ? input.lengthMm - 2 * input.throatMm
        : math.pi * input.tubeOdMm;
    final leffOk = leff.isFinite && leff > 0;
    return QuoteSection(
      title: context.tr(pl: 'Spoina', en: 'Weld'),
      children: [
        _chips([
          _choice('fillet-size-a',
              context.tr(pl: 'Grubość a', en: 'Throat a'), !_legMode,
              () => _setLegMode(false)),
          _choice('fillet-size-z', context.tr(pl: 'Bok z', en: 'Leg z'),
              _legMode, () => _setLegMode(true)),
        ]),
        const SizedBox(height: 10),
        _field(
          _size,
          _legMode
              ? context.tr(pl: 'Długość boku z', en: 'Leg length z')
              : context.tr(
                  pl: 'Grubość obliczeniowa a', en: 'Throat thickness a'),
          key: const ValueKey('fillet-size'),
          unit: 'mm',
          onChanged: _onSizeChanged,
        ),
        _caption(
          [
            if (conversion != null) conversion,
            context.tr(
                pl: 'a = z/√2 tylko dla ścianek pod kątem prostym. Spoina '
                    'pachwinowa wg normy: kąt między ściankami 60°–120° '
                    '(EN 1993-1-8 p. 4.3.2.1).',
                en: 'a = z/√2 only for faces at a right angle. A fillet weld '
                    'per the code: angle between the faces 60°–120° '
                    '(EN 1993-1-8 cl. 4.3.2.1).'),
          ].join(' · '),
          key: const ValueKey('fillet-size-caption'),
        ),
        const SizedBox(height: 14),
        _chips([
          _choice(
              'fillet-layout-linear',
              context.tr(pl: 'Odcinki proste', en: 'Straight runs'),
              _layout == WeldLayout.linear,
              () => _layout = WeldLayout.linear),
          _choice(
              'fillet-layout-circumferential',
              context.tr(pl: 'Obwodowa: rura do blachy', en: 'All round: tube to plate'),
              _layout == WeldLayout.circumferential,
              () => _layout = WeldLayout.circumferential),
        ]),
        const SizedBox(height: 12),
        if (_layout == WeldLayout.linear) ...[
          _field(
            _length,
            context.tr(pl: 'Długość jednej spoiny l', en: 'Length of one weld l'),
            key: const ValueKey('fillet-length'),
            unit: 'mm',
          ),
          const SizedBox(height: 12),
          _label(context.tr(pl: 'Liczba spoin', en: 'Number of welds')),
          _chips([
            _choice('fillet-welds-1',
                context.tr(pl: '1 — jednostronna', en: '1 — one side'),
                _welds == 1, () => _welds = 1),
            _choice('fillet-welds-2',
                context.tr(pl: '2 — obustronna', en: '2 — both sides'),
                _welds == 2, () => _welds = 2),
            _choice('fillet-welds-4',
                context.tr(pl: '4 spoiny', en: '4 welds'), _welds == 4,
                () => _welds = 4),
          ]),
          _caption(context.tr(
              pl: 'l_eff = l − 2a${leffOk ? ' = ${formatDown(leff, 1, en: _en)} mm' : ''} '
                  'na każdą spoinę (EN 1993-1-8 p. 4.5.1) — na końcach spoina nie '
                  'ma pełnego przekroju. Min. max(30 mm; 6a).',
              en: 'l_eff = l − 2a${leffOk ? ' = ${formatDown(leff, 1, en: _en)} mm' : ''} '
                  'per weld (EN 1993-1-8 cl. 4.5.1) — the ends are not full size. '
                  'Min. max(30 mm; 6a).')),
        ] else ...[
          _field(
            _tube,
            context.tr(
                pl: 'Średnica zewnętrzna rury D', en: 'Tube outside diameter D'),
            key: const ValueKey('fillet-tube'),
            unit: 'mm',
          ),
          _caption(
            context.tr(
                pl: 'l = π·D${leffOk ? ' = ${formatDown(leff, 1, en: _en)} mm' : ''}. '
                    'Spoina zamknięta, bez końców — bez odejmowania 2a, jeśli '
                    'początek i koniec są zachodzące, pełnego przekroju.',
                en: 'l = π·D${leffOk ? ' = ${formatDown(leff, 1, en: _en)} mm' : ''}. '
                    'A closed weld with no ends — no 2a deduction if the start and '
                    'stop overlap at full size.'),
            key: const ValueKey('fillet-tube-caption'),
          ),
        ],
      ],
    );
  }

  Widget _methodSection() {
    final circ = _layout == WeldLayout.circumferential;
    return QuoteSection(
      title: context.tr(pl: 'Metoda', en: 'Method'),
      children: [
        _chips([
          _choice(
              'fillet-method-simplified',
              context.tr(pl: 'Uproszczona', en: 'Simplified'),
              _method == FilletMethod.simplified,
              () => _method = FilletMethod.simplified),
          _choice(
              'fillet-method-directional',
              context.tr(pl: 'Kierunkowa', en: 'Directional'),
              _method == FilletMethod.directional,
              () => _method = FilletMethod.directional),
        ]),
        if (_method == FilletMethod.simplified)
          _caption(context.tr(
              pl: 'fvw,d = fu/(√3·βw·γM2) — niezależnie od kierunku siły; zawsze '
                  'po bezpiecznej stronie (EN 1993-1-8 p. 4.5.3.3).',
              en: 'fvw,d = fu/(√3·βw·γM2) — whatever the force direction; always '
                  'on the safe side (EN 1993-1-8 cl. 4.5.3.3).'))
        else if (circ)
          _caption(context.tr(
              pl: 'Spoina obwodowa: siła osiowa w rurze (rozciąganie / ściskanie) '
                  '— wszędzie w poprzek spoiny (90°). Ścinanie poprzeczne rury: '
                  'metoda uproszczona. Moment zginający — poza zakresem modułu.',
              en: 'All-round weld: axial force in the tube (tension / compression) '
                  '— across the weld everywhere (90°). Transverse shear on the '
                  'tube: use the simplified method. Bending — outside this module.'))
        else ...[
          const SizedBox(height: 12),
          _label(context.tr(
              pl: 'Kierunek siły względem osi spoiny',
              en: 'Force direction to the weld axis')),
          _chips([
            _choice(
                'fillet-dir-along',
                context.tr(pl: 'Wzdłuż (0°)', en: 'Along (0°)'),
                _direction == _Direction.along,
                () => _direction = _Direction.along),
            _choice(
                'fillet-dir-across',
                context.tr(pl: 'W poprzek (90°)', en: 'Across (90°)'),
                _direction == _Direction.across,
                () => _direction = _Direction.across),
            _choice(
                'fillet-dir-angle',
                context.tr(pl: 'Pod kątem θ', en: 'At angle θ'),
                _direction == _Direction.angle,
                () => _direction = _Direction.angle),
          ]),
          if (_direction == _Direction.angle) ...[
            const SizedBox(height: 10),
            _field(_angle,
                context.tr(pl: 'Kąt θ do osi spoiny', en: 'Angle θ to the weld axis'),
                key: const ValueKey('fillet-angle'), unit: '°'),
          ],
          _caption(context.tr(
              pl: 'Siła w płaszczyźnie jednej ze ścianek (np. wspornik ciągnięty '
                  'od blachy, zakładka). [σ⊥² + 3(τ⊥² + τ∥²)]^0,5 ≤ fu/(βw·γM2) '
                  'oraz σ⊥ ≤ 0,9·fu/γM2 (EN 1993-1-8 p. 4.5.3.2). W poprzek — '
                  'ok. 1,22 × więcej niż uproszczona.',
              en: 'Force in the plane of one face (e.g. a bracket pulled off the '
                  'plate, a lap). [σ⊥² + 3(τ⊥² + τ∥²)]^0.5 ≤ fu/(βw·γM2) and '
                  'σ⊥ ≤ 0.9·fu/γM2 (EN 1993-1-8 cl. 4.5.3.2). Across — about '
                  '1.22 × the simplified value.')),
        ],
      ],
    );
  }

  Widget _forceSection(
      {required bool forceEmpty,
      required bool forceValid,
      double? fEd,
      FilletFigures? figures}) {
    final error = forceEmpty || forceValid
        ? null
        : context.tr(
            pl: 'Wpisz liczbę większą od 0.',
            en: 'Enter a number greater than 0.');
    return QuoteSection(
      title: context.tr(pl: 'Siła na spoinę', en: 'Force on the weld'),
      subtitle: context.tr(
          pl: 'Opcjonalnie — do wykorzystania i wymaganego a.',
          en: 'Optional — for utilisation and the required a.'),
      children: [
        _chips([
          _choice(
              'fillet-force-design',
              context.tr(pl: 'Obliczeniowa F_Ed', en: 'Design F_Ed'),
              _forceKind == ForceKind.design,
              () => _forceKind = ForceKind.design),
          _choice(
              'fillet-force-permanent',
              context.tr(pl: 'Ciężar × 1,35', en: 'Dead load × 1.35'),
              _forceKind == ForceKind.permanent,
              () => _forceKind = ForceKind.permanent),
          _choice(
              'fillet-force-variable',
              context.tr(pl: 'Zmienna × 1,5', en: 'Live load × 1.5'),
              _forceKind == ForceKind.variable,
              () => _forceKind = ForceKind.variable),
        ]),
        const SizedBox(height: 10),
        _field(
          _force,
          _forceKind == ForceKind.design
              ? context.tr(
                  pl: 'Siła obliczeniowa F_Ed', en: 'Design force F_Ed')
              : context.tr(
                  pl: 'Siła charakterystyczna F_k',
                  en: 'Characteristic force F_k'),
          key: const ValueKey('fillet-force'),
          unit: 'kN',
          error: error,
        ),
        if (fEd != null && _forceKind != ForceKind.design)
          _caption(
              'F_Ed = ${_v(_forceKind.gammaF)} × ${_v(parseDecimal(_force.text)!)} kN = '
              '${_fedText(fEd, figures)} kN',
              key: const ValueKey('fillet-fed')),
        _caption(context.tr(
            pl: 'F_Ed z obliczeń/projektu ma już współczynniki. Jeśli znasz tylko '
                'rzeczywiste obciążenie (charakterystyczne), pomnóż je: 1,35 — '
                'stałe (ciężar), 1,5 — zmienne (użytkowe, śnieg, wiatr) wg '
                'EN 1990. Gdy nie wiesz — bierz 1,5. 1 t ≈ 9,81 kN.',
            en: 'An F_Ed from a calculation/design already has the factors. If '
                'you only know the actual (characteristic) load, multiply it: '
                '1.35 — permanent (dead weight), 1.5 — variable (imposed, snow, '
                'wind) per EN 1990. If unsure — use 1.5. 1 t ≈ 9.81 kN.')),
      ],
    );
  }

  /// F_Ed do pokazania: z [FilletFigures] (te same cyfry co przy werdykcie
  /// i w tekście), a bez wyniku — W GÓRĘ do 0,1 kN.
  String _fedText(double fEd, FilletFigures? figures) =>
      figures?.designForce ?? formatUp(fEd, 1, en: _en);

  // ── Wynik ──────────────────────────────────────────────────────────────

  Widget _resultSection(FilletFigures f) {
    final r = f.result;
    final i = r.input;
    final directional = i.method == FilletMethod.directional;
    return QuoteSection(
      title: context.tr(pl: 'Nośność spoiny', en: 'Weld resistance'),
      children: [
        Readout(
          key: const ValueKey('fillet-result'),
          label: 'F_w,Rd',
          value: f.resistance,
          unit: directional
              ? context.tr(
                  pl: 'kN · kierunkowa, ${f.angle}°',
                  en: 'kN · directional, ${f.angle}°')
              : context.tr(pl: 'kN · uproszczona', en: 'kN · simplified'),
          hot: true,
        ),
        const SizedBox(height: 12),
        if (f.check != null) _verdict(f),
        _kv(
            directional
                ? context.tr(
                    pl: 'Wytrzymałość na mm² przekroju',
                    en: 'Strength per mm² of throat')
                : 'fvw,d',
            '${f.strength} MPa',
            valueKey: 'fillet-kv-strength'),
        if (directional)
          _kv(
              context.tr(
                  pl: 'Uproszczona dla porównania',
                  en: 'Simplified, for comparison'),
              '${f.simplifiedResistance} kN',
              valueKey: 'fillet-kv-simplified'),
        if (i.layout == WeldLayout.linear)
          _kv(
              context.tr(
                  pl: 'Σ l_eff (${i.welds} × ${f.effectiveLengthPerWeld})',
                  en: 'Σ l_eff (${i.welds} × ${f.effectiveLengthPerWeld})'),
              '${f.totalEffectiveLength} mm',
              valueKey: 'fillet-kv-leff')
        else
          _kv('l = π·D', '${f.weldLength} mm', valueKey: 'fillet-kv-leff'),
        _kv(context.tr(pl: 'Przekrój obliczeniowy a·Σl', en: 'Throat area a·Σl'),
            '${f.throatArea} mm²',
            valueKey: 'fillet-kv-area'),
        if (r.longJointApplied)
          _kv(context.tr(pl: 'βLw (p. 4.11)', en: 'βLw (cl. 4.11)'),
              f.longJointFactor,
              valueKey: 'fillet-kv-beta'),
      ],
    );
  }

  Widget _verdict(FilletFigures f) {
    final c = f.check!;
    final p = f.utilisation;
    final e = f.designForce;
    final r = f.resistance;
    final text = c.ok
        ? context.tr(
            pl: 'Wystarczy — wykorzystanie $p % (F_Ed $e kN ≤ F_Rd $r kN).',
            en: 'Sufficient — utilisation $p % (F_Ed $e kN ≤ F_Rd $r kN).')
        : context.tr(
            pl: 'NIE wystarczy — wykorzystanie $p % (F_Ed $e kN > F_Rd $r kN). '
                'Zwiększ a, wydłuż spoinę albo dodaj spoiny.',
            en: 'NOT sufficient — utilisation $p % (F_Ed $e kN > F_Rd $r kN). '
                'Increase a, lengthen the weld or add welds.');
    return KeyedSubtree(
      key: ValueKey(c.ok ? 'fillet-verdict-ok' : 'fillet-verdict-fail'),
      child: QuoteNotice(
        color: c.ok ? kPass : kFail,
        icon: c.ok ? Icons.check_circle_outline : Icons.error_outline,
        text: text,
      ),
    );
  }

  Widget _requiredSection(
      FilletWeldInput input, double fEd, FilletFigures? figures) {
    final req = requiredThroat(input, fEd);
    if (req == null) return const SizedBox.shrink();
    final rf = requiredThroatFigures(req, en: _en);
    final children = <Widget>[];
    switch (req.status) {
      case ThroatStatus.found:
      case ThroatStatus.minimum:
        final a = '≥ ${rf!.throat}';
        final z = '≥ ${rf.leg}';
        children.add(Readout(
          key: const ValueKey('fillet-required'),
          label: _legMode
              ? context.tr(pl: 'Wymagany bok z', en: 'Required leg z')
              : context.tr(pl: 'Wymagane a', en: 'Required a'),
          value: _legMode ? z : a,
          unit: _legMode ? 'mm · a $a mm' : 'mm · z $z mm',
        ));
        children.add(const SizedBox(height: 10));
        if (rf.whole != null) {
          children.add(_kv(
              context.tr(pl: 'Przyjmij (całe mm)', en: 'Use (whole mm)'),
              'a${rf.whole} · z ≥ ${rf.wholeLeg} mm',
              valueKey: 'fillet-kv-whole'));
        } else {
          children.add(_caption(context.tr(
              pl: 'Całe a w górę nie mieści się w warunku l_eff ≥ 6a — wydłuż '
                  'spoinę.',
              en: 'The next whole a does not meet l_eff ≥ 6a — lengthen the '
                  'weld.')));
        }
        if (req.status == ThroatStatus.minimum) {
          children.add(_caption(context.tr(
              pl: 'Decyduje minimum normy: a = 3 mm (EN 1993-1-8 p. 4.5.2).',
              en: 'The code minimum governs: a = 3 mm (EN 1993-1-8 cl. 4.5.2).')));
        }
      case ThroatStatus.needsLongerWeld:
        final aMax = formatDown(req.maxMm!, 1, en: _en);
        children.add(KeyedSubtree(
          key: const ValueKey('fillet-required-none'),
          child: QuoteNotice(
            color: kFail,
            icon: Icons.straighten,
            text: context.tr(
                pl: 'Nawet największe a dla tej długości '
                    '($aMax mm, warunek l_eff ≥ 6a) '
                    'nie wystarczy. Wydłuż spoinę, dodaj spoiny albo weź '
                    'większy element.',
                en: 'Even the largest a for this length '
                    '($aMax mm, l_eff ≥ 6a) is not '
                    'enough. Lengthen the weld, add welds or use a larger part.'),
          ),
        ));
      case ThroatStatus.weldTooShort:
        children.add(KeyedSubtree(
          key: const ValueKey('fillet-required-none'),
          child: QuoteNotice(
            color: kFail,
            icon: Icons.straighten,
            text: context.tr(
                pl: 'Spoina za krótka nawet dla a = 3 mm (l_eff ≥ 30 mm).',
                en: 'The weld is too short even for a = 3 mm (l_eff ≥ 30 mm).'),
          ),
        ));
    }
    final fed = _fedText(fEd, figures);
    return QuoteSection(
      title: context.tr(pl: 'Jaka spoina wystarczy', en: 'What weld is enough'),
      subtitle: context.tr(
          pl: 'Dla F_Ed $fed kN, tej długości i metody. '
              'Wymiar zaokrąglony w górę.',
          en: 'For F_Ed $fed kN, this length and method. '
              'Size rounded up.'),
      children: children,
    );
  }

  List<Widget> _warnings(FilletFigures f) {
    final r = f.result;
    final i = r.input;
    return [
      if (i.layout == WeldLayout.linear && i.welds == 1)
        KeyedSubtree(
          key: const ValueKey('fillet-warn-single'),
          child: QuoteNotice(
            text: context.tr(
                pl: 'Pojedyncza spoina jednostronna: siła odrywająca albo '
                    'moment rozciągają grań — EN 1993-1-8 p. 4.12 każe ten '
                    'mimośród uwzględnić, a wynik tego nie robi. Lepiej spoina '
                    'obustronna.',
                en: 'A single one-sided weld: a peeling force or moment opens '
                    'the root — EN 1993-1-8 cl. 4.12 requires that eccentricity '
                    'to be taken into account and this result does not. Better '
                    'weld both sides.'),
          ),
        ),
      if (r.longJointApplied)
        KeyedSubtree(
          key: const ValueKey('fillet-warn-long'),
          child: QuoteNotice(
            text: context.tr(
                pl: 'Spoina dłuższa niż 150·a: nośność zmniejszona '
                    'βLw = 1,2 − 0,2·l/(150a) = ${f.longJointFactor} '
                    '(EN 1993-1-8 p. 4.11 — połączenia zakładkowe; zastosowane '
                    'zachowawczo).',
                en: 'Weld longer than 150·a: resistance reduced by '
                    'βLw = 1.2 − 0.2·l/(150a) = ${f.longJointFactor} '
                    '(EN 1993-1-8 cl. 4.11 — lap joints; applied '
                    'conservatively).'),
          ),
        ),
    ];
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
