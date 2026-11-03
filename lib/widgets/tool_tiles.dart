import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/tool_usage.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import 'tool_registry.dart';

// Wspólne kafle narzędzi: wiersz listy (menu, wyniki wyszukiwania) i zwarty
// kafel (przypięte i ostatnio używane na ekranie głównym).
//
// Każdy cel dotyku ma co najmniej 56 dp wysokości (rękawica), a długie
// przytrzymanie przypina / odpina narzędzie na ekranie głównym.

/// Minimalna wysokość wiersza narzędzia. Rękawica spawalnicza trafia pewnie
/// dopiero w coś tej wielkości — a więcej zamieniłoby menu w długi przewijak.
const double kToolRowMinHeight = 56;

// Specific tools only: do not reuse a generic group photograph when it could
// misrepresent the operation. Other tools retain their icons until a suitable
// photograph is available.
const _toolPhotos = <String, String>{
  'cut_list': 'assets/tool_photos/pipe_cutting.jpg',
  'elbow_takeouts': 'assets/tool_photos/elbows.jpg',
  'reducer': 'assets/tool_photos/reducer.jpg',
  'mitre_bend': 'assets/tool_photos/stainless.jpg',
  'tube_bending': 'assets/tool_photos/tube_bending.jpg',
  'pipe_route': 'assets/tool_photos/route.jpg',
  'pipe_slope': 'assets/tool_photos/pipe_slope.jpg',
  'slope_cut': 'assets/tool_photos/slope_cut.jpg',
  'thermal_expansion': 'assets/tool_photos/pipe_expansion.jpg',
  'flange_check': 'assets/tool_photos/flanges.jpg',
  'bolt_torque': 'assets/tool_photos/bolt_torque.jpg',
  'bolt_kit': 'assets/tool_photos/bolt_kit.png',
  'dn_mm': 'assets/tool_photos/tables.jpg',
  'ndt_plan': 'assets/tool_photos/inspection.jpg',
  'orbital_tig': 'assets/tool_photos/orbital_tig.jpg',
  'grinding': 'assets/tool_photos/grinding.jpg',
  'rigging': 'assets/tool_photos/rigging.jpg',
  'filler_selector': 'assets/tool_photos/filler_selector.jpg',
  'shade': 'assets/tool_photos/welding_mask.jpg',
  'tungsten': 'assets/tool_photos/tungsten.jpg',
  'pipe_supports': 'assets/tool_photos/pipe_supports.jpg',
};

Alignment _toolPhotoAlignment(String id) => switch (id) {
      'cut_list' => const Alignment(-0.6, 0),
      'mitre_bend' => Alignment.centerRight,
      'tube_bending' => Alignment.centerLeft,
      'grinding' => Alignment.centerLeft,
      'slope_cut' => Alignment.centerRight,
      _ => Alignment.center,
    };

double _toolPhotoScale(String id) => switch (id) {
      'mitre_bend' => 2,
      'filler_selector' => 2.5,
      _ => 1,
    };

