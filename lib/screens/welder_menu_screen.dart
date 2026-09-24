import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../theme/app_theme.dart';
import '../widgets/help_button.dart';
import '../widgets/menu_help.dart';
import '../widgets/tool_registry.dart';
import '../widgets/tool_tiles.dart';
import '../widgets/wpqr_chip.dart';

// Menu spawacza: zwarta lista pogrupowana według pracy (parametry,
// kalkulatory, kontrola i dokumentacja, wykończenie nierdzewki). Wpisy żyją
// w rejestrze narzędzi (lib/widgets/tool_registry.dart).

class WelderMenuScreen extends StatelessWidget {
  const WelderMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final checklist = toolById('pre_weld_checklist');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Spawacz', en: 'Welder')),
        actions: const [HelpButton(help: kWelderMenuHelp)],
      ),
      body: ToolGroupedMenu(
        section: ToolSection.welder,
        header: [
          // Above the "try this" tip on purpose: an expired WPQR outranks
          // any suggestion on this menu. Every tool below leads to work
          // that gets stamped with the welder's identity, so the state of
          // that qualification belongs in the header, not three screens
          // deep in the identity form. Draws nothing while the WPQR is
          // valid or no expiry date was entered.
          const WpqrChipLive(padding: EdgeInsets.only(bottom: 12)),
          if (checklist != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TryThis(onOpen: () => openTool(context, checklist)),
            ),
        ],
      ),
    );
  }
}

class _TryThis extends StatelessWidget {
  final VoidCallback onOpen;
  const _TryThis({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFA726);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(pl: 'SPRÓBUJ TEGO', en: 'TRY THIS'),
                  style: const TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                    pl: 'Zacznij od checklisty przed spawaniem — 1 min, zero ryzyka.',
                    en: 'Start with the pre-weld checklist — 1 min, zero risk.',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: kTextSec),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: onOpen,
            child: Text(context.tr(pl: 'Otwórz', en: 'Open')),
          ),
        ],
      ),
    );
  }
}
