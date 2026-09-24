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

  const ToolRow({super.key, required this.tool, this.showSection = false});

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
                onTap: () => openTool(context, tool),
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
                        _IconBox(icon: tool.icon, color: tool.color, size: 38),
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

/// Menu sekcji (monter / spawacz): narzędzia pogrupowane, wiersze min. 56 dp.
/// Na szerokim ekranie (tablet) wiersze idą w dwóch kolumnach.
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
        final wide = constraints.maxWidth >= 700;
        final children = <Widget>[
          ...widget.header,
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              children: [
                const Icon(Icons.push_pin_outlined, size: 14, color: kTextMut),
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
          for (final group in groupsOf(widget.section)) ...[
            ToolSectionLabel(group.title(context)),
            if (wide)
              _WideGroup(tools: toolsInGroup(group))
            else
              for (final tool in toolsInGroup(group)) ToolRow(tool: tool),
          ],
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
          children: children,
        );
      },
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
