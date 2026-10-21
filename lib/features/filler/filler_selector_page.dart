// Dobór spoiwa: spawacz wybiera materiał A, materiał B i proces — ekran
// pokazuje typowe spoiwo (EN ISO + AWS), gaz osłonowy (EN ISO 14175),
// formowanie grani i ostrzeżenia. Druga zakładka liczy równoważniki
// Schaefflera stopiwa z rozcieńczeniem (bez granic obszarów wykresu — patrz
// domain/filler/schaeffler.dart).
//
// Dane i reguły: lib/domain/filler/ (czysty Dart, testy w test/domain/filler).
// Odesłania do innych narzędzi są celowo tylko tekstem — bez nawigacji.

import 'package:flutter/material.dart';

import '../../domain/filler/filler_catalog.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/filler/filler_selector.dart';
import '../../domain/filler/schaeffler.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';

const _tabular = [FontFeature.tabularFigures(), FontFeature.slashedZero()];

class FillerSelectorPage extends StatelessWidget {
  const FillerSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(context.tr(pl: 'Dobór spoiwa', en: 'Filler metal selector')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr(pl: 'Dobór', en: 'Selection')),
              Tab(text: context.tr(pl: 'Rozcieńczenie', en: 'Dilution')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_SelectorTab(), _DilutionTab()],
        ),
      ),
    );
  }
}

// ═══ Zakładka „Dobór” ═══════════════════════════════════════════════════════

class _SelectorTab extends StatefulWidget {
  const _SelectorTab();

  @override
  State<_SelectorTab> createState() => _SelectorTabState();
}

