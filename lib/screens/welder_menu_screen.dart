import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';
import 'welder_pipes_screen.dart';
import 'welder_tanks_screen.dart';
import 'welder_tools_screen.dart';
import 'weld_journal_screen.dart';
import 'orbital_tig_screen.dart';
import 'heat_input_screen.dart';
import 'heat_tint_screen.dart';
import 'pre_weld_checklist_screen.dart';
import 'coupon_log_screen.dart';
import 'tungsten_screen.dart';
import 'passivation_screen.dart';
import 'hydrotest_screen.dart';

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
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA726).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFA726).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFFFA726)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr(pl: 'SPRÓBUJ TEGO', en: 'TRY THIS'),
                              style: const TextStyle(
                                color: Color(0xFFFFA726),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.tr(
                                pl: 'Zacznij od Checklisty przed spawaniem — 1 min, zero ryzyka.',
                                en: 'Start with Pre-weld checklist — 1 min, zero risk.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PreWeldChecklistScreen()),
                        ),
                        child: Text(context.tr(pl: 'Otwórz', en: 'Open')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 800 ? 4 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              delegate: SliverChildListDelegate([
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
              subtitle: context.tr(pl: 'Weld map BPE, numeracja, śledzenie', en: 'BPE weld map, numbering, traceability'),
              accentColor: const Color(0xFF2ECC71),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeldJournalScreen())),
            ),
            _Tile(
              icon: Icons.donut_large_outlined,
              title: context.tr(pl: 'Orbital TIG', en: 'Orbital TIG'),
              subtitle: context.tr(pl: 'Parametry startowe, czas spoiny', en: 'Starting parameters, weld time'),
              accentColor: const Color(0xFF26C6DA),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrbitalTigScreen())),
            ),
            _Tile(
              icon: Icons.palette_outlined,
              title: context.tr(pl: 'Przebarwienia', en: 'Heat tint'),
              subtitle: context.tr(pl: 'Karta kolorów spoiny, akceptacja', en: 'Weld colour chart, acceptance'),
              accentColor: const Color(0xFFAB47BC),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeatTintScreen())),
            ),
            _Tile(
              icon: Icons.checklist_rtl,
              title: context.tr(pl: 'Checklista', en: 'Checklist'),
              subtitle: context.tr(pl: 'Kontrola przed spawaniem', en: 'Pre-weld check'),
              accentColor: const Color(0xFFFFA726),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PreWeldChecklistScreen())),
            ),
            _Tile(
              icon: Icons.science_outlined,
              title: context.tr(pl: 'Log kuponów', en: 'Coupon log'),
              subtitle: context.tr(pl: 'Próbki spawów dnia', en: "Daily test coupons"),
              accentColor: const Color(0xFF66BB6A),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CouponLogScreen())),
            ),
            _Tile(
              icon: Icons.bolt_outlined,
              title: context.tr(pl: 'Elektroda wolframowa', en: 'Tungsten electrode'),
              subtitle: context.tr(pl: 'Dobór Ø wg prądu, typy', en: 'Ø by current, types'),
              accentColor: const Color(0xFF5C6BC0),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TungstenScreen())),
            ),
            _Tile(
              icon: Icons.cleaning_services_outlined,
              title: context.tr(pl: 'Trawienie i pasywacja', en: 'Pickling & passivation'),
              subtitle: context.tr(pl: 'Obróbka powierzchni po spawaniu', en: 'Post-weld surface treatment'),
              accentColor: const Color(0xFFEC407A),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PassivationScreen())),
            ),
            _Tile(
              icon: Icons.water_outlined,
              title: context.tr(pl: 'Próba ciśnieniowa', en: 'Hydrostatic test'),
              subtitle: context.tr(pl: 'Test pressure, objętość, czas', en: 'Test pressure, volume, time'),
              accentColor: const Color(0xFF1976D2),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HydrotestScreen())),
            ),
            _Tile(
              icon: Icons.local_fire_department_outlined,
              title: context.tr(pl: 'Heat Input + CE', en: 'Heat Input + CE'),
              subtitle: context.tr(pl: 'Preheat z chemii • PRO', en: 'Preheat from chemistry • PRO'),
              accentColor: const Color(0xFFE8C14B),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeatInputScreen())),
            ),
              ]),
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
