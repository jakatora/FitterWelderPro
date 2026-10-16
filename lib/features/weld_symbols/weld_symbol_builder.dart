// Czytnik / kreator symbolu spoiny.
//
// Spawacz wskazuje to, co WIDZI na rysunku (rodzaj symbolu, na której linii
// stoi, wymiary, chorągiewka, kółko…), a aplikacja rysuje symbol z przekrojem
// złącza i mówi zdaniem, co trzeba zrobić. Logika opisu jest w
// domain/weld_symbols — tu tylko stan pól i układ ekranu.

import 'package:flutter/material.dart';

import '../../domain/weld_symbols/weld_symbol.dart';
import '../../domain/weld_symbols/weld_symbol_description.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/number_field.dart';
import 'weld_symbol_painter.dart';
import 'weld_symbols_widgets.dart';

class WeldSymbolBuilderView extends StatefulWidget {
  const WeldSymbolBuilderView({super.key});

  @override
  State<WeldSymbolBuilderView> createState() => _WeldSymbolBuilderViewState();
}

class _WeldSymbolBuilderViewState extends State<WeldSymbolBuilderView> {
  static const _initial = WeldSymbolSpec(size: 5);

  WeldSymbolSpec _spec = _initial;

  final _size = TextEditingController(text: '5');
  final _length = TextEditingController();
  final _count = TextEditingController();
  final _element = TextEditingController();
  final _gap = TextEditingController();
  final _process = TextEditingController();
  final _reference = TextEditingController();

  List<TextEditingController> get _all =>
      [_size, _length, _count, _element, _gap, _process, _reference];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(WeldSymbolSpec next) => setState(() => _spec = next);

  void _reset() {
    for (final c in _all) {
      c.clear();
    }
    _size.text = '5';
    _set(_initial);
  }

