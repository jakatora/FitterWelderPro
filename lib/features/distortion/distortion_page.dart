// Odkształcenia spawalnicze: „element się wykrzywił / szczelina się
// zamknęła / kołnierz poszedł w skos — jak temu zapobiec i ile zostawić”.
//
// 1. Szacunek skurczu poprzecznego spoiny czołowej (Spraragen–Ettinger,
//    pole rowka z modelu wycen).
// 2. Wymiar zestawienia przed spawaniem: wymiar końcowy + Σ skurczu spoin
//    poprzecznych, zaokrąglone W GÓRĘ do 0,5 mm.
// 3. Lista środków dobrana do sytuacji (element × odkształcenie), każdy
//    z „dlaczego” i źródłem; przyciski do energii liniowej i odbioru
//    kołnierzy.
// Logika i źródła: domain/welding/distortion.dart, dane:
// data/distortion_tips.dart. Bez zapisu w bazie. Puste albo nieczytelne pole
// to komunikat, nie wynik.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../assistant/core/tool_bridge.dart';
import '../../data/distortion_tips.dart';
import '../../domain/welding/distortion.dart';
import '../../i18n/app_language.dart';
import '../../screens/heat_input_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../flange_check/flange_check_page.dart';
import '../quotes/quote_widgets.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef DistortionShareText = Future<void> Function(
    String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

class DistortionPage extends StatefulWidget {
  const DistortionPage({super.key, this.shareText = _defaultShareText});

  final DistortionShareText shareText;

  @override
  State<DistortionPage> createState() => _DistortionPageState();
}

