import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';
import '../widgets/menu_help.dart';
import '../widgets/tool_registry.dart';
import '../widgets/tool_tiles.dart';
import '../widgets/wpqr_chip.dart';

class WelderMenuScreen extends StatelessWidget {
  const WelderMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Spawacz', en: 'Welder')),
        actions: const [HelpButton(help: kWelderMenuHelp)],
      ),
      body: const ToolGroupedMenu(
        section: ToolSection.welder,
        // Show an actionable qualification warning when needed.
        header: [WpqrChipLive(padding: EdgeInsets.only(bottom: 12))],
      ),
    );
  }
}