  double? _positive(String raw) {
    final v = parseDecimal(raw);
    return v != null && v > 0 ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final reading = describeWeldSymbol(_spec, en: en);
    return LayoutBuilder(builder: (context, box) {
      final preview = _Preview(spec: _spec, reading: reading, en: en);
      final controls = _controls(context, en);
      final bottomPad = 24 + MediaQuery.viewPaddingOf(context).bottom;
      // Wysoki ekran: podgląd przypięty u góry, pola przewijają się pod nim —
      // każdą zmianę widać od razu. Niski (poziomo): wszystko w jednej liście.
      if (box.maxHeight >= 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: preview,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const ValueKey('ws-builder-list'),
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                children: [
                  ..._warnings(reading),
                  ...controls,
                  ..._notes(context, reading),
                ],
              ),
            ),
          ],
        );
      }
      return ListView(
        key: const ValueKey('ws-builder-list'),
        padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad),
        children: [
          preview,
          const SizedBox(height: 8),
          ..._warnings(reading),
          ...controls,
          ..._notes(context, reading),
        ],
      );
    });
  }

  /// Ostrzeżenia o niepełnym / sprzecznym zapisie — na samej górze listy.
  List<Widget> _warnings(WeldSymbolReading reading) => [
        for (final w in reading.warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: kWarn, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(w,
                      style: const TextStyle(
                          color: kWarn, fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          ),
      ];

  /// Objaśnienie każdego elementu odczytu — pod polami wyboru.
  List<Widget> _notes(BuildContext context, WeldSymbolReading reading) => [
        SectionLabel(context.tr(
            pl: 'Co znaczy każdy element', en: 'What each element means')),
        for (final n in reading.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 6, color: kTextMut),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(n,
                      style: const TextStyle(
                          color: kTextSec, fontSize: 13, height: 1.45)),
                ),
              ],
            ),
          ),
      ];

  List<Widget> _controls(BuildContext context, bool en) {
    final s = _spec;
    final isFillet = s.kind == WeldKind.fillet;
    return [
      SectionLabel(context.tr(pl: 'System rysunku', en: 'Drawing system')),
      SegmentedButton<SymbolSystem>(
        key: const ValueKey('ws-system'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: SymbolSystem.a,
            label: Text(context.tr(pl: 'A: dwie linie', en: 'A: two lines')),
          ),
          ButtonSegment(
            value: SymbolSystem.b,
            label: Text(context.tr(pl: 'B: jedna linia', en: 'B: one line')),
          ),
        ],
        selected: {s.system},
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(0, kMinTapTarget)),
        ),
        onSelectionChanged: (v) => _set(s.copyWith(system: v.first)),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          context.tr(
            pl: 'A — linia ciągła i przerywana (EN ISO). B — tylko linia '
                'ciągła, jak na rysunkach AWS.',
            en: 'A — solid and dashed line (EN ISO). B — solid line only, as '
                'on AWS drawings.',
          ),
          style: const TextStyle(color: kTextMut, fontSize: 12, height: 1.4),
        ),
      ),
      SectionLabel(
          context.tr(pl: 'Symbol na rysunku', en: 'Symbol on the drawing')),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in WeldKind.builderKinds)
            ChoiceChip(
              key: ValueKey('ws-kind-${k.name}'),
              avatar: SizedBox(
                width: 22,
                height: 22,
                child: CustomPaint(painter: GlyphOnLinePainter(k)),
              ),
              label: Text(weldKindChip(k, en: en)),
              selected: s.kind == k,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => _set(s.copyWith(kind: k)),
            ),
        ],
      ),
      SectionLabel(
          context.tr(pl: 'Gdzie stoi symbol', en: 'Where the symbol sits')),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final side in WeldSide.values)
            ChoiceChip(
              key: ValueKey('ws-side-${side.name}'),
              label: Text(sideAsDrawn(s.system, side, en: en)),
              selected: s.side == side,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => _set(s.copyWith(side: side)),
            ),
        ],
      ),
      SectionLabel(context.tr(
          pl: 'Wymiar przed symbolem', en: 'Dimension before the symbol')),
      if (isFillet) ...[
        SegmentedButton<FilletSize>(
          key: const ValueKey('ws-fillet-size'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: FilletSize.throat,
              label: Text(context.tr(
                  pl: 'a — grubość obliczeniowa', en: 'a — throat thickness')),
            ),
            ButtonSegment(
              value: FilletSize.leg,
              label: Text(
                  context.tr(pl: 'z — długość boku', en: 'z — leg length')),
            ),
          ],
          selected: {s.filletSize},
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, kMinTapTarget)),
          ),
          onSelectionChanged: (v) => _set(s.copyWith(filletSize: v.first)),
        ),
        const SizedBox(height: 10),
      ],
      TextField(
        key: const ValueKey('ws-size'),
        controller: _size,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        decoration: InputDecoration(
          labelText: isFillet
              ? (s.filletSize == FilletSize.throat
                  ? context.tr(pl: 'a (mm)', en: 'a (mm)')
                  : context.tr(pl: 'z (mm)', en: 'z (mm)'))
              : context.tr(
                  pl: 'Głębokość wtopienia s (mm)',
                  en: 'Penetration depth s (mm)'),
          helperText: isFillet
              ? null
              : context.tr(
                  pl: 'Puste, gdy przed symbolem nie ma liczby — pełny przetop.',
                  en: 'Empty when there is no number before the symbol — '
                      'full penetration.'),
          helperMaxLines: 2,
        ),
        onChanged: (v) => _set(s.copyWith(size: () => _positive(v))),
      ),
      SectionLabel(context.tr(pl: 'Za symbolem', en: 'After the symbol')),
      SwitchListTile(
        key: const ValueKey('ws-intermittent'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr(
            pl: 'Spoina przerywana n × l (e)',
            en: 'Intermittent weld n × l (e)')),
        value: s.intermittent,
        onChanged: (v) => _set(s.copyWith(intermittent: v)),
      ),
      if (!s.intermittent)
        TextField(
          key: const ValueKey('ws-length'),
          controller: _length,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: context.tr(pl: 'Długość (mm)', en: 'Length (mm)'),
            helperText: context.tr(
                pl: 'Puste = spoina na całej długości złącza.',
                en: 'Empty = weld along the whole joint.'),
          ),
          onChanged: (v) => _set(s.copyWith(length: () => _positive(v))),
        )
      else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('ws-count'),
                controller: _count,
                keyboardType: numberKeyboard(decimal: false),
                inputFormatters: numberInputFormatters(decimal: false),
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'n (szt.)', en: 'n (pcs)'),
                  helperText: context.tr(pl: 'Jeśli jest', en: 'If given'),
                ),
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  _set(s.copyWith(count: () => n != null && n > 0 ? n : null));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('ws-element'),
                controller: _element,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: const InputDecoration(labelText: 'l (mm)'),
                onChanged: (v) =>
                    _set(s.copyWith(elementLength: () => _positive(v))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('ws-gap'),
                controller: _gap,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: const InputDecoration(labelText: 'e (mm)'),
                onChanged: (v) => _set(s.copyWith(gap: () => _positive(v))),
              ),
            ),
          ],
        ),
        if (s.staggerApplies)
          SwitchListTile(
            key: const ValueKey('ws-staggered'),
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr(
                pl: 'Przestawna — znak Z między n × l a (e)',
                en: 'Staggered — Z between n × l and (e)')),
            value: s.staggered,
            onChanged: (v) => _set(s.copyWith(staggered: v)),
          ),
      ],
      SectionLabel(context.tr(pl: 'Kształt lica', en: 'Face contour')),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in WeldContour.values)
            ChoiceChip(
              key: ValueKey('ws-contour-${c.name}'),
              label: Text(switch (c) {
                WeldContour.none =>
                  context.tr(pl: 'Bez symbolu', en: 'No symbol'),
                WeldContour.flat => context.tr(pl: 'Płaskie', en: 'Flat'),
                WeldContour.convex => context.tr(pl: 'Wypukłe', en: 'Convex'),
                WeldContour.concave => context.tr(pl: 'Wklęsłe', en: 'Concave'),
              }),
              selected: s.contour == c,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => _set(s.copyWith(contour: c)),
            ),
        ],
      ),
      if (s.backingApplies) ...[
        SectionLabel(context.tr(pl: 'Podkładka', en: 'Backing strip')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in BackingStrip.values)
              ChoiceChip(
                key: ValueKey('ws-backing-${b.name}'),
                label: Text(switch (b) {
                  BackingStrip.none => context.tr(pl: 'Brak', en: 'None'),
                  BackingStrip.permanent =>
                    context.tr(pl: 'M — stała', en: 'M — permanent'),
                  BackingStrip.removable =>
                    context.tr(pl: 'MR — usuwana', en: 'MR — removable'),
                }),
                selected: s.backing == b,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _set(s.copyWith(backing: b)),
              ),
          ],
        ),
      ],
      SectionLabel(
          context.tr(pl: 'Na załamaniu strzałki', en: 'At the arrow junction')),
      SwitchListTile(
        key: const ValueKey('ws-all-around'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr(
            pl: 'Kółko — spoina dookoła', en: 'Circle — weld all around')),
        value: s.allAround,
        onChanged: (v) => _set(s.copyWith(allAround: v)),
      ),
      SwitchListTile(
        key: const ValueKey('ws-field'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr(
            pl: 'Chorągiewka — spoina montażowa',
            en: 'Flag — field (site) weld')),
        value: s.fieldWeld,
        onChanged: (v) => _set(s.copyWith(fieldWeld: v)),
      ),
      SectionLabel(context.tr(pl: 'Rozwidlenie (ogon)', en: 'Tail')),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ws-process'),
              controller: _process,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Proces', en: 'Process'),
                hintText: '111',
              ),
              onChanged: (v) => _set(s.copyWith(process: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('ws-reference'),
              controller: _reference,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Odwołanie', en: 'Reference'),
                hintText: 'WPS-01',
              ),
              onChanged: (v) => _set(s.copyWith(reference: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('ws-reset'),
          style:
              TextButton.styleFrom(minimumSize: const Size(0, kMinTapTarget)),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(context.tr(pl: 'Od nowa', en: 'Start over')),
        ),
      ),
    ];
  }
}

/// Rysunek + zdanie (wynik główny ekranu).
class _Preview extends StatelessWidget {
  const _Preview({required this.spec, required this.reading, required this.en});

  final WeldSymbolSpec spec;
  final WeldSymbolReading reading;
  final bool en;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: CustomPaint(
              key: const ValueKey('ws-drawing'),
              painter: WeldSymbolPainter(spec: spec, en: en),
            ),
          ),
          const SizedBox(height: 6),
          CopyOnLongPress(
            value: reading.sentence,
            label: context.tr(pl: 'Odczyt', en: 'Reading'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                reading.sentence,
                key: const ValueKey('ws-sentence'),
                style: const TextStyle(
                  color: kArc,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kArc, kArc.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
