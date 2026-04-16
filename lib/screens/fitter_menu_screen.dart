import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import 'projects_screen.dart';
import 'component_library_screen.dart';
import 'fitter_tools_screen.dart';
import 'field_assembly_screen.dart';
import 'spool_planner_screen.dart';
import 'dn_mm_screen.dart';

class FitterMenuScreen extends StatelessWidget {
  const FitterMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(pl: 'FITTER', en: 'FITTER'))),
      body: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width >= 800 ? 4 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            _Tile(
              icon: Icons.assignment_outlined,
              title: 'CUT LIST',
              subtitle: context.tr(pl: 'Projekty', en: 'Projects'),
              accentColor: const Color(0xFFF5A623),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsScreen())),
            ),
            _Tile(
              icon: Icons.table_chart_outlined,
              title: 'DN-MM',
              subtitle: 'DN ↔ OD (mm) + NPS',
              accentColor: const Color(0xFF5C6BC0),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DnMmScreen())),
            ),

            _Tile(
              icon: Icons.content_cut_outlined,
              title: context.tr(pl: 'Cięcie kolanka', en: 'Elbow cut'),
              subtitle: context.tr(pl: 'Kąt docelowy', en: 'Target angle'),
              accentColor: const Color(0xFF26A69A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FitterToolsScreen(initialTab: 1)),
              ),
            ),
            _Tile(
              icon: Icons.rotate_right,
              title: context.tr(pl: 'Obrót kolanka', en: 'Elbow rotation'),
              subtitle: '% / °',
              accentColor: const Color(0xFF42A5F5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FitterToolsScreen(initialTab: 2)),
              ),
            ),
            _Tile(
              icon: Icons.straighten,
              title: context.tr(pl: 'Wstawka', en: 'Insert'),
              subtitle: context.tr(pl: 'Ø / R / kąt / odejście', en: 'Ø / R / angle / offset'),
              accentColor: const Color(0xFFAB47BC),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FitterToolsScreen(initialTab: 3)),
              ),
            ),
            _Tile(
              icon: Icons.compress,
              title: context.tr(pl: 'Skracanie redukcji', en: 'Reducer trimming'),
              subtitle: context.tr(pl: 'Ø wyjściowa', en: 'Outlet Ø'),
              accentColor: const Color(0xFFEF5350),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FitterToolsScreen(initialTab: 4)),
              ),
            ),
            _Tile(
              icon: Icons.trending_down,
              title: context.tr(pl: 'Spadek', en: 'Slope'),
              subtitle: context.tr(pl: 'miter – 1 cięcie', en: 'miter - 1 cut'),
              accentColor: const Color(0xFFFFA726),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FitterToolsScreen(initialTab: 0)),
              ),
            ),
            _Tile(
              icon: Icons.route_outlined,
              title: context.tr(pl: 'Projektant trasy', en: 'Route planner'),
              subtitle: context.tr(pl: 'Dobierz komponenty A→B z kierunkami', en: 'Pick components A→B with directions'),
              accentColor: const Color(0xFFAB47BC),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SpoolPlannerScreen()),
              ),
            ),
            _Tile(
              icon: Icons.build_circle_outlined,
              title: context.tr(pl: 'Montaż w terenie', en: 'Field assembly'),
              subtitle: context.tr(pl: 'Etaż / prosta — bez ISO', en: 'Offset / straight — no ISO'),
              accentColor: const Color(0xFF2ECC71),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FieldAssemblyScreen()),
              ),
            ),
            _Tile(
              icon: Icons.inventory_2_outlined,
              title: context.tr(pl: 'Biblioteka komponentów', en: 'Component library'),
              subtitle: 'SS / CS',
              accentColor: const Color(0xFF78909C),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComponentLibraryScreen()),
              ),
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
