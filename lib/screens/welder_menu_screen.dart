import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';
import 'welder_pipes_screen.dart';
import 'welder_tanks_screen.dart';
import 'welder_tools_screen.dart';
import 'weld_journal_screen.dart';

class WelderMenuScreen extends StatelessWidget {
  const WelderMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'SPAWACZ', en: 'WELDER')),
        actions: [HelpButton(help: kHelpWelderMenu)],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width >= 800 ? 4 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            _Tile(
              icon: Icons.oil_barrel_outlined,
              title: context.tr(pl: 'Rury', en: 'Pipes'),
              subtitle: context.tr(pl: 'AMP / Gazy / Zatwierdzone / Moje', en: 'AMP / Gases / Approved / Mine'),
              accentColor: const Color(0xFFE67E22),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelderPipesScreen())),
            ),
            _Tile(
              icon: Icons.propane_tank_outlined,
              title: context.tr(pl: 'Zbiorniki', en: 'Tanks'),
              subtitle: 'AMP / Tandem TIG',
              accentColor: const Color(0xFFEF5350),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelderTanksScreen())),
            ),
            _Tile(
              icon: Icons.calculate_outlined,
              title: context.tr(pl: 'Kalkulatory', en: 'Calculators'),
              subtitle: context.tr(pl: 'Heat Input / Temp / O₂ / Gaz / Timer', en: 'Heat Input / Temp / O₂ / Gas / Timer'),
              accentColor: const Color(0xFF4A9EFF),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelderToolsScreen())),
            ),
            _Tile(
              icon: Icons.article_outlined,
              title: context.tr(pl: 'Dziennik spoin', en: 'Weld journal'),
              subtitle: context.tr(pl: 'Numeracja spoin, parametry, zdjęcia', en: 'Weld numbers, params, photos'),
              accentColor: const Color(0xFF2ECC71),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeldJournalScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accentColor;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: accentColor),
              ),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
