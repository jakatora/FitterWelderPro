// Dodawanie / edycja pozycji wyceny: rodzaj złącza, rozmiar (DN + Sch albo
// ręcznie), rowek, liczba, pozycja, proces, czas przygotowania. Na dole
// podgląd: stopiwo, czasy i koszt pozycji liczone na żywo.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/pipe_schedules.dart';
import '../../domain/quotes/quote_calculator.dart';
import '../../domain/quotes/quote_labels.dart';
import '../../domain/quotes/quote_process.dart';
import '../../domain/quotes/weld_geometry.dart';
import '../../domain/quotes/weld_quote.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import 'quote_widgets.dart';

/// Przygotowanie rowka rury: faza 30° (EN ISO 9692-1, α = 60°) albo
/// 37,5° (ASME B16.25, α = 75°, próg 1,6 mm).
class _BevelPreset {
  final String id;
  final String labelPl;
  final String labelEn;
  final double angle;
  final double rootFace;
  final double gap;
  const _BevelPreset(
      this.id, this.labelPl, this.labelEn, this.angle, this.rootFace, this.gap);
}

const _kPipeBevels = [
  _BevelPreset('EN', 'Faza 30° (EN 9692)', 'Bevel 30° (EN 9692)', 60, 1.5, 2.5),
  _BevelPreset('ASME', 'Faza 37,5° (ASME B16.25)', 'Bevel 37.5° (ASME B16.25)',
      75, 1.6, 3.0),
];

class QuoteJointPage extends StatefulWidget {
  /// Wycena, do której należy pozycja (materiał, schemat, stawki — podgląd).
  final WeldQuote quote;

  /// Edytowana pozycja; `null` = nowa.
  final QuoteJoint? joint;

  const QuoteJointPage({super.key, required this.quote, this.joint});

  @override
  State<QuoteJointPage> createState() => _QuoteJointPageState();
}

class _QuoteJointPageState extends State<QuoteJointPage> {
  late QuoteJoint _j;

  late final TextEditingController _od;
  late final TextEditingController _wall;
  late final TextEditingController _throat;
  late final TextEditingController _length;
  late final TextEditingController _count;
  late final TextEditingController _angle;
  late final TextEditingController _rootFace;
  late final TextEditingController _gap;
  late final TextEditingController _prep;
  late final TextEditingController _label;

  int? _dn;
  String? _sch;
  int? _headerDn;

  bool get _stainless =>
      widget.quote.material == QuoteMaterial.stainless ||
      widget.quote.material == QuoteMaterial.duplex;

  @override
  void initState() {
    super.initState();
    _j = widget.joint ??
        QuoteJoint(
          id: const Uuid().v4(),
          kind: JointKind.pipeButt,
          position: widget.quote.site == QuoteSite.shop
              ? WeldPosition.pa
              : WeldPosition.pf,
        );
    _od = TextEditingController(text: numText(_j.odMm > 0 ? _j.odMm : null));
    _wall =
        TextEditingController(text: numText(_j.wallMm > 0 ? _j.wallMm : null));
    _throat = TextEditingController(
        text: numText(_j.throatMm > 0 ? _j.throatMm : null));
    _length = TextEditingController(
        text: numText(_j.lengthM > 0 ? _j.lengthM : null));
    _count = TextEditingController(text: '${_j.count}');
    _angle = TextEditingController(text: numText(_j.angleDeg));
    _rootFace = TextEditingController(text: numText(_j.rootFaceMm));
    _gap = TextEditingController(text: numText(_j.gapMm));
    _prep = TextEditingController(text: numText(_j.prepMinutes, decimals: 0));
    _label = TextEditingController(text: _j.label);
    // Rozpoznaj DN / Sch zapisanej pozycji, żeby lista pokazała wybór.
    final row = _rowForOd(_j.odMm);
    if (row != null) {
      _dn = row.dn;
      for (final e in row.walls.entries) {
        if (e.value != null && (e.value! - _j.wallMm).abs() < 0.005) {
          _sch = e.key;
          break;
        }
      }
    }
    _headerDn = _rowForOd(_j.headerOdMm)?.dn;
  }

