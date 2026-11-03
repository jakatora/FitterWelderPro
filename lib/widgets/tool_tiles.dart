import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/tool_usage.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import 'industrial_artwork.dart';
import 'tool_registry.dart';

// Wspólne kafle narzędzi: wiersz listy (menu, wyniki wyszukiwania) i zwarty
// kafel (przypięte i ostatnio używane na ekranie głównym).
//
// Każdy cel dotyku ma co najmniej 56 dp wysokości (rękawica), a długie
// przytrzymanie przypina / odpina narzędzie na ekranie głównym.

/// Minimalna wysokość wiersza narzędzia. Rękawica spawalnicza trafia pewnie
/// dopiero w coś tej wielkości — a więcej zamieniłoby menu w długi przewijak.
const double kToolRowMinHeight = 56;

IndustrialArtworkKind _artworkForGroup(ToolGroup group) => switch (group) {
      ToolGroup.cutProjects => IndustrialArtworkKind.cutting,
      ToolGroup.elbowsFittings => IndustrialArtworkKind.fitter,
      ToolGroup.branches => IndustrialArtworkKind.branch,
      ToolGroup.routeSlope => IndustrialArtworkKind.route,
      ToolGroup.tables => IndustrialArtworkKind.table,
      ToolGroup.supportsFlanges => IndustrialArtworkKind.flange,
      ToolGroup.weldParams => IndustrialArtworkKind.welder,
      ToolGroup.weldCalculators => IndustrialArtworkKind.calculator,
      ToolGroup.inspection => IndustrialArtworkKind.inspection,
      ToolGroup.stainlessFinish => IndustrialArtworkKind.finishing,
      ToolGroup.costing => IndustrialArtworkKind.costing,
    };

IndustrialArtworkKind _artworkForTool(ToolSpec tool) => switch (tool.id) {
      'iso_notebook' => IndustrialArtworkKind.blueprint,
      'iso_scanner' => IndustrialArtworkKind.scanner,
      'component_library' => IndustrialArtworkKind.library,
      'spool_check' => IndustrialArtworkKind.measurement,
      'bevel' => IndustrialArtworkKind.bevel,
      'elbow_takeouts' => IndustrialArtworkKind.elbowMeasure,
      'elbow_cut' => IndustrialArtworkKind.elbowCut,
      'elbow_rotation' => IndustrialArtworkKind.elbowRotate,
      'insert' => IndustrialArtworkKind.insert,
      'reducer' => IndustrialArtworkKind.reducer,
      'mitre_bend' => IndustrialArtworkKind.mitre,
      'tube_bending' => IndustrialArtworkKind.bender,
      'cone_layout' => IndustrialArtworkKind.cone,
      'saddle_cut' => IndustrialArtworkKind.saddle,
      'saddle_template' => IndustrialArtworkKind.saddleTemplate,
      'rolling_offset' => IndustrialArtworkKind.rollingOffset,
      'pipe_slope' => IndustrialArtworkKind.pipeSlope,
      'slope_cut' => IndustrialArtworkKind.slopeCut,
      'thermal_expansion' => IndustrialArtworkKind.expansion,
      'dn_mm' => IndustrialArtworkKind.pipeDiameter,
      'wall_thickness' => IndustrialArtworkKind.pipeWall,
      'pipe_weight' => IndustrialArtworkKind.pipeWeight,
      'steel_weight' => IndustrialArtworkKind.steelProfiles,
      'sanitary_tube' => IndustrialArtworkKind.sanitaryPipe,
      'unit_converter' => IndustrialArtworkKind.unitConversion,
      'glossary' => IndustrialArtworkKind.dictionary,
      'pipe_supports' => IndustrialArtworkKind.pipeSupport,
      'bolt_torque' => IndustrialArtworkKind.torque,
      'flange_check' => IndustrialArtworkKind.flangeCheck,
      'bolt_kit' => IndustrialArtworkKind.boltKit,
      'heat_input' => IndustrialArtworkKind.weldHeat,
      'welder_calculators' => IndustrialArtworkKind.gasTimer,
      'pwht_planner' => IndustrialArtworkKind.heatTreatment,
      'fillet_strength' => IndustrialArtworkKind.weldStrength,
      'power_source' => IndustrialArtworkKind.powerSource,
      'pass_plan' => IndustrialArtworkKind.weldPasses,
      'distortion' => IndustrialArtworkKind.weldDistortion,
      'cooling_time' => IndustrialArtworkKind.coolingTime,
      'welder_tanks' => IndustrialArtworkKind.tank,
      'orbital_tig' => IndustrialArtworkKind.orbital,
      'shade' => IndustrialArtworkKind.helmet,
      'tungsten' => IndustrialArtworkKind.electrode,
      'filler_selector' => IndustrialArtworkKind.filler,
      'assistant' => IndustrialArtworkKind.assistant,
      _ => _artworkForGroup(tool.group),
    };