class _SelectorTabState extends State<_SelectorTab>
    with AutomaticKeepAliveClientMixin, ToolHandleHost<_SelectorTab> {
  final _scroll = ScrollController();
  @override
  String get toolId => 'filler_selector';
  @override
  Set<String> get supportedFields =>
      const {'material_a', 'material_b', 'process'};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) markReady();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final a = BaseMaterial.values
        .where((v) => v.name == fields['material_a'])
        .firstOrNull;
    final b = BaseMaterial.values
        .where((v) => v.name == fields['material_b'])
        .firstOrNull;
    final p = FillerProcess.values
        .where((v) => v.name == fields['process'])
        .firstOrNull;
    if (fields.length != 3 || a == null || b == null || p == null) {
      return fields.keys.toSet();
    }
    setState(() {
      _a = a;
      _b = b;
      _process = p;
    });
    DefaultTabController.of(context).animateTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
    return {};
  }

  BaseMaterial _a = BaseMaterial.carbonSteel;
  BaseMaterial _b = BaseMaterial.carbonSteel;
  FillerProcess _process = FillerProcess.tig;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick({required bool sideA}) async {
    final current = sideA ? _a : _b;
    final picked = await showModalBottomSheet<BaseMaterial>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: kCard,
      builder: (_) => _MaterialSheet(
        current: current,
        title: sideA
            ? context.tr(pl: 'Materiał A', en: 'Material A')
            : context.tr(pl: 'Materiał B', en: 'Material B'),
      ),
    );
    if (picked == null || !mounted) return;
    Haptic.tap();
    setState(() {
      if (sideA) {
        _a = picked;
      } else {
        _b = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final english = context.language == AppLanguage.en;
    final rec = selectFiller(_a, _b);
    final filler = rec.forProcess(_process);

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(
          context.tr(
            pl: 'Wybierz materiały po obu stronach złącza i proces — '
                'zobaczysz typowe spoiwo, gaz i na co uważać.',
            en: 'Pick the materials on both sides of the joint and the '
                'process — you get the typical filler, gas and what to '
                'watch for.',
          ),
          style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 12),
        _MaterialField(
          key: const ValueKey('filler-material-a'),
          label: context.tr(pl: 'Materiał A', en: 'Material A'),
          material: _a,
          english: english,
          onTap: () => _pick(sideA: true),
        ),
        const SizedBox(height: 8),
        _MaterialField(
          key: const ValueKey('filler-material-b'),
          label: context.tr(pl: 'Materiał B', en: 'Material B'),
          material: _b,
          english: english,
          onTap: () => _pick(sideA: false),
        ),
        const SizedBox(height: 14),
        Text(context.tr(pl: 'Proces', en: 'Process'),
            style: const TextStyle(
                color: kTextSec, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in FillerProcess.values)
              ChoiceChip(
                key: ValueKey('filler-process-${p.name}'),
                label: Text(p.label),
                selected: _process == p,
                selectedColor: kArc.withValues(alpha: 0.25),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  Haptic.tap();
                  setState(() => _process = p);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        ..._result(context, rec, filler, english),
        const SizedBox(height: 16),
        const _Disclaimer(),
      ],
    );
  }

  List<Widget> _result(BuildContext context, FillerRecommendation rec,
      ProcessFiller? filler, bool english) {
    switch (rec.verdict) {
      case FillerVerdict.notArcWeldable:
        return [
          _StatusCard(
            key: const ValueKey('filler-not-weldable'),
            color: kFail,
            icon: Icons.block,
            title:
                context.tr(pl: 'Nie spawa się łukowo', en: 'Not arc weldable'),
            body: rec.summary.of(english: english),
          ),
        ];
      case FillerVerdict.specialist:
        return [
          _StatusCard(
            key: const ValueKey('filler-specialist'),
            color: kWarn,
            icon: Icons.engineering_outlined,
            title: context.tr(
                pl: 'Połączenie specjalne — tylko wg WPS',
                en: 'Special joint — per the WPS only'),
            body: rec.summary.of(english: english),
          ),
          const SizedBox(height: 12),
          _BackingCard(rec: rec, english: english),
          ..._notes(context, rec, english),
        ];
      case FillerVerdict.typical:
        return [
          if (filler != null)
            _FillerCard(
              family: rec.family!,
              filler: filler,
              summary: rec.summary,
              english: english,
            )
          else
            _StatusCard(
              key: const ValueKey('filler-process-missing'),
              color: kWarn,
              icon: Icons.help_outline,
              title: context.tr(
                  pl: 'Brak typowego doboru dla ${_process.label}',
                  en: 'No typical selection for ${_process.label}'),
              body: context.tr(
                pl: 'Dla tego połączenia aplikacja podaje spoiwo dla: '
                    '${rec.availableProcesses.map((p) => p.label).join(', ')}. '
                    'Spoiwo do ${_process.label} — wg WPS.',
                en: 'For this joint the app gives a filler for: '
                    '${rec.availableProcesses.map((p) => p.label).join(', ')}. '
                    'Filler for ${_process.label} — per the WPS.',
              ),
            ),
          const SizedBox(height: 12),
          _GasCard(process: _process, filler: filler, english: english),
          const SizedBox(height: 12),
          _BackingCard(rec: rec, english: english),
          ..._notes(context, rec, english),
        ];
    }
  }

  List<Widget> _notes(
      BuildContext context, FillerRecommendation rec, bool english) {
    return [
      if (rec.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Section(
          key: const ValueKey('filler-warnings'),
          title:
              context.tr(pl: 'Uwagi i ostrzeżenia', en: 'Notes and warnings'),
          children: [
            for (final w in rec.warnings)
              _Bullet(
                icon: Icons.warning_amber_rounded,
                color: kWarn,
                text: w.of(english: english),
              ),
          ],
        ),
      ],
      if (rec.seeAlso.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Section(
          title: context.tr(
              pl: 'Zobacz też w aplikacji', en: 'See also in the app'),
          children: [
            for (final s in rec.seeAlso)
              _Bullet(
                icon: Icons.arrow_right_alt,
                color: kTextSec,
                text: s.of(english: english),
              ),
          ],
        ),
      ],
    ];
  }
}

class _MaterialField extends StatelessWidget {
  final String label;
  final BaseMaterial material;
  final bool english;
  final VoidCallback onTap;

  const _MaterialField({
    super.key,
    required this.label,
    required this.material,
    required this.english,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: kTextMut,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(material.label.of(english: english),
                          style: const TextStyle(
                              color: kText,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text(material.grades,
                          style:
                              const TextStyle(color: kTextSec, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, color: kTextSec),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MaterialSheet extends StatelessWidget {
  final BaseMaterial current;
  final String title;

  const _MaterialSheet({required this.current, required this.title});

  @override
  Widget build(BuildContext context) {
    final english = context.language == AppLanguage.en;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: kText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                  bottom: 16 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                for (final g in MaterialGroup.values) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(g.title.of(english: english),
                        style: const TextStyle(
                            color: kTextMut,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  for (final m
                      in BaseMaterial.values.where((m) => m.group == g))
                    ListTile(
                      key: ValueKey('filler-pick-${m.name}'),
                      minTileHeight: 56,
                      selected: m == current,
                      selectedColor: kArc,
                      title: Text(m.label.of(english: english),
                          style: TextStyle(
                              color: m == current ? kArc : kText,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(m.grades,
                          style:
                              const TextStyle(color: kTextSec, fontSize: 12)),
                      trailing: m == current
                          ? const Icon(Icons.check, color: kArc)
                          : null,
                      onTap: () => Navigator.pop(context, m),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wynik główny: spoiwo dla wybranego procesu.
class _FillerCard extends StatelessWidget {
  final FillerFamily family;
  final ProcessFiller filler;
  final FillerText summary;
  final bool english;

  const _FillerCard({
    required this.family,
    required this.filler,
    required this.summary,
    required this.english,
  });

  @override
  Widget build(BuildContext context) {
    final items = filler.consumables;
    return Container(
      key: const ValueKey('filler-result'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                pl: 'Spoiwo · ${family.name.pl}',
                en: 'Filler · ${family.name.en}'),
            style: const TextStyle(
                color: kTextSec, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(summary.of(english: english),
              style: const TextStyle(
                  color: kTextSec, fontSize: 12.5, height: 1.4)),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 24),
            const SizedBox(height: 10),
            _ConsumableBlock(item: items[i], hot: i == 0, english: english),
          ],
          if (filler.note != null) ...[
            const SizedBox(height: 10),
            Text(filler.note!.of(english: english),
                style: const TextStyle(
                    color: kTextSec, fontSize: 12.5, height: 1.4)),
          ],
          const SizedBox(height: 10),
          Text(
            context.tr(
                pl: 'Typowy dobór — wiążące spoiwo podaje WPS. Przytrzymaj '
                    'oznaczenie, aby je skopiować.',
                en: 'Typical selection — the WPS gives the binding filler. '
                    'Long-press a designation to copy it.'),
            style: const TextStyle(
                color: kTextMut, fontSize: 11.5, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _ConsumableBlock extends StatelessWidget {
  final Consumable item;
  final bool hot;
  final bool english;

  const _ConsumableBlock({
    required this.item,
    required this.hot,
    required this.english,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.use != null) ...[
          Text(item.use!.of(english: english),
              style: const TextStyle(color: kText, fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
        ],
        CopyOnLongPress(
          value: item.awsDesignation,
          label: item.awsStandard,
          child: Text(
            item.awsDesignation,
            style: TextStyle(
              color: hot ? kArc : kText,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w700,
              fontFeatures: _tabular,
            ),
          ),
        ),
        Text(item.awsStandard,
            style: const TextStyle(color: kTextMut, fontSize: 12)),
        const SizedBox(height: 8),
        CopyOnLongPress(
          value: item.isoDesignation,
          label: item.isoStandard,
          child: Text(
            item.isoDesignation,
            style: const TextStyle(
              color: kText,
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w700,
              fontFeatures: _tabular,
            ),
          ),
        ),
        Text(item.isoStandard,
            style: const TextStyle(color: kTextMut, fontSize: 12)),
      ],
    );
  }
}

class _GasCard extends StatelessWidget {
  final FillerProcess process;
  final ProcessFiller? filler;
  final bool english;

  const _GasCard({
    required this.process,
    required this.filler,
    required this.english,
  });

  @override
  Widget build(BuildContext context) {
    final gases = filler?.shielding ?? const <GasSymbol>[];
    return _Section(
      key: const ValueKey('filler-gas'),
      title: context.tr(
          pl: 'Gaz osłonowy (EN ISO 14175)',
          en: 'Shielding gas (EN ISO 14175)'),
      children: [
        if (!process.usesShieldingGas)
          Text(
              context.tr(
                  pl: 'Nie dotyczy — elektroda otulona.',
                  en: 'Not applicable — covered electrode.'),
              style: const TextStyle(color: kTextSec, fontSize: 13))
        else if (gases.isEmpty)
          Text(context.tr(pl: 'Wg WPS.', en: 'Per the WPS.'),
              style: const TextStyle(color: kTextSec, fontSize: 13))
        else ...[
          for (final g in gases) _GasRow(gas: g, english: english),
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Gaz z karty producenta spoiwa ma pierwszeństwo.',
                en: 'The gas on the filler data sheet takes precedence.'),
            style: const TextStyle(color: kTextMut, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _GasRow extends StatelessWidget {
  final GasSymbol gas;
  final bool english;

  const _GasRow({required this.gas, required this.english});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: CopyOnLongPress(
              value: gas.code,
              child: Text(gas.code,
                  style: const TextStyle(
                      color: kText, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(gas.description.of(english: english),
                  style: const TextStyle(color: kTextSec, fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackingCard extends StatelessWidget {
  final FillerRecommendation rec;
  final bool english;

  const _BackingCard({required this.rec, required this.english});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (rec.backing) {
      BackingNeed.required => (
          context.tr(pl: 'Wymagane', en: 'Required'),
          kWarn,
          Icons.priority_high,
        ),
      BackingNeed.recommended => (
          context.tr(pl: 'Zalecane', en: 'Recommended'),
          kWarn,
          Icons.info_outline,
        ),
      BackingNeed.notNeeded => (
          context.tr(pl: 'Zwykle niepotrzebne', en: 'Usually not needed'),
          kPass,
          Icons.check_circle_outline,
        ),
    };
    return _Section(
      key: const ValueKey('filler-backing'),
      title: context.tr(
          pl: 'Formowanie grani (gaz od strony grani)',
          en: 'Root purge (backing gas)'),
      children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (rec.backingGases.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final g in rec.backingGases) _GasRow(gas: g, english: english),
        ],
        const SizedBox(height: 4),
        Text(
          context.tr(
              pl: 'Dotyczy grani spawanej z jednej strony (rury, zbiorniki).',
              en: 'Applies to roots welded from one side (pipes, vessels).'),
          style: const TextStyle(color: kTextMut, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;

  const _StatusCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(body,
                    style: const TextStyle(
                        color: kText, fontSize: 13.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Bullet({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: kText, fontSize: 13, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('filler-disclaimer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kTextMut.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.menu_book_outlined, color: kTextSec, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                pl: 'Wiążące spoiwo, gaz, podgrzewanie i obróbkę cieplną '
                    'podaje WPS / specyfikacja projektu. Aplikacja pokazuje '
                    'typowy dobór wg norm klasyfikacji spoiw i kart '
                    'producentów — przed spawaniem sprawdź WPS.',
                en: 'The binding filler, gas, preheat and heat treatment come '
                    'from the WPS / project specification. The app shows a '
                    'typical selection per filler classification standards '
                    'and maker data sheets — check the WPS before welding.',
              ),
              style: const TextStyle(
                  color: kText,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══ Zakładka „Rozcieńczenie” ═══════════════════════════════════════════════

enum _Column { a, b, filler }

enum _Element { c, si, mn, cr, mo, ni, nb }

extension on _Element {
  String get symbol => switch (this) {
        _Element.c => 'C',
        _Element.si => 'Si',
        _Element.mn => 'Mn',
        _Element.cr => 'Cr',
        _Element.mo => 'Mo',
        _Element.ni => 'Ni',
        _Element.nb => 'Nb',
      };
}

class _DilutionTab extends StatefulWidget {
  const _DilutionTab();

  @override
  State<_DilutionTab> createState() => _DilutionTabState();
}

class _DilutionTabState extends State<_DilutionTab>
    with AutomaticKeepAliveClientMixin {
  late final Map<(_Column, _Element), TextEditingController> _fields = {
    for (final c in _Column.values)
      for (final e in _Element.values) (c, e): TextEditingController(),
  };
  final _dilution = TextEditingController();
  final _shareA = TextEditingController(text: '50');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    for (final c in [..._fields.values, _dilution, _shareA]) {
      c.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [..._fields.values, _dilution, _shareA]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Wartość pola w %; `null` dla pustego albo nieliczbowego.
  double? _value(TextEditingController c) => parseDecimal(c.text);

  bool _outOfRange(TextEditingController c) {
    final v = _value(c);
    return v != null && (v < 0 || v > 100);
  }

  /// Skład kolumny — wymaga Cr i Ni, reszta pustych = 0. `null`, gdy
  /// brakuje Cr / Ni albo skład jest poza zakresem.
  WeldComposition? _composition(_Column col) {
    double? v(_Element e) => _value(_fields[(col, e)]!);
    final cr = v(_Element.cr);
    final ni = v(_Element.ni);
    if (cr == null || ni == null) return null;
    final x = WeldComposition(
      c: v(_Element.c) ?? 0,
      si: v(_Element.si) ?? 0,
      mn: v(_Element.mn) ?? 0,
      cr: cr,
      mo: v(_Element.mo) ?? 0,
      ni: ni,
      nb: v(_Element.nb) ?? 0,
    );
    return x.isValid ? x : null;
  }

  String _fmt(double v, {required bool english}) {
    final s = v.toStringAsFixed(1);
    return english ? s : s.replaceAll('.', ',');
  }

  String _columnLabel(BuildContext context, _Column c) => switch (c) {
        _Column.a => context.tr(pl: 'A', en: 'A'),
        _Column.b => context.tr(pl: 'B', en: 'B'),
        _Column.filler => context.tr(pl: 'Spoiwo', en: 'Filler'),
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final english = context.language == AppLanguage.en;
    final a = _composition(_Column.a);
    final b = _composition(_Column.b);
    final f = _composition(_Column.filler);
    final d = _value(_dilution);
    final s = _value(_shareA);
    final weld = (a != null &&
            b != null &&
            f != null &&
            d != null &&
            s != null &&
            !_outOfRange(_dilution) &&
            !_outOfRange(_shareA))
        ? weldMetalComposition(
            filler: f, baseA: a, baseB: b, dilution: d / 100, shareA: s / 100)
        : null;

    final rows = <(String, WeldComposition?, bool)>[
      (context.tr(pl: 'Materiał A', en: 'Material A'), a, false),
      (context.tr(pl: 'Materiał B', en: 'Material B'), b, false),
      (context.tr(pl: 'Spoiwo', en: 'Filler'), f, false),
      (context.tr(pl: 'Stopiwo', en: 'Weld metal'), weld, true),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(
          context.tr(
            pl: 'Równoważniki Schaefflera dla materiałów, spoiwa i stopiwa z '
                'rozcieńczeniem. Skład wpisz z atestu 3.1 i świadectwa '
                'spoiwa, w % masowych. Cr i Ni są wymagane, puste pozostałe '
                'pole = 0.',
            en: 'Schaeffler equivalents for the parent metals, filler and '
                'diluted weld metal. Enter the chemistry from the 3.1 '
                'certificate and the filler certificate, in mass %. Cr and Ni '
                'are required; any other empty field = 0.',
          ),
          style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(width: 40),
          for (final c in _Column.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_columnLabel(context, c),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: kTextSec,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        for (final e in _Element.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  height: 52,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(e.symbol,
                        style: const TextStyle(
                            color: kText,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                for (final c in _Column.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        key: ValueKey('dilution-${c.name}-${e.name}'),
                        controller: _fields[(c, e)],
                        keyboardType: numberKeyboard(),
                        inputFormatters: numberInputFormatters(),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText:
                              e == _Element.cr || e == _Element.ni ? '—' : '0',
                          errorText:
                              _outOfRange(_fields[(c, e)]!) ? '0–100' : null,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('dilution-percent'),
          controller: _dilution,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText:
                context.tr(pl: 'Rozcieńczenie D, %', en: 'Dilution D, %'),
            helperText: context.tr(
                pl: 'Udział materiału rodzimego w spoinie.',
                en: 'Share of parent metal in the weld.'),
            helperMaxLines: 2,
            errorText: _outOfRange(_dilution) ? '0–100' : null,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('dilution-share-a'),
          controller: _shareA,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: context.tr(pl: 'Udział A, %', en: 'Share of A, %'),
            helperText: context.tr(
                pl: 'Udział materiału A w stopionym materiale rodzimym '
                    '(reszta to B).',
                en: 'Share of material A in the melted parent metal (the '
                    'rest is B).'),
            helperMaxLines: 2,
            errorText: _outOfRange(_shareA) ? '0–100' : null,
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          key: const ValueKey('dilution-results'),
          title: context.tr(
              pl: 'Równoważniki (Schaeffler)', en: 'Equivalents (Schaeffler)'),
          children: [
            Row(children: [
              const Expanded(flex: 3, child: SizedBox()),
              Expanded(
                flex: 2,
                child: Text('Cr_eq',
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: kTextMut, fontSize: 12)),
              ),
              Expanded(
                flex: 2,
                child: Text('Ni_eq',
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: kTextMut, fontSize: 12)),
              ),
            ]),
            for (final (label, x, hot) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: Text(label,
                        style: TextStyle(
                            color: hot ? kText : kTextSec,
                            fontSize: 14,
                            fontWeight:
                                hot ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  for (final v in [x?.crEq, x?.niEq])
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: v == null
                            ? const Text('—',
                                style: TextStyle(color: kTextMut, fontSize: 16))
                            : CopyOnLongPress(
                                value: _fmt(v, english: english),
                                label: label,
                                child: Text(
                                  _fmt(v, english: english),
                                  style: TextStyle(
                                    color: hot ? kArc : kText,
                                    fontSize: hot ? 24 : 17,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: _tabular,
                                  ),
                                ),
                              ),
                      ),
                    ),
                ]),
              ),
            if (weld == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                      pl: 'Stopiwo: wpisz Cr i Ni dla A, B i spoiwa oraz '
                          'rozcieńczenie.',
                      en: 'Weld metal: enter Cr and Ni for A, B and the filler '
                          'plus the dilution.'),
                  style: const TextStyle(color: kTextMut, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: context.tr(pl: 'Jak to liczymy', en: 'How it is calculated'),
          children: [
            for (final t in [
              const FillerText(
                  'Cr_eq = Cr + Mo + 1,5·Si + 0,5·Nb;  '
                      'Ni_eq = Ni + 30·C + 0,5·Mn (Schaeffler).',
                  'Cr_eq = Cr + Mo + 1.5·Si + 0.5·Nb;  '
                      'Ni_eq = Ni + 30·C + 0.5·Mn (Schaeffler).'),
              const FillerText(
                  'Stopiwo = (1 − D)·spoiwo + D·(u·A + (1 − u)·B), gdzie D — '
                      'rozcieńczenie, u — udział A.',
                  'Weld metal = (1 − D)·filler + D·(u·A + (1 − u)·B), where '
                      'D is dilution and u the share of A.'),
              const FillerText(
                  'Aplikacja nie rysuje granic obszarów wykresu Schaefflera '
                      '(austenit, ferryt, martenzyt) — nie ma ich '
                      'zweryfikowanych współrzędnych. Punkt stopiwa nanosi '
                      'technolog na wykres z normy lub podręcznika.',
                  'The app does not draw the Schaeffler diagram boundaries '
                      '(austenite, ferrite, martensite) — it has no verified '
                      'coordinates for them. The engineer plots the weld-metal '
                      'point on the diagram from a standard or handbook.'),
              const FillerText(
                  'Schaeffler pomija azot — przy dupleksie i stalach z N '
                      'technolog stosuje zwykle wykres WRC-1992.',
                  'Schaeffler ignores nitrogen — for duplex and N-bearing '
                      'steels the engineer usually uses the WRC-1992 '
                      'diagram.'),
            ])
              _Bullet(
                icon: Icons.info_outline,
                color: kTextSec,
                text: t.of(english: english),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const _Disclaimer(),
      ],
    );
  }
}
