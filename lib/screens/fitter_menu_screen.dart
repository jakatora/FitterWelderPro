import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';
import 'projects_screen.dart';
import 'component_library_screen.dart';
import 'fitter_tools_screen.dart';
import 'dn_mm_screen.dart';
import 'pipe_route_calculator_screen.dart';
import 'rolling_offset_screen.dart';
import 'pipe_slope_screen.dart';
import 'saddle_cut_screen.dart';
import 'iso_notebook_screen.dart';
import 'iso_scanner_screen.dart';
import 'bolt_torque_screen.dart';
import 'elbow_takeout_screen.dart';
import 'pipe_schedule_screen.dart';
import 'saddle_template_screen.dart';
import 'quick_converter_screen.dart';
import 'sanitary_tube_screen.dart';
import 'support_config_screen.dart';

class FitterMenuScreen extends StatelessWidget {
  const FitterMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'FITTER', en: 'FITTER')),
        actions: [HelpButton(help: kHelpFitterMenu)],
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
              icon: Icons.inventory_2_outlined,
              title: context.tr(pl: 'Biblioteka komponentów', en: 'Component library'),
              subtitle: 'SS / CS',
              accentColor: const Color(0xFF78909C),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComponentLibraryScreen()),
              ),
            ),
            _Tile(
              icon: Icons.account_tree_outlined,
              title: context.tr(pl: 'Trasa rur', en: 'Pipe route'),
              subtitle: context.tr(pl: '3 kolanka 90° – odcinki', en: '3 × 90° elbows – segments'),
              accentColor: const Color(0xFF00897B),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PipeRouteCalculatorScreen()),
              ),
            ),
            _Tile(
              icon: Icons.swap_vert_circle_outlined,
              title: context.tr(pl: 'Rolling Offset', en: 'Rolling Offset'),
              subtitle: context.tr(pl: 'Rise + Spread → Travel', en: 'Rise + Spread → Travel'),
              accentColor: const Color(0xFF1E88E5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RollingOffsetScreen()),
              ),
            ),
            _Tile(
              icon: Icons.show_chart,
              title: context.tr(pl: 'Spadek rury', en: 'Pipe slope'),
              subtitle: context.tr(pl: '% / mm/m / kąt', en: '% / mm/m / angle'),
              accentColor: const Color(0xFFFF7043),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PipeSlopeScreen()),
              ),
            ),
            _Tile(
              icon: Icons.join_full_outlined,
              title: context.tr(pl: 'Saddle Cut', en: 'Saddle Cut'),
              subtitle: context.tr(pl: 'Wycięcie siodłowe – odgałęzienie', en: 'Fish-mouth cut – branch pipe'),
              accentColor: const Color(0xFF8E24AA),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SaddleCutScreen()),
              ),
            ),
            _Tile(
              icon: Icons.grid_on,
              title: context.tr(pl: 'Zeszyt ISO', en: 'ISO Notebook'),
              subtitle: context.tr(pl: 'Rysuj trasy rur na siatce ISO', en: 'Draw pipe routes on ISO grid'),
              accentColor: const Color(0xFF5C6BC0),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IsoNotebookScreen()),
              ),
            ),
            _Tile(
              icon: Icons.document_scanner_outlined,
              title: context.tr(pl: 'Skaner izometryku', en: 'Iso scanner'),
              subtitle: context.tr(pl: 'Zdjęcie rysunku → CUT list', en: 'Photo of drawing → CUT list'),
              accentColor: const Color(0xFFEF6C00),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IsoScannerScreen()),
              ),
            ),
            _Tile(
              icon: Icons.table_rows_outlined,
              title: context.tr(pl: 'Wymiary kolan', en: 'Elbow takeouts'),
              subtitle: context.tr(pl: 'centre–face: LR/SR 90° i 45°', en: 'centre–face: LR/SR 90° & 45°'),
              accentColor: const Color(0xFFE57373),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ElbowTakeoutScreen()),
              ),
            ),
            _Tile(
              icon: Icons.swap_horiz_outlined,
              title: context.tr(pl: 'Konwerter jednostek', en: 'Unit converter'),
              subtitle: context.tr(pl: 'mm/in, °C/°F, bar/MPa/psi', en: 'mm/in, °C/°F, bar/MPa/psi'),
              accentColor: const Color(0xFF66BB6A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QuickConverterScreen()),
              ),
            ),
            _Tile(
              icon: Icons.view_column_outlined,
              title: context.tr(pl: 'Grubości ścianek', en: 'Wall thickness'),
              subtitle: context.tr(pl: 'Sch 10S/STD/40/80/160 + kg/m', en: 'Sch 10S/STD/40/80/160 + kg/m'),
              accentColor: const Color(0xFF7E57C2),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PipeScheduleScreen()),
              ),
            ),
            _Tile(
              icon: Icons.water_drop_outlined,
              title: context.tr(pl: 'Rury sanitarne', en: 'Sanitary tube'),
              subtitle: context.tr(pl: 'Food/pharma: ASME BPE + DIN 11850', en: 'Food/pharma: ASME BPE + DIN 11850'),
              accentColor: const Color(0xFF26A69A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SanitaryTubeScreen()),
              ),
            ),
            _Tile(
              icon: Icons.anchor_outlined,
              title: context.tr(pl: 'Podpory rur', en: 'Pipe supports'),
              subtitle: context.tr(pl: 'Rozstaw, typy, zasady', en: 'Spacing, types, rules'),
              accentColor: const Color(0xFF8D6E63),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportConfigScreen()),
              ),
            ),
            _Tile(
              icon: Icons.bolt_outlined,
              title: context.tr(pl: 'Moment śrub', en: 'Bolt torque'),
              subtitle: context.tr(pl: 'B7/B7M/B16/B8M • PRO', en: 'B7/B7M/B16/B8M • PRO'),
              accentColor: const Color(0xFFE8C14B),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BoltTorqueScreen()),
              ),
            ),
            _Tile(
              icon: Icons.crop_din_outlined,
              title: context.tr(pl: 'Saddle / Coping', en: 'Saddle / Coping'),
              subtitle: context.tr(pl: 'Szablon PDF do druku • PRO', en: 'Printable PDF template • PRO'),
              accentColor: const Color(0xFF26A69A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SaddleTemplateScreen()),
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
                  color: accentColor.withValues(alpha: 0.12),
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