/// Przypina albo odpina narzędzie i mówi o tym wprost — długie przytrzymanie
/// bez potwierdzenia to akcja, której nikt nie zauważy.
Future<void> toggleToolPin(BuildContext context, ToolSpec tool) async {
  final title = tool.title(context);
  final pinnedMsg = context.tr(
    pl: 'Przypięto „$title" na ekranie głównym',
    en: 'Pinned "$title" to the home screen',
  );
  final unpinnedMsg = context.tr(
    pl: 'Odpięto „$title"',
    en: 'Unpinned "$title"',
  );
  final messenger = ScaffoldMessenger.maybeOf(context);
  Haptic.tap();
  final pinned = await ToolUsageStore.instance.toggleFavorite(tool.id);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(pinned ? pinnedMsg : unpinnedMsg),
      duration: const Duration(seconds: 2),
    ));
}

String _pinHint(BuildContext context, bool pinned) => pinned
    ? context.tr(pl: 'odepnij z ekranu głównego', en: 'unpin from home')
    : context.tr(pl: 'przypnij na ekranie głównym', en: 'pin to home');

/// Wiersz narzędzia w menu i w wynikach wyszukiwania.
class ToolRow extends StatelessWidget {
  final ToolSpec tool;

  /// Pokazuje nad tytułem, z której sekcji jest narzędzie (wyniki
  /// wyszukiwania mieszają monter i spawacz).
  final bool showSection;

