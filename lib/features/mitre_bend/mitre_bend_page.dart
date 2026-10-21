// Kolano segmentowe (lobster back): ile segmentów, pod jakim kątem ciąć,
// długości po osi / gardle / grzbiecie, rzędne szablonu do trasowania
// i szablon 1:1 do druku. Dla montera, który nie ma kolana na magazynie
// (albo ma rurę DN600, a kolano kosztuje fortunę).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../data/pipe_schedules.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/fitter/mitre_bend.dart';
import '../../domain/quotes/quote_calculator.dart' show formatQty;
import '../../i18n/app_language.dart';
import '../../services/wrap_template_pdf.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';

String _mm(double v, {int d = 1}) => formatQty(v, decimals: d);

class MitreBendPage extends StatefulWidget {
  const MitreBendPage({super.key});

  @override
  State<MitreBendPage> createState() => _MitreBendPageState();
}

class _MitreBendPageState extends State<MitreBendPage>
    with ToolHandleHost<MitreBendPage> {
  @override
  String get toolId => 'mitre_bend';
  @override
  Set<String> get supportedFields =>
      const {'od_mm', 'angle_deg', 'welds', 'radius_mm', 'tangent_mm'};

  @override
  void initState() {
    super.initState();
    markReady();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || fields.keys.any((key) => !supportedFields.contains(key))) {
      return fields.keys.toSet();
    }
    final rejected = <String>{};
    for (final key in supportedFields) {
      final value = fields[key];
      if (value is! num || !value.isFinite) rejected.add(key);
    }
    if (rejected.isNotEmpty) return rejected;
    double n(String key) => (fields[key] as num).toDouble();
    final welds = n('welds');
    if (welds != welds.roundToDouble() || welds < 1 || welds > 12) {
      return {'welds'};
    }
    final input = MitreBendInput(
        odMm: n('od_mm'),
        bendAngleDeg: n('angle_deg'),
        welds: welds.toInt(),
        radiusMm: n('radius_mm'),
        tangentMm: n('tangent_mm'));
    if (computeMitreBend(input) == null) return fields.keys.toSet();
    setState(() {
      _dn = null;
      _od.text = input.odMm.toString();
      _angle.text = input.bendAngleDeg.toString();
      _welds = input.welds;
      _radiusFactor = null;
      _radius.text = input.radiusMm.toString();
      _tangent.text = input.tangentMm.toString();
    });
    return {};
  }

  final _od = TextEditingController(text: '168,3');
  final _angle = TextEditingController(text: '90');
  final _radius = TextEditingController();
  final _tangent = TextEditingController(text: '0');
  int? _dn = 150;
  int _welds = 3;

  /// Promień jako wielokrotność D (null = wpisany w mm).
  double? _radiusFactor = 1.5;
  bool _exporting = false;

  @override
  void dispose() {
    for (final c in [_od, _angle, _radius, _tangent]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _odMm => parseDecimal(_od.text) ?? 0;

  double get _radiusMm => _radiusFactor != null
      ? _radiusFactor! * _odMm
      : (parseDecimal(_radius.text) ?? 0);

  MitreBendInput get _input => MitreBendInput(
        odMm: _odMm,
        bendAngleDeg: parseDecimal(_angle.text) ?? 0,
        welds: _welds,
        radiusMm: _radiusMm,
        tangentMm: parseDecimal(_tangent.text) ?? 0,
      );

  void _pickDn(int? dn) {
    final row = kPipeWalls.where((r) => r.dn == dn).firstOrNull;
    setState(() {
      _dn = dn;
      if (row != null) _od.text = numText(row.od);
    });
  }

  String _problemText(MitreProblem p) => switch (p) {
        MitreProblem.od => context.tr(
            pl: 'Podaj średnicę zewnętrzną (do 3000 mm).',
            en: 'Enter the outside diameter (up to 3000 mm).'),
        MitreProblem.angle => context.tr(
            pl: 'Kąt kolana 1–180°, a na jednej spoinie mniej niż 180°.',
            en: 'Bend angle 1–180°, less than 180° per weld.'),
        MitreProblem.welds =>
          context.tr(pl: 'Od 1 do 12 spoin.', en: 'From 1 to 12 welds.'),
        MitreProblem.radius =>
          context.tr(pl: 'Podaj promień gięcia.', en: 'Enter the bend radius.'),
        MitreProblem.radiusTooSmall => context.tr(
            pl: 'Promień musi być większy niż połowa średnicy — inaczej '
                'segmenty nachodzą na siebie od strony gardła.',
            en: 'The radius must exceed half the diameter — otherwise the '
                'segments overlap on the throat side.'),
        MitreProblem.tangent => context.tr(
            pl: 'Odcinek prosty nie może być ujemny.',
            en: 'The straight length cannot be negative.'),
        MitreProblem.tangentTooShort => context.tr(
            pl: 'Przy jednym cięciu odcinek prosty musi być dłuższy niż '
                'skos od strony gardła — zwiększ go.',
            en: 'With a single cut the straight length must exceed the '
                'throat-side slant — increase it.'),
      };

  Future<void> _sharePdf(MitreBendResult r) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final en = context.language == AppLanguage.en;
    try {
      final spec = _templateSpec(r, en);
      final bytes = await buildWrapTemplatePdf(
        spec,
        font: pw.Font.ttf(
            await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
        bold:
            pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
        en: en,
        generatedAt: DateTime.now(),
      );
      if (kIsWeb) {
        await Share.shareXFiles([
          XFile.fromData(bytes,
              mimeType: 'application/pdf', name: 'kolano_segmentowe.pdf')
        ]);
      } else {
        final dir = await getTemporaryDirectory();
        final name =
            'kolano_${_mm(r.input.odMm, d: 0)}_${_mm(r.input.bendAngleDeg, d: 0)}st_${r.input.welds}sp.pdf';
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/pdf', name: name)],
            subject:
                en ? 'Mitred bend template' : 'Szablon kolana segmentowego');
      }
      Haptic.saved();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się przygotować szablonu.',
              en: 'Could not prepare the template.'))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  WrapTemplateSpec _templateSpec(MitreBendResult r, bool en) {
    String tr(String pl, String e) => en ? e : pl;
    final i = r.input;
    final pts = r.templatePoints(16);
    return WrapTemplateSpec(
      title: tr('Szablon cięcia — kolano segmentowe',
          'Cutting template — mitred bend'),
      summaryLines: [
        'OD ${_mm(i.odMm)} mm · ${tr('kolano', 'bend')} ${_mm(i.bendAngleDeg)}° · '
            '${i.welds} ${tr('spoin(y)', 'weld(s)')}'
            '${i.welds > 1 ? ' · R ${_mm(i.radiusMm)} mm' : ''}',
        '${tr('Kąt cięcia', 'Cut angle')} β = ${_mm(r.cutAngleDeg, d: 2)}° · '
            '${tr('różnica gardło–grzbiet na cięciu', 'throat–heel drop per cut')} '
            '${_mm(r.cutDropMm)} mm · ${tr('obwód', 'circumference')} ${_mm(r.circumferenceMm)} mm',
        if (r.fullSegment != null)
          '${tr('Segment pełny', 'Full segment')} × ${r.fullSegments}: '
              '${tr('oś', 'centre')} ${_mm(r.fullSegment!.centreMm)} · '
              '${tr('gardło', 'throat')} ${_mm(r.fullSegment!.throatMm)} · '
              '${tr('grzbiet', 'heel')} ${_mm(r.fullSegment!.heelMm)} mm',
        '${tr('Segment końcowy', 'End piece')} × 2: '
            '${tr('oś', 'centre')} ${_mm(r.endPiece.centreMm)} · '
            '${tr('gardło', 'throat')} ${_mm(r.endPiece.throatMm)} · '
            '${tr('grzbiet', 'heel')} ${_mm(r.endPiece.heelMm)} mm',
      ],
      stripLengthMm: r.circumferenceMm,
      maxDepthMm: r.cutDropMm,
      depthAt: (x) => r.pointAt(x / r.circumferenceMm * 360).offsetMm,
      tableHeaders: [
        tr('Punkt', 'Point'),
        tr('Kąt od gardła', 'Angle from throat'),
        tr('Łuk od gardła (mm)', 'Arc from throat (mm)'),
        tr('Odsunięcie (mm)', 'Offset (mm)'),
      ],
      tableRows: [
        for (final (n, p) in pts.indexed)
          [
            '$n',
            '${_mm(p.phiDeg, d: 1)}°',
            _mm(p.arcMm),
            _mm(p.offsetMm),
          ],
      ],
      instructions: [
        tr(
            'Linia bazowa Y = 0 prostopadła do osi rury, przez punkt gardła (wewnętrzna strona łuku, 0°). '
                'Odsunięcie mierz od linii bazowej w stronę cięcia; X odmierzaj po obwodzie.',
            'Base line Y = 0 square to the pipe axis, through the throat point (inside of the bend, 0°). '
                'Measure the offset from the base line towards the cut; X runs round the circumference.'),
        tr(
            'Segment pełny: tak samo na obu końcach, grzbiety po tej samej stronie rury. '
                'Kolejne segmenty z jednej rury: obracaj szablon o 180° — mniej odpadu.',
            'Full segment: the same on both ends, heels on the same side of the pipe. '
                'Consecutive segments from one pipe: turn the template by 180° — less waste.'),
      ],
      note: tr(
          'Geometria powierzchni zewnętrznej — bez ukosowania, szczeliny i rzazu piły. '
              'W rurociągach ciśnieniowych kolano segmentowe tylko wtedy, gdy dopuszcza je projekt '
              '(ASME B31.3 §304.2.3).',
          'Outside-surface geometry — no bevel, gap or saw kerf. '
              'In pressure piping a mitred bend only where the design allows it (ASME B31.3 §304.2.3).'),
      tileHint: tr(
          '+Y: w stronę cięcia. Grube kreski: 0°/90°/180°/270° (0° = gardło).',
          '+Y: towards the cut. Thick lines: 0°/90°/180°/270° (0° = throat).'),
    );
  }

  Widget _numField(TextEditingController c, String label,
          {String? unit, String? helper, Key? key}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 2,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final input = _input;
    final problems = input.problems;
    final r = computeMitreBend(input);
    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(pl: 'Kolano segmentowe', en: 'Mitred bend'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          QuoteSection(
            title: context.tr(pl: 'Rura', en: 'Pipe'),
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey('mitre-dn-${_dn ?? 0}'),
                initialValue: _dn,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'DN / NPS',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  for (final row in kPipeWalls)
                    DropdownMenuItem(
                      value: row.dn,
                      child: Text(
                          'DN${row.dn}  ·  ${row.nps}"  ·  Ø${numText(row.od)}'),
                    ),
                ],
                onChanged: _pickDn,
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('mitre-od'),
                controller: _od,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                onChanged: (_) => setState(() {
                  final od = parseDecimal(_od.text);
                  final row = kPipeWalls
                      .where((r) => od != null && (r.od - od).abs() < 0.05)
                      .firstOrNull;
                  _dn = row?.dn;
                }),
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Średnica OD', en: 'Outside dia.'),
                  suffixText: 'mm',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          QuoteSection(
            title: context.tr(pl: 'Kolano', en: 'Bend'),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in const [90, 60, 45, 30])
                    ChoiceChip(
                      key: ValueKey('mitre-angle-$a'),
                      label: Text('$a°'),
                      selected: parseDecimal(_angle.text) == a,
                      onSelected: (_) => setState(() => _angle.text = '$a'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _numField(_angle, context.tr(pl: 'Kąt kolana', en: 'Bend angle'),
                  unit: '°', key: const ValueKey('mitre-angle')),
              const SizedBox(height: 14),
              Text(
                  context.tr(
                      pl: 'Liczba spoin (cięć)', en: 'Number of welds (cuts)'),
                  style: const TextStyle(color: kTextSec, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var w = 1; w <= 12; w++)
                    ChoiceChip(
                      key: ValueKey('mitre-welds-$w'),
                      label: Text('$w'),
                      selected: _welds == w,
                      onSelected: (_) => setState(() => _welds = w),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _welds == 1
                    ? context.tr(
                        pl:
                            'Jedno cięcie: dwa kawałki, kolano ostre (bez promienia).',
                        en: 'One cut: two pieces, a sharp bend (no radius).')
                    : context.tr(
                        pl: '${_welds - 1} segm. pełne + 2 końcowe (połówki).',
                        en: '${_welds - 1} full segment(s) + 2 end pieces (halves).'),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
              if (_welds > 1) ...[
                const SizedBox(height: 14),
                Text(
                    context.tr(
                        pl: 'Promień gięcia (po osi)',
                        en: 'Bend radius (centreline)'),
                    style: const TextStyle(color: kTextSec, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in const [1.0, 1.5, 2.0, 3.0])
                      ChoiceChip(
                        key: ValueKey('mitre-r-$f'),
                        label: Text('${formatQty(f)}D'),
                        selected: _radiusFactor == f,
                        onSelected: (_) => setState(() => _radiusFactor = f),
                      ),
                    ChoiceChip(
                      key: const ValueKey('mitre-r-mm'),
                      label: Text(context.tr(pl: 'w mm', en: 'in mm')),
                      selected: _radiusFactor == null,
                      onSelected: (_) => setState(() {
                        if (_radius.text.trim().isEmpty && _odMm > 0) {
                          _radius.text = numText(1.5 * _odMm);
                        }
                        _radiusFactor = null;
                      }),
                    ),
                  ],
                ),
                if (_radiusFactor == null) ...[
                  const SizedBox(height: 10),
                  _numField(
                      _radius, context.tr(pl: 'Promień R', en: 'Radius R'),
                      unit: 'mm', key: const ValueKey('mitre-radius')),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('R = ${_mm(_radiusMm)} mm',
                        style: const TextStyle(fontSize: 12, color: kTextMut)),
                  ),
              ],
              const SizedBox(height: 14),
              _numField(
                _tangent,
                context.tr(
                    pl: 'Prosty odcinek na końcach',
                    en: 'Straight length at the ends'),
                unit: 'mm',
                helper: context.tr(
                    pl: 'Doklejany do obu segmentów końcowych (np. do spoiny z rurą).',
                    en: 'Added to both end pieces (e.g. to weld to the pipe).'),
                key: const ValueKey('mitre-tangent'),
              ),
            ],
          ),
          if (problems.isNotEmpty || r == null)
            QuoteNotice(
              color: kFail,
              icon: Icons.error_outline,
              text: problems.isEmpty
                  ? context.tr(
                      pl: 'Wynik poza zakresem. Sprawdź wymiary.',
                      en: 'Result out of range. Check dimensions.')
                  : problems.map(_problemText).join('\n'),
            )
          else ...[
            QuoteSection(
              title: context.tr(pl: 'Cięcie', en: 'Cut'),
              children: [
                Readout(
                  label: context.tr(
                      pl: 'Kąt cięcia β (od prostopadłej)',
                      en: 'Cut angle β (from square)'),
                  value: _mm(r.cutAngleDeg, d: 2),
                  unit: context.tr(
                      pl: '° · ustaw piłę / palnik',
                      en: '° · set the saw / torch'),
                  hot: true,
                ),
                const SizedBox(height: 12),
                _kv(
                    context.tr(
                        pl: 'Zmiana kierunku na spoinie', en: 'Turn per weld'),
                    '${_mm(r.jointDeflectionDeg, d: 2)}°'),
                _kv(
                    context.tr(
                        pl: 'Różnica gardło–grzbiet na jednym cięciu',
                        en: 'Throat–heel drop per cut'),
                    '${_mm(r.cutDropMm)} mm'),
                _kv(
                    context.tr(
                        pl: 'Długość jednej spoiny', en: 'Length of one weld'),
                    '${_mm(r.weldLengthMm, d: 0)} mm'),
                _kv(
                    context.tr(
                        pl: 'Rura do zużycia (po osi)',
                        en: 'Pipe needed (centreline)'),
                    '${_mm(r.pipeNeededMm, d: 0)} mm + ${context.tr(pl: 'rzazy', en: 'kerfs')}'),
              ],
            ),
            QuoteSection(
              title: context.tr(pl: 'Segmenty', en: 'Segments'),
              children: [
                _BendDiagram(result: r),
                const SizedBox(height: 12),
                _pieceTable(context, r, en),
              ],
            ),
            QuoteSection(
              title: context.tr(
                  pl: 'Szablon do trasowania', en: 'Marking template'),
              subtitle: context.tr(
                  pl: 'Obwód podzielony na 16 części. Odsunięcie od linii bazowej przez gardło (0°).',
                  en: 'Circumference in 16 parts. Offset from the base line through the throat (0°).'),
              children: [
                _ordinates(context, r),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('mitre-pdf'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: kArc,
                    foregroundColor: kOnArc,
                  ),
                  onPressed: _exporting ? null : () => unawaited(_sharePdf(r)),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(
                      context.tr(
                          pl: 'Szablon 1:1 do druku (PDF)',
                          en: '1:1 printable template (PDF)'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            QuoteNotice(
              text: context.tr(
                  pl: 'Geometria powierzchni zewnętrznej — bez ukosowania, szczeliny i rzazu. '
                      'W rurociągach ciśnieniowych kolano segmentowe tylko wtedy, gdy dopuszcza je '
                      'projekt (ASME B31.3 §304.2.3 — obliczenie i ograniczenia kąta).',
                  en: 'Outside-surface geometry — no bevel, gap or kerf. In pressure piping a mitred '
                      'bend only where the design allows it (ASME B31.3 §304.2.3 — calculation and '
                      'angle limits).'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => CopyOnLongPress(
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              Text(v,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      );

  Widget _pieceTable(BuildContext context, MitreBendResult r, bool en) {
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
          children: [
            for (final c in cells)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(c,
                    textAlign:
                        c == cells.first ? TextAlign.left : TextAlign.right,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: head ? FontWeight.w800 : FontWeight.w600,
                      color: head ? kTextSec : kText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
          ],
        );
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6)},
      border: const TableBorder(
          horizontalInside: BorderSide(color: kBorder, width: 1)),
      children: [
        row([
          context.tr(pl: 'mm', en: 'mm'),
          context.tr(pl: 'oś', en: 'centre'),
          context.tr(pl: 'gardło', en: 'throat'),
          context.tr(pl: 'grzbiet', en: 'heel'),
        ], head: true),
        if (r.fullSegment != null)
          row([
            context.tr(
                pl: 'Pełny × ${r.fullSegments}',
                en: 'Full × ${r.fullSegments}'),
            _mm(r.fullSegment!.centreMm),
            _mm(r.fullSegment!.throatMm),
            _mm(r.fullSegment!.heelMm),
          ]),
        row([
          context.tr(pl: 'Końcowy × 2', en: 'End × 2'),
          _mm(r.endPiece.centreMm),
          _mm(r.endPiece.throatMm),
          _mm(r.endPiece.heelMm),
        ]),
      ],
    );
  }

  Widget _ordinates(BuildContext context, MitreBendResult r) {
    final pts = r.templatePoints(16);
    final text = pts
        .map((p) =>
            '${_mm(p.phiDeg, d: 1)}°: ${_mm(p.arcMm)} → ${_mm(p.offsetMm)} mm')
        .join('\n');
    return CopyOnLongPress(
      value: text,
      label: context.tr(pl: 'Rzędne szablonu', en: 'Template ordinates'),
      child: Table(
        border: const TableBorder(
            horizontalInside: BorderSide(color: kBorder, width: 0.6)),
        children: [
          TableRow(children: [
            for (final h in [
              '#',
              context.tr(pl: 'kąt', en: 'angle'),
              context.tr(pl: 'łuk mm', en: 'arc mm'),
              context.tr(pl: 'odsun. mm', en: 'offset mm'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(h,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: kTextMut,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          for (final (n, p) in pts.indexed)
            TableRow(children: [
              for (final c in [
                '$n',
                '${_mm(p.phiDeg, d: 1)}°',
                _mm(p.arcMm),
                _mm(p.offsetMm),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(c,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: n % 4 == 0 ? kArc : kText,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
            ]),
        ],
      ),
    );
  }
}

/// Rysunek kolana: segmenty jako czworoboki wzdłuż łamanej osi.
class _BendDiagram extends StatelessWidget {
  final MitreBendResult result;
  const _BendDiagram({required this.result});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: CustomPaint(painter: _BendPainter(result)),
    );
  }
}

class _BendPainter extends CustomPainter {
  final MitreBendResult r;
  _BendPainter(this.r);

  @override
  void paint(Canvas canvas, Size size) {
    final i = r.input;
    final half = i.odMm / 2;
    final alpha = r.jointDeflectionDeg * math.pi / 180;
    final beta = r.cutAngleDeg * math.pi / 180;
    // Długości kolejnych kawałków po osi.
    final lengths = <double>[
      r.endPiece.centreMm,
      for (var k = 0; k < r.fullSegments; k++) r.fullSegment!.centreMm,
      r.endPiece.centreMm,
    ];
    // Punkty osi i kierunki; zakręt w lewo (gardło po lewej).
    var dir = 0.0;
    var p = Offset.zero;
    final axis = <Offset>[p];
    final dirs = <double>[];
    for (var k = 0; k < lengths.length; k++) {
      dirs.add(dir);
      p = p + Offset(math.cos(dir), math.sin(dir)) * lengths[k];
      axis.add(p);
      if (k < lengths.length - 1) dir += alpha;
    }
    // Krawędzie cięcia w punktach spoin (dwusieczna), proste na końcach.
    List<Offset> cutAt(int k) {
      final d = k == 0
          ? dirs.first
          : k == axis.length - 1
              ? dirs.last
              : (dirs[k - 1] + dirs[k]) / 2;
      final n = Offset(-math.sin(d), math.cos(d));
      final reach =
          (k == 0 || k == axis.length - 1) ? half : half / math.cos(beta);
      return [axis[k] + n * reach, axis[k] - n * reach];
    }

    final cuts = [for (var k = 0; k < axis.length; k++) cutAt(k)];
    final all = [for (final c in cuts) ...c];
    var minX = all.first.dx, maxX = all.first.dx;
    var minY = all.first.dy, maxY = all.first.dy;
    for (final o in all) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    const pad = 12.0;
    final s = math.min((size.width - 2 * pad) / math.max(maxX - minX, 1),
        (size.height - 2 * pad) / math.max(maxY - minY, 1));
    // Oś Y ekranu w dół — odwracamy, żeby kolano szło w górę.
    Offset map(Offset o) => Offset(
          pad +
              (o.dx - minX) * s +
              ((size.width - 2 * pad) - (maxX - minX) * s) / 2,
          size.height -
              pad -
              (o.dy - minY) * s -
              ((size.height - 2 * pad) - (maxY - minY) * s) / 2,
        );
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = kText;
    for (var k = 0; k < lengths.length; k++) {
      final a = cuts[k], b = cuts[k + 1];
      final path = Path()
        ..moveTo(map(a[0]).dx, map(a[0]).dy)
        ..lineTo(map(b[0]).dx, map(b[0]).dy)
        ..lineTo(map(b[1]).dx, map(b[1]).dy)
        ..lineTo(map(a[1]).dx, map(a[1]).dy)
        ..close();
      fill.color = (k == 0 || k == lengths.length - 1)
          ? kTextMut.withValues(alpha: 0.25)
          : kArc.withValues(alpha: k.isEven ? 0.28 : 0.18);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
    // Spoiny na granicach segmentów.
    final weld = Paint()
      ..color = kArc
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var k = 1; k < cuts.length - 1; k++) {
      canvas.drawLine(map(cuts[k][0]), map(cuts[k][1]), weld);
    }
    // Oś.
    final axisPaint = Paint()
      ..color = kTextSec
      ..strokeWidth = 1;
    for (var k = 0; k < axis.length - 1; k++) {
      canvas.drawLine(map(axis[k]), map(axis[k + 1]), axisPaint);
    }
  }

  @override
  bool shouldRepaint(_BendPainter old) => old.r != r;
}
