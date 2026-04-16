import 'package:flutter/material.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import 'fitter_menu_screen.dart';
import 'fitter_screen.dart';
import 'help_screen.dart';
import 'welder_menu_screen.dart';

// ─── Kolory spójne z motywem ──────────────────────────────────────────────────
const _kOrange  = Color(0xFFF5A623);
const _kGold    = Color(0xFFE8C14B);
const _kBlue    = Color(0xFF4A9EFF);
const _kGreen   = Color(0xFF2ECC71);
const _kBorder  = Color(0xFF2C3354);
const _kCard    = Color(0xFF1A1D26);
const _kSurface = Color(0xFF22263A);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();

  List<Project> _recent = [];
  int _totalProjects = 0;
  int _totalSegments = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await _projectDao.listAll();
    int segs = 0;
    for (final p in projects) {
      final s = await _segmentDao.listForProject(p.id);
      segs += s.length;
    }
    if (!mounted) return;
    setState(() {
      _totalProjects = projects.length;
      _totalSegments = segs;
      _recent = projects.take(3).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D26),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [_kOrange, _kGold],
          ).createShader(b),
          child: const Text(
            'FITTER WELDER PRO',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Colors.white,
            ),
          ),
        ),
        actions: [
          PopupMenuButton<AppLanguage>(
            tooltip: context.tr(pl: 'Zmień język', en: 'Change language'),
            initialValue: lang,
            onSelected: context.setLanguage,
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppLanguage.pl, child: Text('Polski')),
              PopupMenuItem(value: AppLanguage.en, child: Text('English')),
            ],
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                lang == AppLanguage.en ? 'EN' : 'PL',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _kOrange,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kOrange,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              0, 0, 0, 24 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            // ── HERO BANNER ────────────────────────────────────────────────
            _HeroBanner(
              totalProjects: _totalProjects,
              totalSegments: _totalSegments,
              loading: _loading,
            ),

            const SizedBox(height: 20),

            // ── SEKCJA: NARZĘDZIA ──────────────────────────────────────────
            _SectionLabel(context.tr(pl: 'Narzędzia', en: 'Tools')),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.55,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MenuCard(
                    icon: Icons.handyman_outlined,
                    title: 'FITTER',
                    subtitle: context.tr(
                        pl: 'Cut list, kalkulatory',
                        en: 'Cut list, calculators'),
                    accent: _kOrange,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const FitterMenuScreen())),
                  ),
                  _MenuCard(
                    icon: Icons.waves_outlined,
                    title: context.tr(pl: 'SPAWACZ', en: 'WELDER'),
                    subtitle: context.tr(
                        pl: 'Parametry, gazy',
                        en: 'Params, gases'),
                    accent: _kBlue,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const WelderMenuScreen())),
                  ),
                  _MenuCard(
                    icon: Icons.help_outline_rounded,
                    title: context.tr(pl: 'POMOC', en: 'HELP'),
                    subtitle: context.tr(
                        pl: 'Porady, FAQ',
                        en: 'Tips, FAQ'),
                    accent: _kGreen,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const HelpScreen())),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── SEKCJA: OSTATNIE PROJEKTY ──────────────────────────────────
            _SectionLabel(
                context.tr(pl: 'Ostatnie projekty', en: 'Recent projects')),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: _kOrange)),
              )
            else if (_recent.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_outlined,
                          color: _kTextMut, size: 28),
                      const SizedBox(width: 14),
                      Text(
                        context.tr(
                            pl: 'Brak projektów — zacznij w FITTER → CUT LIST',
                            en: 'No projects yet — start in FITTER → CUT LIST'),
                        style: const TextStyle(
                            color: _kTextMut, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _recent
                      .map((p) => _ProjectTile(
                            project: p,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      FitterScreen(projectId: p.id)),
                            ).then((_) => _load()),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── HERO BANNER ─────────────────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  final int totalProjects;
  final int totalSegments;
  final bool loading;

  const _HeroBanner({
    required this.totalProjects,
    required this.totalSegments,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1D26), Color(0xFF22263A), Color(0xFF1A1D2E)],
        ),
        border: Border(
          bottom: BorderSide(color: _kBorder, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Iskra spawalnicza — dekoracja
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: _kOrange.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _kGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.tr(pl: 'Aktywny', en: 'Active'),
                      style: const TextStyle(
                          color: _kGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            context.tr(
                pl: 'Witaj, Spawaczu 👷',
                en: 'Welcome, Welder 👷'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE8ECF0),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Twoje narzędzia gotowe do pracy',
                en: 'Your tools are ready'),
            style: const TextStyle(fontSize: 13, color: _kTextSec),
          ),
          const SizedBox(height: 18),
          // Statystyki
          Row(
            children: [
              _StatChip(
                value: loading ? '–' : '$totalProjects',
                label: context.tr(pl: 'Projekty', en: 'Projects'),
                icon: Icons.folder_outlined,
                color: _kOrange,
              ),
              const SizedBox(width: 10),
              _StatChip(
                value: loading ? '–' : '$totalSegments',
                label: context.tr(pl: 'Segmenty', en: 'Segments'),
                icon: Icons.linear_scale,
                color: _kBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, color: _kTextMut, height: 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SEKCJA LABEL ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kTextMut,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ─── KARTA MENU ───────────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder, width: 1),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Pasek koloru na dole
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(height: 2, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE8ECF0),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: _kTextMut, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── KAFELEK PROJEKTU ─────────────────────────────────────────────────────────
class _ProjectTile extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const _ProjectTile({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (project.name?.trim().isNotEmpty == true)
        ? project.name!
        : context.tr(pl: 'Projekt', en: 'Project');

    final matColor =
        project.materialGroup == 'SS' ? _kBlue : _kOrange;
    final matLabel = project.materialGroup;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder, width: 1),
        ),
        child: Row(
          children: [
            // Ikona
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _kOrange.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_outlined,
                  size: 22, color: _kOrange),
            ),
            const SizedBox(width: 12),
            // Dane projektu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8ECF0),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Ø${project.diameterMm.toStringAsFixed(1)} mm  ·  '
                    't ${project.wallThicknessMm.toStringAsFixed(1)} mm',
                    style: const TextStyle(
                        fontSize: 12, color: _kTextMut),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Badge materiału
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: matColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: matColor.withOpacity(0.3), width: 1),
              ),
              child: Text(
                matLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: matColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: _kTextMut),
          ],
        ),
      ),
    );
  }
}
