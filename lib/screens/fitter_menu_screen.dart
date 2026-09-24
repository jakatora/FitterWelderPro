import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';
import '../widgets/menu_help.dart';
import '../widgets/tool_registry.dart';
import '../widgets/tool_tiles.dart';

// Menu montera. Zamiast 21 równych kafli w połowie pustych — zwarta lista
// pogrupowana według pracy (cięcie, kolana, odgałęzienia, trasa, tabele,
// podpory). Wpisy, ikony i ekrany docelowe żyją w jednym rejestrze
// (lib/widgets/tool_registry.dart), wspólnym z wyszukiwarką na ekranie głównym.

class FitterMenuScreen extends StatelessWidget {
  const FitterMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Monter', en: 'Fitter')),
        actions: const [HelpButton(help: kFitterMenuHelp)],
      ),
      body: const ToolGroupedMenu(section: ToolSection.fitter),
    );
  }
}