class _DistortionPageState extends State<DistortionPage>
    with ToolHandleHost<DistortionPage>
    implements InputToolHandle {
  @override
  String get toolId => 'distortion';
  @override
  Set<String> get supportedFields => const {
        'groove',
        'thickness_mm',
        'gap_mm',
        'root_face_mm',
        'angle_deg',
        'final_length_mm',
        'butt_welds',
        'fillet_welds'
      };
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'groove': _groove.name,
        'thickness_mm': parseDecimal(_t.text),
        'gap_mm': parseDecimal(_gap.text),
        'root_face_mm': parseDecimal(_rootFace.text),
        'angle_deg': parseDecimal(
            (_groove == ButtGroove.halfV ? _bevel : _angle).text),
        'final_length_mm': parseDecimal(_final.text),
        'butt_welds': parseDecimal(_buttCount.text),
        'fillet_welds': parseDecimal(_filletCount.text),
        'measured': _measuredMode,
      });

  @override
  void initState() {
    super.initState();
    markReady();
  }

  /// Asystent: rowek i szacunek skurczu (nie pomiar z próby); wymiar
  /// końcowy i liczby spoin tylko, gdy podane. Wszystko albo nic.
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || fields.keys.any((k) => !supportedFields.contains(k))) {
      return fields.keys.toSet();
    }
    final groove =
        ButtGroove.values.where((g) => g.name == fields['groove']).firstOrNull;
    bool number(Object? v) => v is num && v.isFinite && v >= 0;
    final rejected = <String>{
      if (groove == null) 'groove',
      for (final key in const [
        'thickness_mm',
        'gap_mm',
        'root_face_mm',
        'angle_deg'
      ])
        if (!number(fields[key])) key,
      for (final key in const ['final_length_mm', 'butt_welds', 'fillet_welds'])
        if (fields.containsKey(key) && !number(fields[key])) key,
    };
    if (rejected.isNotEmpty) return rejected;
    String text(String key) => _n((fields[key] as num).toDouble());
    setState(() {
      _measuredMode = false;
      _groove = groove!;
      _t.text = text('thickness_mm');
      _gap.text = text('gap_mm');
      _rootFace.text = text('root_face_mm');
      (groove == ButtGroove.halfV ? _bevel : _angle).text = text('angle_deg');
      if (fields.containsKey('final_length_mm')) {
        _final.text = text('final_length_mm');
      }
      if (fields.containsKey('butt_welds')) {
        _buttCount.text = text('butt_welds');
      }
      if (fields.containsKey('fillet_welds')) {
        _filletCount.text = text('fillet_welds');
      }
    });
    return {};
  }

  // Blacha 10 mm, rowek V 60°, d 2, c 1,5 — typowy start.
  ButtGroove _groove = ButtGroove.v;
  final _t = TextEditingController(text: '10');
  final _gap = TextEditingController(text: '2');
  final _rootFace = TextEditingController(text: numText(1.5));
  final _angle = TextEditingController(text: '60');
  final _bevel = TextEditingController(text: '45');

  final _final = TextEditingController(text: '1000');
  final _buttCount = TextEditingController(text: '2');
  final _filletCount = TextEditingController(text: '0');
  final _measured = TextEditingController();

  /// true — skurcz na spoinę czołową z pomiaru na próbie, nie z szacunku.
  bool _measuredMode = false;

  DistortionElement _element = DistortionElement.plateButt;
  DistortionKind _kind = DistortionKind.angular;
  bool _sharing = false;

  @override
  void dispose() {
    for (final c in [
      _t,
      _gap,
      _rootFace,
      _angle,
      _bevel,
      _final,
      _buttCount,
      _filletCount,
      _measured,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  String _f(double v, int d) => distFixed(v, d, en: _en);
  String _n(double v) => distNum(v, en: _en);

  /// Liczba z pola; puste albo nieczytelne → NaN (domena zgłosi problem).
  double _val(TextEditingController c) => parseDecimal(c.text) ?? double.nan;

  ButtShrinkageInput get _shrinkInput => ButtShrinkageInput(
        groove: _groove,
        thicknessMm: _val(_t),
        gapMm: _val(_gap),
        rootFaceMm: _val(_rootFace),
        angleDeg: _val(_groove == ButtGroove.halfV ? _bevel : _angle),
      );

  PreWeldInput _preWeldInput(ButtShrinkageResult? s) => PreWeldInput(
        finalLengthMm: _val(_final),
        buttWelds: _val(_buttCount),
        shrinkagePerButtMm: _measuredMode
            ? _val(_measured)
            : (s?.shrinkageAllowanceMm ?? double.nan),
        filletWelds: _val(_filletCount),
      );

  // ── Komunikaty ─────────────────────────────────────────────────────────

  String _shrinkProblem(ShrinkageProblem p) => switch (p) {
        ShrinkageProblem.thickness => context.tr(
            pl: 'Podaj grubość blachy t (od 0 do ${_n(kMaxThicknessMm)} mm).',
            en: 'Enter the plate thickness t (0 to ${_n(kMaxThicknessMm)} mm).'),
        ShrinkageProblem.gap => context.tr(
            pl: 'Podaj odstęp w grani d (od 0 do ${_n(kMaxGapMm)} mm).',
            en: 'Enter the root gap d (0 to ${_n(kMaxGapMm)} mm).'),
        ShrinkageProblem.rootFace => context.tr(
            pl: 'Podaj próg c (od 0 mm, mniej niż grubość t).',
            en: 'Enter the root face c (from 0 mm, less than thickness t).'),
        ShrinkageProblem.angle => _groove == ButtGroove.halfV
            ? context.tr(
                pl: 'Kąt fazy β od ${_n(kMinBevelDeg)} do ${_n(kMaxBevelDeg)}°.',
                en: 'Bevel angle β from ${_n(kMinBevelDeg)} to ${_n(kMaxBevelDeg)}°.')
            : context.tr(
                pl: 'Kąt rowka α od ${_n(kMinIncludedAngleDeg)} do '
                    '${_n(kMaxIncludedAngleDeg)}°.',
                en: 'Groove angle α from ${_n(kMinIncludedAngleDeg)} to '
                    '${_n(kMaxIncludedAngleDeg)}°.'),
      };

  String _preWeldProblem(PreWeldProblem p) => switch (p) {
        PreWeldProblem.finalLength => context.tr(
            pl: 'Podaj wymiar końcowy (do ${_n(kMaxFinalLengthMm)} mm).',
            en: 'Enter the final dimension (up to ${_n(kMaxFinalLengthMm)} mm).'),
        PreWeldProblem.buttWelds => context.tr(
            pl: 'Liczba spoin czołowych: liczba całkowita od 0 do $kMaxWelds.',
            en: 'Number of butt welds: a whole number from 0 to $kMaxWelds.'),
        PreWeldProblem.filletWelds => context.tr(
            pl: 'Liczba spoin pachwinowych: liczba całkowita od 0 do $kMaxWelds.',
            en: 'Number of fillet welds: a whole number from 0 to $kMaxWelds.'),
        PreWeldProblem.noWelds => context.tr(
            pl: 'W łańcuchu nie ma spoin — wymiar się nie zmienia.',
            en: 'There are no welds in the chain — the dimension does not change.'),
        PreWeldProblem.shrinkagePerButt => _measuredMode
            ? context.tr(
                pl: 'Wpisz zmierzony skurcz jednej spoiny (od 0 do '
                    '${_n(kMaxShrinkagePerWeldMm)} mm).',
                en: 'Enter the measured shrinkage of one weld (0 to '
                    '${_n(kMaxShrinkagePerWeldMm)} mm).')
            : context.tr(
                pl: 'Brak szacunku skurczu — popraw dane rowka wyżej albo '
                    'wpisz własny pomiar.',
                en: 'No shrinkage estimate — correct the groove data above '
                    'or enter your own measurement.'),
      };

  // ── Akcje ──────────────────────────────────────────────────────────────

  void _pickElement(DistortionElement e) {
    _element = e;
    final kinds = kindsFor(e);
    if (!kinds.contains(_kind)) _kind = kinds.first;
  }

  Future<void> _open(MeasureLink link) async {
    unawaited(Haptic.tap());
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => switch (link) {
        MeasureLink.heatInput => const HeatInputScreen(),
        MeasureLink.flangeCheck => const FlangeCheckPage(),
      },
    ));
  }

  Future<void> _share(ButtShrinkageResult? s, PreWeldResult? p,
      List<DistortionMeasure> measures) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final text = distortionShareText(
        en: _en,
        shrinkage: s,
        preWeld: p,
        measuredShrinkage: _measuredMode,
        element: _element,
        kind: _kind,
        measures: measures,
      );
      unawaited(Haptic.tap());
      await widget.shareText(
          text,
          context.tr(
              pl: 'Odkształcenia spawalnicze', en: 'Welding distortion'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się udostępnić.', en: 'Could not share.'))));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shrinkInput = _shrinkInput;
    final shrinkProblems = shrinkageProblems(shrinkInput);
    final shrink = computeButtShrinkage(shrinkInput);
    final preInput = _preWeldInput(shrink);
    final preProblems = preWeldProblems(preInput);
    final pre = computePreWeld(preInput);
    final measures = measuresFor(_element, _kind);

    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Odkształcenia spawalnicze', en: 'Welding distortion'))),
      body: ListView(
        key: const ValueKey('dist-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _shrinkSection(shrinkProblems, shrink),
          _preWeldSection(preProblems, pre, shrink),
          _preventSection(measures),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              key: const ValueKey('dist-share'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: kArc,
                foregroundColor: kOnArc,
              ),
              onPressed: _sharing
                  ? null
                  : () => unawaited(_share(shrink, pre, measures)),
              icon: const Icon(Icons.share_outlined),
              label: Text(
                  context.tr(
                      pl: 'Udostępnij wynik i środki',
                      en: 'Share the result and measures'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          KeyedSubtree(
            key: const ValueKey('dist-disclaimer'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.engineering_outlined,
              text: distortionDisclaimer(en: _en),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pomocnicze widżety ─────────────────────────────────────────────────

  Widget _field(TextEditingController c, String label,
          {required Key key,
          String? unit,
          String? helper,
          bool decimal = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: numberKeyboard(decimal: decimal),
          inputFormatters: numberInputFormatters(decimal: decimal),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            helperText: helper,
            helperMaxLines: 3,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _note(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _chips(List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: chips),
      );

  Widget _choice(String key, String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(onTap),
      );

  Widget _kv(String k, String v, {Key? key}) => CopyOnLongPress(
        key: key,
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
              Text(v,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      );

  // ── Sekcja 1: skurcz poprzeczny ────────────────────────────────────────

  Widget _shrinkSection(
      List<ShrinkageProblem> problems, ButtShrinkageResult? r) {
    final halfV = _groove == ButtGroove.halfV;
    final warnings = r == null
        ? const <ShrinkageWarning>[]
        : shrinkageWarnings(r.input);
    return QuoteSection(
      title: context.tr(
          pl: 'Skurcz poprzeczny spoiny czołowej',
          en: 'Transverse shrinkage of a butt weld'),
      subtitle: context.tr(
          pl: 'Szacunek: o ile skróci się element na jednej spoinie — tyle '
              'dodać do wymiaru przed spawaniem.',
          en: 'Estimate: how much one weld shortens the part — add this to '
              'the dimension before welding.'),
      children: [
        _label(context.tr(pl: 'Rowek', en: 'Groove')),
        _chips([
          for (final g in ButtGroove.values)
            _choice('dist-groove-${g.name}', grooveLabel(g, en: _en),
                _groove == g, () => _groove = g),
        ]),
        _field(_t, context.tr(pl: 'Grubość blachy t', en: 'Plate thickness t'),
            key: const ValueKey('dist-t'), unit: 'mm'),
        _field(_gap, context.tr(pl: 'Odstęp w grani d', en: 'Root gap d'),
            key: const ValueKey('dist-gap'), unit: 'mm'),
        _field(_rootFace, context.tr(pl: 'Próg c', en: 'Root face c'),
            key: const ValueKey('dist-rootface'), unit: 'mm'),
        if (halfV)
          _field(_bevel,
              context.tr(pl: 'Kąt fazy β', en: 'Bevel angle β'),
              key: const ValueKey('dist-bevel'),
              unit: '°',
              helper: context.tr(
                  pl: 'Faza tylko na jednym elemencie.',
                  en: 'Bevel on one part only.'))
        else
          _field(
              _angle,
              context.tr(
                  pl: 'Kąt rowka α (całkowity)',
                  en: 'Groove angle α (included)'),
              key: const ValueKey('dist-angle'),
              unit: '°',
              helper: _groove == ButtGroove.x
                  ? context.tr(
                      pl: 'Ten sam kąt po obu stronach, próg w środku '
                          'grubości.',
                      en: 'The same angle on both sides, root face at '
                          'mid-thickness.')
                  : null),
        if (problems.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('dist-shrink-problems'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: problems.map(_shrinkProblem).join('\n'),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 4),
          KeyedSubtree(
            key: const ValueKey('dist-shrinkage'),
            child: Readout(
              label: context.tr(
                  pl: 'Skurcz poprzeczny — szacunek',
                  en: 'Transverse shrinkage — estimate'),
              value: _f(r.shrinkageAllowanceMm, 1),
              unit: context.tr(
                  pl: 'mm na spoinę · w górę do 0,1',
                  en: 'mm per weld · up to 0.1'),
            ),
          ),
          const SizedBox(height: 10),
          _kv(context.tr(pl: 'Pole rowka A_w', en: 'Groove area A_w'),
              '${_f(r.areaMm2, 1)} mm²',
              key: const ValueKey('dist-area')),
          _kv(
              context.tr(
                  pl: 'Średnia szerokość A_w/t', en: 'Mean width A_w/t'),
              '${_f(r.meanWidthMm, 2)} mm'),
          _kv('${_n(kSeAreaCoef)} · A_w/t', '${_f(r.areaTermMm, 3)} mm'),
          _kv('${_n(kSeGapCoef)} · d', '${_f(r.gapTermMm, 3)} mm'),
          _kv(
              context.tr(
                  pl: 'S przed zaokrągleniem', en: 'S before rounding'),
              '${_f(r.shrinkageMm, 3)} mm',
              key: const ValueKey('dist-shrinkage-raw')),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const ValueKey('dist-shrink-warnings'),
              child: QuoteNotice(
                color: kWarn,
                icon: Icons.warning_amber_rounded,
                text: warnings
                    .map((w) => shrinkageWarningText(w, en: _en))
                    .join('\n'),
              ),
            ),
          ],
        ],
        _note(shrinkageFormulaNote(en: _en),
            key: const ValueKey('dist-formula')),
        _note(twiButtNote(en: _en)),
      ],
    );
  }

  // ── Sekcja 2: wymiar przed spawaniem ───────────────────────────────────

  Widget _preWeldSection(List<PreWeldProblem> problems, PreWeldResult? r,
      ButtShrinkageResult? shrink) {
    final estimateLabel = shrink == null
        ? context.tr(pl: 'Szacunek (brak)', en: 'Estimate (none)')
        : context.tr(
            pl: 'Szacunek ${_f(shrink.shrinkageAllowanceMm, 1)} mm',
            en: 'Estimate ${_f(shrink.shrinkageAllowanceMm, 1)} mm');
    final fillet = _n(kTwiFilletTransverseMm);
    return QuoteSection(
      title: context.tr(
          pl: 'Wymiar przed spawaniem', en: 'Dimension before welding'),
      subtitle: context.tr(
          pl: 'Wymiar po spawaniu + skurcz spoin poprzecznych w łańcuchu '
              'wymiarowym.',
          en: 'Dimension after welding + shrinkage of the transverse welds '
              'in the dimension chain.'),
      children: [
        _field(
            _final,
            context.tr(
                pl: 'Wymiar końcowy (po spawaniu)',
                en: 'Final dimension (after welding)'),
            key: const ValueKey('dist-final'),
            unit: 'mm'),
        _field(
            _buttCount,
            context.tr(
                pl: 'Spoiny czołowe w łańcuchu',
                en: 'Butt welds in the chain'),
            key: const ValueKey('dist-butt-count'),
            decimal: false),
        _label(context.tr(
            pl: 'Skurcz jednej spoiny czołowej',
            en: 'Shrinkage of one butt weld')),
        _chips([
          _choice('dist-src-estimate', estimateLabel, !_measuredMode,
              () => _measuredMode = false),
          _choice(
              'dist-src-measured',
              context.tr(pl: 'Mój pomiar', en: 'My measurement'),
              _measuredMode,
              () => _measuredMode = true),
        ]),
        if (_measuredMode)
          _field(
              _measured,
              context.tr(
                  pl: 'Zmierzony skurcz jednej spoiny',
                  en: 'Measured shrinkage of one weld'),
              key: const ValueKey('dist-measured'),
              unit: 'mm',
              helper: context.tr(
                  pl: 'Różnica wymiaru po sczepieniu i po spawaniu '
                      'pierwszego złącza.',
                  en: 'Difference between the dimension after tacking and '
                      'after welding the first joint.')),
        _field(
            _filletCount,
            context.tr(
                pl: 'Spoiny pachwinowe w poprzek łańcucha',
                en: 'Fillet welds across the chain'),
            key: const ValueKey('dist-fillet-count'),
            decimal: false,
            helper: context.tr(
                pl: 'TWI: ok. $fillet mm na spoinę, gdy noga ≤ ¾ grubości '
                    'blachy.',
                en: 'TWI: about $fillet mm per weld when the leg ≤ ¾ of the '
                    'plate thickness.')),
        if (problems.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('dist-preweld-problems'),
            child: QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: problems.map(_preWeldProblem).join('\n'),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 4),
          KeyedSubtree(
            key: const ValueKey('dist-preweld'),
            child: Readout(
              label: context.tr(
                  pl: 'Zestaw przed spawaniem', en: 'Set up before welding'),
              value: _f(r.preWeldLengthMm, 1),
              unit: context.tr(
                  pl: 'mm · w górę do 0,5 mm', en: 'mm · up to 0.5 mm'),
              hot: true,
            ),
          ),
          const SizedBox(height: 10),
          if (r.buttWelds > 0)
            _kv(
                context.tr(
                    pl: 'Spoiny czołowe ${r.buttWelds} × '
                        '${_n(r.perButtMm)} mm',
                    en: 'Butt welds ${r.buttWelds} × '
                        '${_n(r.perButtMm)} mm'),
                '${_n(r.buttShrinkageMm)} mm'),
          if (r.filletWelds > 0)
            _kv(
                context.tr(
                    pl: 'Spoiny pachwinowe ${r.filletWelds} × $fillet mm',
                    en: 'Fillet welds ${r.filletWelds} × $fillet mm'),
                '${_n(r.filletShrinkageMm)} mm'),
          _kv(context.tr(pl: 'Suma skurczu', en: 'Total shrinkage'),
              '${_n(r.totalShrinkageMm)} mm',
              key: const ValueKey('dist-total')),
          _kv(
              context.tr(
                  pl: 'Dodane przez zaokrąglenie', en: 'Added by rounding'),
              '+${_n(r.roundingAddMm)} mm'),
          _note(context.tr(
              pl: 'Zaokrąglamy W GÓRĘ: element za długi po spawaniu '
                  'dotniesz, za krótki trzeba by dospawać — drożej i z kolejną '
                  'spoiną, która też się kurczy.',
              en: 'Rounded UP: a part too long after welding can be trimmed, '
                  'one too short would need weld added — more costly, and '
                  'that weld shrinks too.')),
        ],
        _note(twiLongitudinalNote(en: _en)),
      ],
    );
  }

  // ── Sekcja 3: zapobieganie ─────────────────────────────────────────────

  Widget _preventSection(List<DistortionMeasure> measures) {
    return QuoteSection(
      title: context.tr(pl: 'Jak zapobiegać', en: 'How to prevent it'),
      subtitle: context.tr(
          pl: 'Wybierz element i odkształcenie — środki z uzasadnieniem '
              'i źródłem.',
          en: 'Choose the part and the distortion — measures with the '
              'reason and the source.'),
      children: [
        _label(context.tr(pl: 'Element', en: 'Part')),
        _chips([
          for (final e in DistortionElement.values)
            _choice('dist-el-${e.name}', e.label(en: _en), _element == e,
                () => _pickElement(e)),
        ]),
        _label(context.tr(pl: 'Odkształcenie', en: 'Distortion')),
        _chips([
          for (final k in kindsFor(_element))
            _choice('dist-kind-${k.name}', k.label(en: _en), _kind == k,
                () => _kind = k),
        ]),
        const Divider(height: 8, color: kBorder),
        for (final (i, m) in measures.indexed) ...[
          if (i > 0) const Divider(height: 20, color: kBorder),
          _measureTile(i + 1, m),
        ],
      ],
    );
  }

  Widget _measureTile(int n, DistortionMeasure m) {
    return Padding(
      key: ValueKey('dist-measure-${m.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$n. ${m.title(en: _en)}',
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: kText)),
          if (m.correction)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  context.tr(
                      pl: 'KOREKTA PO SPAWANIU', en: 'CORRECTION AFTER WELDING'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: kWarn)),
            ),
          const SizedBox(height: 4),
          Text(m.how(en: _en),
              style: const TextStyle(fontSize: 13.5, color: kText, height: 1.4)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: context.tr(pl: 'Dlaczego: ', en: 'Why: '),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: m.why(en: _en)),
            ]),
            style: const TextStyle(fontSize: 13, color: kTextSec, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text('${context.tr(pl: 'Źródło', en: 'Source')}: ${m.source}',
              style: const TextStyle(
                  fontSize: 11.5, color: kTextMut, height: 1.3)),
          if (m.link != null) ...[
            const SizedBox(height: 8),
            _linkButton(m.link!),
          ],
        ],
      ),
    );
  }

  Widget _linkButton(MeasureLink link) {
    final (key, label, icon) = switch (link) {
      MeasureLink.heatInput => (
          'dist-open-heat-input',
          context.tr(
              pl: 'Policz energię liniową', en: 'Work out the heat input'),
          Icons.local_fire_department_outlined,
        ),
      MeasureLink.flangeCheck => (
          'dist-open-flange-check',
          context.tr(
              pl: 'Odbiór połączenia kołnierzowego',
              en: 'Flange joint check'),
          Icons.adjust,
        ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: ValueKey(key),
        style: OutlinedButton.styleFrom(
          foregroundColor: kArc,
          side: BorderSide(color: kArc.withValues(alpha: 0.7)),
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: () => unawaited(_open(link)),
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