  @override
  void dispose() {
    for (final c in [
      _od,
      _wall,
      _throat,
      _length,
      _count,
      _angle,
      _rootFace,
      _gap,
      _prep,
      _label,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  PipeRow? _rowForOd(double od) {
    if (od <= 0) return null;
    for (final r in kPipeWalls) {
      if ((r.od - od).abs() <= 0.05) return r;
    }
    return null;
  }

  PipeRow? get _row =>
      _dn == null ? null : kPipeWalls.where((r) => r.dn == _dn).firstOrNull;

  List<String> get _schedules => schedulesFor(stainless: _stainless)
      .where((s) => _row?.walls[s] != null)
      .toList();

  void _update(QuoteJoint j) => setState(() => _j = j);

  void _setText(TextEditingController c, double? v, {int decimals = 2}) {
    c.text = numText(v, decimals: decimals);
  }

  String _sizeLabel() {
    final row = _row;
    if (row == null) return '';
    final sch = _sch;
    return sch == null ? 'DN${row.dn}' : 'DN${row.dn} Sch $sch';
  }

  void _pickDn(int? dn) {
    _dn = dn;
    final row = _row;
    if (row == null) return;
    if (_sch == null || row.walls[_sch] == null) {
      final list = _schedules;
      _sch = list.contains(_stainless ? '10S' : 'STD')
          ? (_stainless ? '10S' : 'STD')
          : (list.isEmpty ? null : list.first);
    }
    _applyRow();
  }

  void _pickSch(String sch) {
    _sch = sch;
    _applyRow();
  }

  void _applyRow() {
    final row = _row;
    if (row == null) return;
    final wall = _sch == null ? null : row.walls[_sch];
    _setText(_od, row.od);
    if (wall != null) _setText(_wall, wall);
    var j = _j.copyWith(
      odMm: row.od,
      wallMm: wall ?? _j.wallMm,
      sizeLabel: _sizeLabel(),
    );
    // Mufa SW wg ASME B31.3 rys. 328.5.2C: noga Cx ≥ 1,09·t ścianki rury →
    // grubość obliczeniowa a ≈ 0,77·t; zaokrąglone w górę do 0,5, min. 3.
    if (j.kind == JointKind.pipeFillet && wall != null) {
      final a = ((0.77 * wall) * 2).ceil() / 2;
      final throat = a < 3 ? 3.0 : a;
      _setText(_throat, throat);
      j = j.copyWith(throatMm: throat);
    }
    _update(j);
  }

  void _pickHeader(int? dn) {
    _headerDn = dn;
    final row = kPipeWalls.where((r) => r.dn == dn).firstOrNull;
    _update(_j.copyWith(headerOdMm: row?.od ?? 0));
  }

  void _setKind(JointKind k) {
    var j = _j.copyWith(kind: k);
    if (k == JointKind.branch) {
      j = j.copyWith(angleDeg: 45, rootFaceMm: 1.5, gapMm: 2.5);
    } else if (k == JointKind.pipeButt || k == JointKind.plateButt) {
      // Z rodzaju bez rowka V (króciec ½V 45°, pachwina) wracamy na typową
      // fazę 30° — inaczej po drodze króciec → pachwina → doczołowa
      // zostałby kąt 45° fazy króćca.
      final wasButt =
          _j.kind == JointKind.pipeButt || _j.kind == JointKind.plateButt;
      if (!wasButt) {
        j = j.copyWith(angleDeg: 60, rootFaceMm: 1.5, gapMm: 2.5);
      }
    }
    if (k == JointKind.plateButt || k == JointKind.plateFillet) {
      j = j.copyWith(sizeLabel: '');
    } else if (j.groove == GrooveType.x) {
      j = j.copyWith(groove: GrooveType.v);
    }
    _setText(_angle, j.angleDeg);
    _setText(_rootFace, j.rootFaceMm);
    _setText(_gap, j.gapMm);
    _update(j);
    if (k == JointKind.pipeFillet && _j.throatMm <= 0 && _row != null) {
      _applyRow();
    }
  }

  void _applyBevel(_BevelPreset p) {
    _setText(_angle, p.angle);
    _setText(_rootFace, p.rootFace);
    _setText(_gap, p.gap);
    _update(_j.copyWith(
        angleDeg: p.angle,
        rootFaceMm: p.rootFace,
        gapMm: p.gap,
        groove: GrooveType.v));
  }

  void _bumpCount(int delta) {
    final n = (_j.count + delta).clamp(1, 99999);
    _count.text = '$n';
    _update(_j.copyWith(count: n));
  }

  void _save() {
    final j = _j.copyWith(label: _label.text.trim());
    if (!j.isValid) {
      Haptic.error();
      return;
    }
    Haptic.saved();
    Navigator.of(context).pop(j);
  }

  // ─── Widoki ───────────────────────────────────────────────────────────────

  Widget _numField(
    TextEditingController c,
    String label, {
    String? unit,
    String? helper,
    required ValueChanged<double?> onChanged,
    bool decimal = true,
  }) =>
      TextField(
        controller: c,
        keyboardType: numberKeyboard(decimal: decimal),
        inputFormatters: numberInputFormatters(decimal: decimal),
        onChanged: (t) => onChanged(parseDecimal(t)),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _kindChips(bool en) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in JointKind.values)
            ChoiceChip(
              key: ValueKey('kind-${k.code}'),
              label: Text(jointKindShort(k, en: en)),
              avatar: Icon(_kindIcon(k), size: 18),
              selected: _j.kind == k,
              onSelected: (_) => _setKind(k),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      );

  static IconData _kindIcon(JointKind k) => switch (k) {
        JointKind.pipeButt => Icons.horizontal_rule,
        JointKind.pipeFillet => Icons.radio_button_unchecked,
        JointKind.branch => Icons.call_split,
        JointKind.plateButt => Icons.view_agenda_outlined,
        JointKind.plateFillet => Icons.turn_slight_right,
      };

  Widget _dnDropdown({
    required Key key,
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) =>
      DropdownButtonFormField<int>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final r in kPipeWalls)
            DropdownMenuItem(
              value: r.dn,
              child: Text('DN${r.dn}  ·  ${r.nps}"  ·  Ø${numText(r.od)}'),
            ),
        ],
        onChanged: onChanged,
      );

  Widget _pipeSize(bool en) {
    final kind = _j.kind;
    return QuoteSection(
      title: kind == JointKind.branch
          ? context.tr(pl: 'Króciec', en: 'Branch')
          : context.tr(pl: 'Rura', en: 'Pipe'),
      subtitle: context.tr(
          pl: 'Wybierz DN i grubość ścianki z tabeli albo wpisz wymiary ręcznie.',
          en: 'Pick DN and schedule from the table or type the dimensions.'),
      children: [
        _dnDropdown(
          // Klucz z wartością: ręczna zmiana OD przestawia listę.
          key: ValueKey('dn-${_dn ?? 0}'),
          label: 'DN / NPS',
          value: _dn,
          onChanged: (v) => setState(() => _pickDn(v)),
        ),
        if (_row != null && kind != JointKind.pipeFillet) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _schedules)
                ChoiceChip(
                  key: ValueKey('sch-$s'),
                  label: Text('Sch $s · ${numText(_row!.walls[s])}'),
                  selected: _sch == s,
                  onSelected: (_) => setState(() => _pickSch(s)),
                ),
            ],
          ),
        ],
        if (_row != null && kind == JointKind.pipeFillet) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _schedules)
                ChoiceChip(
                  key: ValueKey('sch-$s'),
                  label: Text('Sch $s'),
                  selected: _sch == s,
                  onSelected: (_) => setState(() => _pickSch(s)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FieldPair(
          left: _numField(
              _od, context.tr(pl: 'Średnica OD', en: 'Outside dia.'),
              unit: 'mm', onChanged: (v) {
            _update(_j.copyWith(
                odMm: v ?? 0, sizeLabel: _matchingLabel(v, _j.wallMm)));
          }),
          right: kind == JointKind.pipeFillet
              ? _numField(
                  _throat, context.tr(pl: 'Grubość spoiny a', en: 'Throat a'),
                  unit: 'mm',
                  helper: context.tr(
                      pl: 'Mufa SW (B31.3): a ≈ 0,77 × ścianka rury',
                      en: 'Socket weld (B31.3): a ≈ 0.77 × pipe wall'),
                  onChanged: (v) => _update(_j.copyWith(throatMm: v ?? 0)))
              : _numField(_wall, context.tr(pl: 'Ścianka t', en: 'Wall t'),
                  unit: 'mm', onChanged: (v) {
                  _update(_j.copyWith(
                      wallMm: v ?? 0, sizeLabel: _matchingLabel(_j.odMm, v)));
                }),
        ),
        if (kind == JointKind.pipeFillet) ...[
          const SizedBox(height: 10),
          _numField(
              _wall,
              context.tr(
                  pl: 'Ścianka rury (opcjonalnie)', en: 'Pipe wall (optional)'),
              unit: 'mm',
              onChanged: (v) => _update(_j.copyWith(wallMm: v ?? 0))),
        ],
        if (kind == JointKind.branch) ...[
          const SizedBox(height: 12),
          _dnDropdown(
            key: ValueKey('header-dn-${_headerDn ?? 0}'),
            label: context.tr(pl: 'Rura główna (DN)', en: 'Header (DN)'),
            value: _headerDn,
            onChanged: (v) => _pickHeader(v),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Długość spoiny liczona z linii przenikania króćca z rurą główną.',
                en: 'Weld length from the branch–header intersection line.'),
            style: const TextStyle(fontSize: 11.5, color: kTextMut),
          ),
        ],
      ],
    );
  }

  /// Etykieta „DN… Sch …" zostaje tylko, gdy ręczne wymiary dalej jej
  /// odpowiadają — inaczej oferta pokazałaby rozmiar, którego nie liczono.
  String _matchingLabel(double? od, double? wall) {
    final row = _row;
    if (row == null || od == null || (row.od - od).abs() > 0.05) {
      _dn = _rowForOd(od ?? 0)?.dn;
      _sch = null;
      return '';
    }
    final w = _sch == null ? null : row.walls[_sch];
    if (w == null || wall == null || (w - wall).abs() > 0.005) {
      _sch = null;
      return 'DN${row.dn}';
    }
    return _sizeLabel();
  }

  Widget _plateSize(bool en) {
    final fillet = _j.kind == JointKind.plateFillet;
    return QuoteSection(
      title: context.tr(pl: 'Blacha / spoina', en: 'Plate / weld'),
      children: [
        FieldPair(
          left: fillet
              ? _numField(
                  _throat, context.tr(pl: 'Grubość spoiny a', en: 'Throat a'),
                  unit: 'mm',
                  onChanged: (v) => _update(_j.copyWith(throatMm: v ?? 0)))
              : _numField(_wall,
                  context.tr(pl: 'Grubość blachy t', en: 'Plate thickness t'),
                  unit: 'mm',
                  onChanged: (v) => _update(_j.copyWith(wallMm: v ?? 0))),
          right: _numField(_length,
              context.tr(pl: 'Długość jednej spoiny', en: 'Length of one weld'),
              unit: 'm',
              onChanged: (v) => _update(_j.copyWith(lengthM: v ?? 0))),
        ),
      ],
    );
  }

  Widget _groove(bool en) {
    final kind = _j.kind;
    if (kind.isFillet) return const SizedBox.shrink();
    final branch = kind == JointKind.branch;
    return QuoteSection(
      title: context.tr(pl: 'Rowek', en: 'Groove'),
      subtitle: branch
          ? context.tr(
              pl: 'Faza na króćcu (½V) + spoina pachwinowa przykrywająca '
                  'tc = min(0,7·t; 6 mm) wg ASME B31.3.',
              en: 'Bevel on the branch (½V) + cover fillet '
                  'tc = min(0.7·t; 6 mm) per ASME B31.3.')
          : null,
      children: [
        if (kind == JointKind.pipeButt)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _kPipeBevels)
                ChoiceChip(
                  key: ValueKey('bevel-${p.id}'),
                  label: Text(en ? p.labelEn : p.labelPl),
                  selected: _j.groove == GrooveType.v &&
                      _j.angleDeg == p.angle &&
                      _j.rootFaceMm == p.rootFace &&
                      _j.gapMm == p.gap,
                  onSelected: (_) => _applyBevel(p),
                ),
              ChoiceChip(
                key: const ValueKey('groove-I'),
                label: Text(context.tr(pl: 'Bez fazy (I)', en: 'Square (I)')),
                selected: _j.groove == GrooveType.square,
                onSelected: (_) =>
                    _update(_j.copyWith(groove: GrooveType.square)),
              ),
            ],
          ),
        if (kind == JointKind.plateButt)
          Wrap(
            spacing: 6,
            children: [
              for (final g in GrooveType.values)
                ChoiceChip(
                  key: ValueKey('groove-${g.code}'),
                  label: Text(switch (g) {
                    GrooveType.v =>
                      context.tr(pl: 'V — jednostronnie', en: 'V — one side'),
                    GrooveType.x =>
                      context.tr(pl: 'X — dwustronnie', en: 'X — both sides'),
                    GrooveType.square =>
                      context.tr(pl: 'I — bez fazy', en: 'I — square'),
                  }),
                  selected: _j.groove == g,
                  onSelected: (_) => _update(_j.copyWith(groove: g)),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_j.groove != GrooveType.square || branch) ...[
              Expanded(
                child: _numField(
                    _angle,
                    branch
                        ? context.tr(pl: 'Kąt fazy β', en: 'Bevel β')
                        : context.tr(pl: 'Kąt rowka α', en: 'Groove α'),
                    unit: '°',
                    onChanged: (v) => _update(_j.copyWith(angleDeg: v ?? 0))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numField(
                    _rootFace, context.tr(pl: 'Próg c', en: 'Root face c'),
                    unit: 'mm',
                    onChanged: (v) => _update(_j.copyWith(rootFaceMm: v ?? 0))),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _numField(_gap, context.tr(pl: 'Szczelina b', en: 'Gap b'),
                  unit: 'mm',
                  onChanged: (v) => _update(_j.copyWith(gapMm: v ?? 0))),
            ),
          ],
        ),
        if (!branch && _j.groove != GrooveType.square) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'α to kąt CAŁEGO rowka: faza 30° na obu elementach = 60°.',
                en: 'α is the INCLUDED angle: 30° bevel on both parts = 60°.'),
            style: const TextStyle(fontSize: 11.5, color: kTextMut),
          ),
        ],
      ],
    );
  }

  Widget _countAndPosition(bool en) => QuoteSection(
        title: context.tr(pl: 'Ilość i pozycja', en: 'Quantity and position'),
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                key: const ValueKey('count-minus'),
                iconSize: 26,
                constraints: const BoxConstraints(
                    minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                onPressed: _j.count > 1 ? () => _bumpCount(-1) : null,
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('count'),
                  controller: _count,
                  textAlign: TextAlign.center,
                  keyboardType: numberKeyboard(decimal: false),
                  inputFormatters: numberInputFormatters(decimal: false),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                  onChanged: (t) =>
                      _update(_j.copyWith(count: int.tryParse(t.trim()) ?? 0)),
                  decoration: InputDecoration(
                    labelText: _j.kind.hasLength
                        ? context.tr(pl: 'Liczba spoin', en: 'Number of welds')
                        : context.tr(
                            pl: 'Liczba spoin (szt.)', en: 'Number of welds'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                key: const ValueKey('count-plus'),
                iconSize: 26,
                constraints: const BoxConstraints(
                    minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                onPressed: () => _bumpCount(1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in WeldPosition.values)
                ChoiceChip(
                  key: ValueKey('pos-${p.code}'),
                  label: Text(en ? p.labelEn : p.labelPl),
                  selected: _j.position == p,
                  onSelected: (_) => _update(_j.copyWith(position: p)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Pozycja wydłuża czas spawania: ×${numText(_j.position.factor)}.',
                en: 'Position stretches the welding time: ×${numText(_j.position.factor)}.'),
            style: const TextStyle(fontSize: 11.5, color: kTextMut),
          ),
        ],
      );

  Widget _processAndPrep(bool en) {
    final auto = autoPrepMinutes(_j);
    return QuoteSection(
      title: context.tr(pl: 'Proces i przygotowanie', en: 'Process and prep'),
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('scheme'),
          initialValue: _j.scheme?.code ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.tr(pl: 'Metoda spawania', en: 'Welding method'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(context.tr(
                  pl: 'Jak w wycenie (${widget.quote.scheme.label})',
                  en: 'As in the quote (${widget.quote.scheme.label})')),
            ),
            for (final s in kCommonSchemes)
              DropdownMenuItem(
                value: s.code,
                child: Text(s.isCombo
                    ? context.tr(
                        pl: '${s.label} — grań ${s.root!.code}',
                        en: '${s.label} — ${s.root!.code} root')
                    : s.label),
              ),
          ],
          onChanged: (v) => _update(_j.copyWith(
              scheme: () =>
                  v == null || v.isEmpty ? null : WeldScheme.fromCode(v))),
        ),
        const SizedBox(height: 12),
        _numField(
          _prep,
          context.tr(
              pl: 'Przygotowanie 1 spoiny', en: 'Prep per weld'),
          unit: 'min',
          helper: context.tr(
              pl: 'Fazowanie, ustawienie, sczepianie. Puste = automatycznie: '
                  '${numText(auto, decimals: 0)} min',
              en: 'Bevelling, fit-up, tacking. Empty = automatic: '
                  '${numText(auto, decimals: 0)} min'),
          onChanged: (v) => _update(_j.copyWith(prepMinutes: () => v)),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('label'),
          controller: _label,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: context.tr(
                pl: 'Opis (opcjonalnie), np. „kolektor, prefabrykacja"',
                en: 'Description (optional), e.g. "header, prefab"'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _preview(bool en) {
    final problems = _j.problems;
    if (problems.isNotEmpty) {
      return QuoteNotice(
        text: problems.map((p) => jointProblemText(p, en: en)).join('\n'),
        color: kFail,
        icon: Icons.error_outline,
      );
    }
    final q = widget.quote;
    final r = computeJoint(q, _j);
    // Koszt pozycji z narzutem i zyskiem, bez NDT i pozycji dodatkowych.
    final alone = computeQuote(q.copyWith(
      joints: [_j],
      extras: const [],
      rates: q.rates.copyWith(ndt: const {}),
    ));
    final n = _j.count;
    return QuoteSection(
      title: context.tr(pl: 'Podgląd pozycji', en: 'Item preview'),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _kv(context.tr(pl: 'Stopiwo / spoina', en: 'Deposit / weld'),
                '${numText(r.depositedKgPerWeld, decimals: 3)} kg'),
            _kv(context.tr(pl: 'Spawanie / spoina', en: 'Welding / weld'),
                formatHours(r.weldHours / n)),
            _kv(context.tr(pl: 'Przygotowanie / spoina', en: 'Prep / weld'),
                formatHours(r.prepHours / n)),
            if (r.diameterInches > 0)
              _kv(context.tr(pl: 'Cale-średnice', en: 'Dia-inches'),
                  '${r.diApprox ? '≈ ' : ''}${numText(r.diameterInches, decimals: 1)}'),
          ],
        ),
        const SizedBox(height: 10),
        // Bez „n × cena”: cena za spoinę jest zaokrąglona do grosza, więc
        // iloczyn potrafi rozjechać się z sumą o grosz.
        MoneyRow(
          label: context.tr(
              pl: 'Pozycja netto ($n szt.)', en: 'Item net ($n pcs)'),
          hint: context.tr(
              pl: '≈ ${formatPln(alone.netPerWeldGrosze)} za spoinę · z narzutem '
                  'i zyskiem, bez NDT i dodatków',
              en: '≈ ${formatPln(alone.netPerWeldGrosze)} per weld · with '
                  'overhead and profit, without NDT and extras'),
          grosze: alone.netGrosze,
          strong: true,
          hot: true,
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11.5, color: kTextMut)),
          Text(v,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final editing = widget.joint != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing
            ? context.tr(pl: 'Edycja pozycji', en: 'Edit item')
            : context.tr(pl: 'Nowa pozycja', en: 'New item')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          QuoteSection(
            title: context.tr(pl: 'Rodzaj złącza', en: 'Joint type'),
            children: [_kindChips(en)],
          ),
          if (_j.kind.onPipe) _pipeSize(en) else _plateSize(en),
          _groove(en),
          _countAndPosition(en),
          _processAndPrep(en),
          _preview(en),
          const SizedBox(height: 4),
          FilledButton.icon(
            key: const ValueKey('save-joint'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
            ),
            onPressed: _j.isValid ? _save : null,
            icon: const Icon(Icons.check),
            label: Text(
              editing
                  ? context.tr(pl: 'Zapisz pozycję', en: 'Save item')
                  : context.tr(pl: 'Dodaj do wyceny', en: 'Add to quote'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