Alignment _toolPhotoScaleAlignment(String id) => switch (id) {
      'filler_selector' => Alignment.bottomCenter,
      _ => Alignment.centerRight,
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

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _IconBox({required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

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
                        if (_toolPhotos[tool.id] case final photo?)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Transform.scale(
                              scale: _toolPhotoScale(tool.id),
                              alignment: _toolPhotoScaleAlignment(tool.id),
                              child: Image.asset(photo,
                                key: ValueKey('tool-photo-${tool.id}'),
                                width: 54,
                                height: 54,
                                cacheWidth: 216,
                                fit: BoxFit.cover,
                                alignment: _toolPhotoAlignment(tool.id),
                                excludeFromSemantics: true,
                                errorBuilder: (_, __, ___) => _IconBox(
                                    icon: tool.icon,
                                    color: tool.color,
                                    size: 54)),
                            ),
                          )
                        else
                          SizedBox(
                            width: 54,
                            child: Center(
                              child: _IconBox(
                                  icon: tool.icon, color: tool.color, size: 38),
                            ),
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
                  if (_toolPhotos[tool.id] case final photo?)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Transform.scale(
                        scale: _toolPhotoScale(tool.id),
                        alignment: _toolPhotoScaleAlignment(tool.id),
                        child: Image.asset(photo,
                          key: ValueKey('$keyPrefix-photo-${tool.id}'),
                          width: 36,
                          height: 36,
                          cacheWidth: 144,
                          fit: BoxFit.cover,
                          alignment: _toolPhotoAlignment(tool.id),
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => _IconBox(
                              icon: tool.icon, color: tool.color, size: 36)),
                      ),
                    )
                  else
                    _IconBox(icon: tool.icon, color: tool.color, size: 36),
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
  static const _groupPhotos = <ToolGroup, String>{
    ToolGroup.cutProjects: 'assets/tool_photos/workshop.jpg',
    ToolGroup.elbowsFittings: 'assets/tool_photos/elbows.jpg',
    ToolGroup.branches: 'assets/tool_photos/branches.jpg',
    ToolGroup.routeSlope: 'assets/tool_photos/route.jpg',
    ToolGroup.tables: 'assets/tool_photos/tables.jpg',
    ToolGroup.supportsFlanges: 'assets/tool_photos/flanges.jpg',
    ToolGroup.weldParams: 'assets/tool_photos/weld_parameters.jpg',
    ToolGroup.weldCalculators: 'assets/tool_photos/calculators.jpg',
    ToolGroup.inspection: 'assets/tool_photos/inspection.jpg',
    ToolGroup.stainlessFinish: 'assets/tool_photos/stainless.jpg',
    ToolGroup.costing: 'assets/tool_photos/costing.jpg',
  };

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
                        if (_groupPhotos[group] case final photo?) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(photo,
                                key: ValueKey('tool-group-photo-${group.name}'),
                                width: 64,
                                height: 64,
                                cacheWidth: 256,
                                fit: BoxFit.cover,
                                excludeFromSemantics: true),
                          ),
                          const SizedBox(width: 14),
                        ],
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
          if (groups.any(_groupPhotos.containsKey))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('tool-photo-credits'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(context.tr(pl: 'Źródła zdjęć', en: 'Photo credits')),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        'Ghasemimoshref, Gas seamed elbow.jpg; Gas pipe tee.jpg.\n'
                        'Belle Tong, Typical Pipe Spool Workshop.jpg.\n'
                        'Christopher.S.rcbc, Pipe to Flange TIG Welding.jpg.\n'
                        'Merakistarsllp, Wmass carbon steel flanges.jpg.\n'
                        'Wikimedia Commons, CC BY-SA 4.0.\n\n'
                        'Alf van Beem, Piping pic1.JPG; Rhetos, Messschieber misst Kupferrohraußendurchmesser.jpg. Wikimedia Commons, CC0 1.0.\n'
                        'PEO ACWA, Blue Grass Chemical Agent-Destruction Pilot Plant Pipe Welder (22338174219).jpg. Wikimedia Commons, CC BY 2.0.\n'
                        'PEO ACWA, Pueblo Chemical Agent-Destruction Pilot Plant Agent Processing Building (5571653437).jpg. Wikimedia Commons, CC BY 2.0.\n'
                        'Newfoundlandguy, Welding pipe.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'Rm at Dutch Wikipedia, Waterpas.jpg. Wikimedia Commons, CC BY-SA 3.0.\n'
                        'RomanM82, Metal expansion joint on fiberglass piping.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'Sgt. Samuel R. Beyers, U.S. Marine Corps, cutting steel pipe (100823-M-PC721-185). Wikimedia Commons, public domain.\n'
                        'Smigler, Narrow clearance tools.jpg. Wikimedia Commons, CC BY-SA 3.0.\n'
                        'Taylor 49, Threaded rods of different sizes.png. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'Benjam126, Orbital welding - SXMF 1.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'Widar23, Makita DGA504.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'Ghasemimoshref, Gas seamless connections.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'SpanSet1966, Rundschlinge.jpg. Wikimedia Commons, CC BY-SA 3.0.\n'
                        'Triddle, Arc welding electrodes and electrode holder.triddle.jpg; Soerfm, color and brightness. Wikimedia Commons, public domain.\n'
                        'Jorge Franganillo, Calculator.jpg. Wikimedia Commons, CC BY 2.0.\n'
                        'TECNIC Bioprocess Solutions, A man operates industrial machinery in a workshop. Unsplash License.\n'
                        'Flattrackers and Caferacers Parts and bikebuilds, Stainless pipe weld joints.jpg. Wikimedia Commons, CC BY-SA 2.0.\n'
                        'Martink, Buigijzer.jpg. Wikimedia Commons, CC BY-SA 3.0.\n'
                        'Santeri Viinamäki, Welding mask.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'Ruslan468, Wl 15 ф 3.jpg. Wikimedia Commons, CC BY-SA 4.0.\n'
                        'SylvIba, Riser clamps.jpg. Wikimedia Commons, CC BY 3.0.\n'
                        'Dithira Hettiarachchi, A calculator sitting on top of a piece of paper. Unsplash License.\n'
                        '${context.tr(pl: 'Zdjęcia warsztatu, instalacji, kontroli, wyceny, cięcia, giętarki, przyłbicy, podpór, kompensatora oraz montera i spawacza zmniejszono; miniatury wyświetlane są w kadrze.', en: 'The workshop, piping, inspection, costing, cutting, tube bender, welding mask, pipe support, expansion joint, fitter and welder photos were resized; thumbnails are displayed cropped.')}\n\n'
                        'https://commons.wikimedia.org/wiki/File:Gas_seamed_elbow.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Gas_pipe_tee.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Typical_Pipe_Spool_Workshop.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Pipe_to_Flange_TIG_Welding.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Wmass_carbon_steel_flanges.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Piping_pic1.JPG\n\n'
                        'https://commons.wikimedia.org/wiki/File:Messschieber_misst_Kupferrohrau%C3%9Fendurchmesser.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Blue_Grass_Chemical_Agent-Destruction_Pilot_Plant_Pipe_Welder_(22338174219).jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Pueblo_Chemical_Agent-Destruction_Pilot_Plant_Agent_Processing_Building_(5571653437).jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Welding_pipe.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Waterpas.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Narrow_clearance_tools.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Threaded_rods_of_different_sizes.png\n\n'
                        'https://commons.wikimedia.org/wiki/File:Orbital_welding_-_SXMF_1.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Makita_DGA504.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Gas_seamless_connections.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Rundschlinge.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Arc_welding_electrodes_and_electrode_holder.triddle.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Metal_expansion_joint_on_fiberglass_piping.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:A_U.S._Marine_with_8th_Engineer_Support_Battalion,_Logistics_Combat_Element,_attached_to_Special-Purpose_Marine_Air-Ground_Task_Force_Continuing_Promise_2010_(CP10),_cuts_steel_pipe_for_a_fence_in_Limon,_Costa_100823-M-PC721-185.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/Template:PD-USGov-Military-Marines\n\n'
                        'https://commons.wikimedia.org/wiki/File:Stainless_pipe_weld_joints.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Buigijzer.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Welding_mask.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Wl_15_%D1%84_3.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Riser_clamps.jpg\n\n'
                        'https://commons.wikimedia.org/wiki/File:Calculator.jpg\n\n'
                        'https://unsplash.com/photos/a-man-operates-industrial-machinery-in-a-workshop-ZJzv93F6F1U\n\n'
                        'https://unsplash.com/photos/a-calculator-sitting-on-top-of-a-piece-of-paper-6Vc2hC21PFw\n\n'
                        'https://creativecommons.org/licenses/by-sa/4.0/\n\n'
                        'https://creativecommons.org/licenses/by-sa/3.0/\n\n'
                        'https://creativecommons.org/licenses/by/2.0/\n\n'
                        'https://creativecommons.org/licenses/by/3.0/\n\n'
                        'https://creativecommons.org/licenses/by-sa/2.0/\n\n'
                        'https://creativecommons.org/publicdomain/zero/1.0/\n\n'
                        'https://unsplash.com/license'
                      ),
                    ),
                    actions: [TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(context.tr(pl: 'Zamknij', en: 'Close')),
                    )],
                  ),
                ),
                child: Text(context.tr(pl: 'Źródła zdjęć', en: 'Photo credits')),
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
