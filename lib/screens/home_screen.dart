import 'package:flutter/material.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../services/welder_identity.dart';
import 'chat_screen.dart';
import 'iso_scanner_screen.dart';
import 'fitter_menu_screen.dart';
import 'fitter_screen.dart';
import 'help_screen.dart';
import 'jobs_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';
import 'welder_identity_setup_screen.dart';
import 'welder_menu_screen.dart';
import '../config/feature_flags.dart';
import '../widgets/help_button.dart';

// ─── Kolory spójne z motywem ──────────────────────────────────────────────────
const _kOrange  = Color(0xFFFF8E1E);
const _kGold    = Color(0xFFE8C14B);
const _kBlue    = Color(0xFF4A9EFF);
const _kGreen   = Color(0xFF2ECC71);
const _kRed     = Color(0xFFE57373);
const _kPurple  = Color(0xFFAB47BC);
const _kBorder  = Color(0xFF2A3140);
const _kCard    = Color(0xFF141821);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF5A6478);

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

  /// Odczyt bazy padł. Trzymamy to jawnie, bo „masz 0 projektów" i „nie wiem,
  /// ile masz projektów" to dwa różne komunikaty — a ekran pokazywał ten
  /// pierwszy w obu przypadkach.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted && _loadFailed) setState(() => _loadFailed = false);
    try {
      final projects = await _projectDao.listAll();
      // Sequential `await` per project blocks home screen open by N×~50 ms.
      // Parallelise with `Future.wait` so total wall-time is one DAO round-trip
      // (better-sqlite3 serialises internally; the win is the absence of
      // intermediate `await` ticks on the UI thread).
      final segLists = await Future.wait(
        projects.map((p) => _segmentDao.listForProject(p.id)),
      );
      final segs = segLists.fold<int>(0, (n, s) => n + s.length);
      if (!mounted) return;
      setState(() {
        _totalProjects = projects.length;
        _totalSegments = segs;
        _recent = projects.take(3).toList();
        _loading = false;
      });
    } catch (e) {
      // P0-11: HomeScreen had ZERO error handling — wedged spinner wygląda jak
      // zepsuta apka i monter ją odinstalowuje.
      //
      // Był tu SnackBar, ale to zły nośnik dla błędu CAŁEGO ekranu: pływający
      // dymek nie znika po wejściu w inny ekran, wędruje za użytkownikiem i
      // przykrywa treść. Błąd należy do miejsca, w którym powstał — pokazujemy
      // go w treści, obok pustej listy projektów.
      debugPrint('HomeScreen load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141821),
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
          // P0-08: gate to the persistent welder identity setup. Badge
          // is open if the user hasn't saved one yet — they need it
          // before the weld journal is audit-traceable.
          IconButton(
            icon: Icon(
              WelderIdentityService.instance.current == null
                  ? Icons.badge_outlined
                  : Icons.badge,
            ),
            tooltip: context.tr(
              pl: 'Tożsamość spawacza',
              en: 'Welder identity',
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WelderIdentitySetupScreen()),
              );
              // Trigger rebuild so the badge icon reflects newly-saved
              // identity (filled badge) without a hot reload.
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: context.tr(pl: 'Twój profil', en: 'Your profile'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          HelpButton(help: kHelpHome),
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
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language, size: 14, color: _kOrange),
                  const SizedBox(width: 6),
                  Text(
                    lang == AppLanguage.en ? 'EN' : 'PL',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _kOrange,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more, size: 16, color: _kOrange),
                ],
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
              failed: _loadFailed,
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
                  // ── Społeczność — darmowa dla wszystkich ──────────────────
                  if (kCommunityEnabled)
                    _MenuCard(
                      icon: Icons.forum_outlined,
                      title: context.tr(pl: 'CZAT', en: 'CHAT'),
                      subtitle: context.tr(
                          pl: 'Rozmawiaj z fachem',
                          en: 'Talk to pros'),
                      accent: _kPurple,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const ChatScreen())),
                    ),
                  // ── Płatne / metered — ukryte całkowicie, nie "wkrótce" ───
                  if (kJobsEnabled)
                    _MenuCard(
                      icon: Icons.work_outline,
                      title: context.tr(pl: 'PRACA', en: 'JOBS'),
                      subtitle: context.tr(
                          pl: 'Ogłoszenia 49 PLN',
                          en: 'Listings 49 PLN'),
                      accent: _kRed,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const JobsScreen())),
                    ),
                  // Skaner stoi za bramką Premium, której nie da się przejść,
                  // dopóki płatności są wyłączone — kafel pokazujemy dopiero,
                  // gdy zakup jest możliwy (kAiScannerReachable).
                  if (kAiScannerReachable)
                    _MenuCard(
                      icon: Icons.document_scanner_outlined,
                      title: context.tr(pl: 'SKANER ISO', en: 'ISO SCAN'),
                      subtitle: context.tr(
                          pl: 'Zdjęcie rysunku → CUT',
                          en: 'Photo → CUT list'),
                      accent: const Color(0xFFEF6C00),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const IsoScannerScreen())),
                    ),
                  if (kPaidFeaturesEnabled)
                    _MenuCard(
                      icon: Icons.workspace_premium,
                      title: 'PREMIUM',
                      subtitle: context.tr(
                          pl: 'AI + pełne tools',
                          en: 'AI + full tools'),
                      accent: _kGold,
                      badge: context.tr(pl: 'PRO', en: 'PRO'),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const PremiumScreen())),
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
            else if (_loadFailed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _LoadError(onRetry: _load),
              )
            else if (_recent.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                // First-time UX: tappable coaching callout — taps open FITTER
                // menu directly so a brand-new user has a 1-tap path to value.
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FitterMenuScreen()),
                  ).then((_) => _load()),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _kOrange.withValues(alpha: 0.35), width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _kOrange.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.auto_awesome,
                              color: _kOrange, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr(
                                    pl: 'Spróbuj tego',
                                    en: 'Try this'),
                                style: const TextStyle(
                                  color: _kOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.tr(
                                    pl: 'Otwórz FITTER → CUT LIST i dodaj '
                                        'pierwszy segment rury. Zajmuje 30 s.',
                                    en: 'Open FITTER → CUT LIST and add your '
                                        'first pipe segment. Takes 30 s.'),
                                style: const TextStyle(
                                    color: Color(0xFFE7ECF3),
                                    fontSize: 13,
                                    height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right,
                            size: 20, color: _kOrange),
                      ],
                    ),
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
  final bool failed;

  const _HeroBanner({
    required this.totalProjects,
    required this.totalSegments,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141821), Color(0xFF22263A), Color(0xFF1A1D2E)],
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
                  color: _kOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: _kOrange.withValues(alpha: 0.3), width: 1),
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
              color: Color(0xFFE7ECF3),
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
              // Po błędzie odczytu liczba jest NIEZNANA, nie zerowa.
              _StatChip(
                value: (loading || failed) ? '–' : '$totalProjects',
                label: context.tr(pl: 'Projekty', en: 'Projects'),
                icon: Icons.folder_outlined,
                color: _kOrange,
              ),
              const SizedBox(width: 10),
              _StatChip(
                value: (loading || failed) ? '–' : '$totalSegments',
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
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
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

// ─── BŁĄD ODCZYTU PROJEKTÓW ───────────────────────────────────────────────────
// Świadomie w treści, nie w SnackBarze: błąd całego ekranu ma zostać tam, gdzie
// powstał, dopóki go nie naprawimy — a nie zniknąć po czterech sekundach ani
// wędrować za użytkownikiem na kolejne ekrany.
class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0655A).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0655A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_off_outlined,
                color: Color(0xFFF0655A), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                      pl: 'Nie udało się wczytać projektów',
                      en: 'Could not load projects'),
                  style: const TextStyle(
                      color: Color(0xFFE7ECF3),
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                      pl: 'Twoje dane są bezpieczne. Kalkulatory działają.',
                      en: 'Your data is safe. The calculators still work.'),
                  style: const TextStyle(
                      color: _kTextMut, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(
              context.tr(pl: 'Ponów', en: 'Retry'),
              style: const TextStyle(
                  color: _kOrange, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
  final String? badge;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1F29), Color(0xFF14171E)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          child: Stack(
            children: [
              // Accent spine — a thin vertical channel that reads like the
              // labelled edge of a measuring instrument, not decoration.
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Container(width: 3, color: accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.25)),
                          ),
                          child: Icon(icon, size: 21, color: accent),
                        ),
                        const Spacer(),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.40)),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: accent,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFEDF1F7),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
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
                color: _kOrange.withValues(alpha: 0.10),
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
                      color: Color(0xFFE7ECF3),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    // Edge-case: brand-new projects start at 0/0, and a bad
                    // DB row could carry NaN/Infinity. Either way, rendering
                    // "Ø0.0 mm · t 0.0 mm" / "ØNaN mm" on the tile is noise
                    // for a fitter scanning the recent list — show a dash.
                    () {
                      final d = project.diameterMm;
                      final t = project.wallThicknessMm;
                      final dOk = d.isFinite && d > 0;
                      final tOk = t.isFinite && t > 0;
                      if (!dOk && !tOk) {
                        return context.tr(
                            pl: 'Wymiary nieustawione',
                            en: 'Dimensions not set');
                      }
                      final dStr = dOk ? d.toStringAsFixed(1) : '—';
                      final tStr = tOk ? t.toStringAsFixed(1) : '—';
                      return 'Ø$dStr mm  ·  t $tStr mm';
                    }(),
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
                color: matColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: matColor.withValues(alpha: 0.3), width: 1),
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