  final Map<String, Object?> fields;
  const ToolRow(
      {super.key,
      required this.tool,
      this.showSection = false,
      this.fields = const {}});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ToolUsageStore.instance,
      builder: (context, _) {
        final pinned = ToolUsageStore.instance.isFavorite(tool.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: kCard,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kBorder),
            ),
            child: Semantics(
              onLongPressHint: _pinHint(context, pinned),
              child: InkWell(
                key: ValueKey('tool-row-${tool.id}'),
                onTap: () => openTool(context, tool, fields: fields),
                onLongPress: () => toggleToolPin(context, tool),
                splashColor: tool.color.withValues(alpha: 0.10),
                highlightColor: tool.color.withValues(alpha: 0.05),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: kToolRowMinHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        IndustrialArtwork(
                          key: ValueKey('tool-artwork-${tool.id}'),
                          kind: _artworkForTool(tool),
                          glyph: tool.icon,
                          size: 54,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showSection)
                                Text(
                                  tool.section.label(context).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                    color: kTextMut,
                                  ),
                                ),
                              Text(
                                tool.title(context),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: kText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Jedna linia: menu ma być zwarte, a tytuł
                              // sam mówi, co to za narzędzie.
                              Text(
                                tool.subtitle(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: kTextSec,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (pinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.push_pin,
                              size: 18,
                              color: kGold,
                              semanticLabel:
                                  context.tr(pl: 'Przypięte', en: 'Pinned'),
                            ),
                          ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            size: 20, color: kTextMut),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Zwarty kafel na ekranie głównym (przypięte, ostatnio używane).
class ToolCompactTile extends StatelessWidget {
  final ToolSpec tool;

  /// Prefiks klucza — to samo narzędzie może być naraz przypięte i ostatnio
  /// używane, a testy muszą umieć wskazać konkretny kafel.
  final String keyPrefix;

  const ToolCompactTile({
    super.key,
    required this.tool,
    this.keyPrefix = 'tool-tile',
  });

  @override
  Widget build(BuildContext context) {
    final pinned = ToolUsageStore.instance.isFavorite(tool.id);
    return Material(
      color: kCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kBorder),
      ),
      child: Semantics(
        onLongPressHint: _pinHint(context, pinned),
        child: InkWell(
          key: ValueKey('$keyPrefix-${tool.id}'),
          onTap: () => openTool(context, tool),
          onLongPress: () => toggleToolPin(context, tool),
          splashColor: tool.color.withValues(alpha: 0.10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kToolRowMinHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  IndustrialArtwork(
                    key: ValueKey('$keyPrefix-artwork-${tool.id}'),
                    kind: _artworkForTool(tool),
                    glyph: tool.icon,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tool.title(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: kText,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dwie kolumny o wysokości dopasowanej do treści — bez sztywnych proporcji,
/// więc powiększona czcionka systemowa nie ucina tekstu.
class TwoColumnTiles extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const TwoColumnTiles({super.key, required this.children, this.gap = 10});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: i + 2 < children.length ? gap : 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              SizedBox(width: gap),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Etykieta sekcji / grupy: drobne wersaliki, jak w reszcie aplikacji.
class ToolSectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const ToolSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 16, 4, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: kTextMut,
            letterSpacing: 1.3,
          ),
        ),
      ),
    );
  }
}

/// Menu sekcji: najpierw wybór grupy, następnie jej narzędzia.
class ToolGroupedMenu extends StatefulWidget {
  final ToolSection section;

  /// Treść nad listą (np. ostrzeżenie o WPQR, podpowiedź).
  final List<Widget> header;

  const ToolGroupedMenu({
    super.key,
    required this.section,
    this.header = const [],
  });

  @override
  State<ToolGroupedMenu> createState() => _ToolGroupedMenuState();
}

class _ToolGroupedMenuState extends State<ToolGroupedMenu> {


  @override
  void initState() {
    super.initState();
    // Gwiazdki przypięcia muszą znać stan z dysku.
    ToolUsageStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = groupsOf(widget.section);
        final children = <Widget>[
          ...widget.header,
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: kCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: kBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('tool-group-${group.name}'),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _ToolGroupScreen(group: group),
                  )),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: kToolRowMinHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(children: [
                        IndustrialArtwork(
                          key: ValueKey('tool-group-artwork-${group.name}'),
                          kind: _artworkForGroup(group),
                          size: 64,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(group.title(context),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: kText))),
                        const Icon(Icons.chevron_right, color: kTextMut),
                      ]),
                    ),
                  ),
                ),
              ),
            ),

        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
          children: children,
        );
      },
    );
  }
}

class _ToolGroupScreen extends StatelessWidget {
  final ToolGroup group;
  const _ToolGroupScreen({required this.group});

  @override
  Widget build(BuildContext context) {
    final tools = toolsInGroup(group);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(group.title(context))),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        return ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Row(
                children: [
                  const Icon(Icons.push_pin_outlined,
                      size: 14, color: kTextMut),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr(
                        pl: 'Przytrzymaj narzędzie, żeby przypiąć je na '
                            'ekranie głównym.',
                        en: 'Long-press a tool to pin it to the home screen.',
                      ),
                      style: const TextStyle(fontSize: 12, color: kTextMut),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (wide)
              _WideGroup(tools: tools)
            else
              for (final tool in tools) ToolRow(tool: tool),
          ],
        );
      }),
    );
  }
}

class _WideGroup extends StatelessWidget {
  final List<ToolSpec> tools;
  const _WideGroup({required this.tools});

  @override
  Widget build(BuildContext context) {
    // ToolRow ma własny odstęp od dołu — tu tylko odstęp między kolumnami.
    return TwoColumnTiles(
      gap: 0,
      children: [
        for (var i = 0; i < tools.length; i++)
          Padding(
            padding:
                EdgeInsets.only(left: i.isOdd ? 6 : 0, right: i.isEven ? 6 : 0),
            child: ToolRow(tool: tools[i]),
          ),
      ],
    );
  }
}
