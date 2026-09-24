import 'dart:async';

import 'package:flutter/material.dart';

import '../config/feature_flags.dart';
import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../services/tool_usage.dart';
import '../services/user_profile.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart';
import '../widgets/community_gate.dart';
import '../widgets/tool_registry.dart';
import '../widgets/tool_tiles.dart';
import 'ai_chat_screen.dart';
import 'chat_screen.dart';
import 'fitter_menu_screen.dart';
import 'fitter_screen.dart';
import 'help_screen.dart';
import 'jobs_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';
import 'welder_identity_setup_screen.dart';
import 'welder_menu_screen.dart';

// Ekran główny — pierwsze, co monter widzi po otwarciu aplikacji.
//
// Kolejność ułożona pod „szybko sprawdzić jedną rzecz na rusztowaniu":
//   1. krótkie powitanie (imię z profilu, jeśli jest) + liczniki w jednej linii,
//   2. wyszukiwarka narzędzi,
//   3. przypięte narzędzia (długie przytrzymanie dowolnego narzędzia),
//   4. ostatnio używane (4 pozycje, zapisywane lokalnie),
//   5. działy: Monter, Spawacz, Asystent, Czat,
//   6. ostatnie projekty.
//
// Pomoc jest jedna: ikona „?" w pasku otwiera bazę wiedzy. Dawny kafel POMOC
// ją dublował.

const _kBlue = Color(0xFF4A9EFF);
const _kPurple = Color(0xFFAB47BC);
const _kRed = Color(0xFFE57373);
const _kTeal = Color(0xFF26A69A);

/// Ile ostatnio używanych narzędzi pokazuje ekran główny.
const int kRecentShown = 4;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  UserProfile? _profile;
  StreamSubscription<UserProfile?>? _profileSub;

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
    ToolUsageStore.instance.load();
    // Imię do powitania: z pamięci od razu, z dysku chwilę później, a po
    // edycji w profilu — ze strumienia zmian.
    _profile = UserProfileService.instance.current;
    UserProfileService.instance.get().then((p) {
      if (mounted) setState(() => _profile = p);
    });
    _profileSub = UserProfileService.instance.changes.listen((p) {
      if (mounted) setState(() => _profile = p);
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
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

  Future<void> _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// Czat, ogłoszenia i Premium wysyłają dane na serwer — imię, nazwisko i
  /// zasady zbiera bramka dopiero tutaj, nie przy starcie aplikacji.
  Future<void> _openBehindGate(Widget screen) async {
    if (!await ensureCommunityAccess(context)) return;
    if (!mounted) return;
    await _push(screen);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [kArc, kGold],
            ).createShader(b),
            child: const Text(
              'FITTER WELDER PRO',
              maxLines: 1,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white,
              ),
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
              await _push(const WelderIdentitySetupScreen());
              // Trigger rebuild so the badge icon reflects newly-saved
              // identity (filled badge) without a hot reload.
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: context.tr(pl: 'Twój profil', en: 'Your profile'),
            onPressed: () => _push(const ProfileScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: context.tr(pl: 'Pomoc', en: 'Help'),
            onPressed: () => _push(const HelpScreen()),
          ),
          _LanguageButton(lang: lang),
        ],
      ),
      body: RefreshIndicator(
        color: kArc,
        onRefresh: _load,
        child: ListenableBuilder(
          listenable: ToolUsageStore.instance,
          builder: (context, _) => ListView(
            padding: EdgeInsets.fromLTRB(
                0, 0, 0, 24 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              _Greeting(
                firstName: _profile?.firstName,
                totalProjects: _totalProjects,
                totalSegments: _totalSegments,
                unknownCounts: _loading || _loadFailed,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _SearchField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  hasText: _query.isNotEmpty,
                  onChanged: (v) => setState(() => _query = v),
                  onClear: _clearSearch,
                  onSubmitted: (v) {
                    final hits = searchTools(v, lang);
                    if (hits.isNotEmpty) openTool(context, hits.first.tool);
                  },
                ),
              ),
              if (_query.trim().isNotEmpty)
                ..._searchResults(lang)
              else
                ..._dashboard(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _searchResults(AppLanguage lang) {
    final hits = searchTools(_query, lang);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: ToolSectionLabel(
          context.tr(pl: 'Wyniki', en: 'Results'),
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        ),
      ),
      if (hits.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _NoResults(
            query: _query.trim(),
            onHelp: () => _push(const HelpScreen()),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final hit in hits)
                ToolRow(tool: hit.tool, showSection: true),
            ],
          ),
        ),
    ];
  }

  List<Widget> _dashboard() {
    final store = ToolUsageStore.instance;
    final pinned = resolveTools(store.favorites);
    // Przypięte już są na górze — w „ostatnio używanych" byłyby drugi raz.
    final recent = resolveTools(
      store.recent.where((id) => !store.isFavorite(id)),
      limit: kRecentShown,
    );

    return [
      // ── PRZYPIĘTE ───────────────────────────────────────────────────────
      if (pinned.isNotEmpty) ...[
        _Label(context.tr(pl: 'Przypięte', en: 'Pinned')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TwoColumnTiles(
            children: [
              for (final t in pinned)
                ToolCompactTile(tool: t, keyPrefix: 'pinned'),
            ],
          ),
        ),
      ],

      // ── OSTATNIO UŻYWANE ────────────────────────────────────────────────
      if (recent.isNotEmpty) ...[
        _Label(context.tr(pl: 'Ostatnio używane', en: 'Recently used')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TwoColumnTiles(
            children: [
              for (final t in recent)
                ToolCompactTile(tool: t, keyPrefix: 'recent'),
            ],
          ),
        ),
        if (pinned.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.push_pin_outlined, size: 14, color: kTextMut),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Przytrzymaj kafel, żeby przypiąć go na górze.',
                      en: 'Long-press a tile to pin it to the top.',
                    ),
                    style: const TextStyle(fontSize: 12, color: kTextMut),
                  ),
                ),
              ],
            ),
          ),
      ],

      // ── DZIAŁY ──────────────────────────────────────────────────────────
      _Label(context.tr(pl: 'Narzędzia', en: 'Tools')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TwoColumnTiles(children: _sectionTiles()),
      ),

      // ── OSTATNIE PROJEKTY ───────────────────────────────────────────────
      _Label(context.tr(pl: 'Ostatnie projekty', en: 'Recent projects')),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: kArc)),
        )
      else if (_loadFailed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _LoadError(onRetry: _load),
        )
      else if (_recent.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // First-time UX: one tap straight into the cut list — the shortest
          // path to value for a brand-new user.
          child: _TryThis(onTap: () async {
            final cutList = toolById('cut_list');
            if (cutList == null) return;
            await openTool(context, cutList);
            if (mounted) _load();
          }),
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
                            builder: (_) => FitterScreen(projectId: p.id)),
                      ).then((_) => _load()),
                    ))
                .toList(),
          ),
        ),
    ];
  }

  List<Widget> _sectionTiles() {
    final scanner = toolById('iso_scanner');
    return [
      _SectionTile(
        icon: Icons.handyman_outlined,
        title: context.tr(pl: 'MONTER', en: 'FITTER'),
        subtitle:
            context.tr(pl: 'Cięcie, kolana, trasy', en: 'Cuts, elbows, routes'),
        accent: kArc,
        onTap: () => _push(const FitterMenuScreen()),
      ),
      _SectionTile(
        icon: Icons.waves_outlined,
        title: context.tr(pl: 'SPAWACZ', en: 'WELDER'),
        subtitle:
            context.tr(pl: 'Parametry i dziennik', en: 'Parameters, journal'),
        accent: _kBlue,
        onTap: () => _push(const WelderMenuScreen()),
      ),
      // ── Asystent — darmowy; „Wykonaj" działa offline i bez zgody ─────
      _SectionTile(
        icon: Icons.record_voice_over_outlined,
        title: context.tr(pl: 'ASYSTENT', en: 'ASSISTANT'),
        subtitle: context.tr(
            pl: 'Zapis głosem, pytania', en: 'Voice notes, questions'),
        accent: _kTeal,
        onTap: () {
          final assistant = toolById('assistant');
          if (assistant != null) {
            openTool(context, assistant);
          } else {
            _push(const AiChatScreen());
          }
        },
      ),
      // ── Społeczność — darmowa dla wszystkich ──────────────────────────
      if (kCommunityEnabled)
        _SectionTile(
          icon: Icons.forum_outlined,
          title: context.tr(pl: 'CZAT', en: 'CHAT'),
          subtitle: context.tr(pl: 'Rozmowy z fachowcami', en: 'Talk to pros'),
          accent: _kPurple,
          onTap: () => _openBehindGate(const ChatScreen()),
        ),
      // ── Płatne / metered — ukryte całkowicie, nie "wkrótce" ───────────
      if (kJobsEnabled)
        _SectionTile(
          icon: Icons.work_outline,
          title: context.tr(pl: 'PRACA', en: 'JOBS'),
          subtitle: context.tr(pl: 'Ogłoszenia 49 PLN', en: 'Listings 49 PLN'),
          accent: _kRed,
          onTap: () => _openBehindGate(const JobsScreen()),
        ),
      // Skaner stoi za bramką Premium, której nie da się przejść, dopóki
      // płatności są wyłączone — kafel pokazujemy dopiero, gdy zakup jest
      // możliwy (kAiScannerReachable → rejestr narzędzi).
      if (scanner != null)
        _SectionTile(
          icon: scanner.icon,
          title: context.tr(pl: 'SKANER ISO', en: 'ISO SCAN'),
          subtitle: context.tr(
              pl: 'Zdjęcie rysunku → lista cięć', en: 'Photo → cut list'),
          accent: scanner.color,
          onTap: () => openTool(context, scanner),
        ),
      if (kPaidFeaturesEnabled)
        _SectionTile(
          icon: Icons.workspace_premium,
          title: 'PREMIUM',
          subtitle:
              context.tr(pl: 'AI + pełne narzędzia', en: 'AI + full tools'),
          accent: kGold,
          onTap: () => _openBehindGate(const PremiumScreen()),
        ),
    ];
  }
}

// ─── PRZEŁĄCZNIK JĘZYKA ───────────────────────────────────────────────────────
// Cel dotyku co najmniej 48 dp — wcześniej ok. 30 dp, nie do trafienia w
// rękawicy.
class _LanguageButton extends StatelessWidget {
  final AppLanguage lang;
  const _LanguageButton({required this.lang});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<AppLanguage>(
        key: const ValueKey('home-language'),
        tooltip: context.tr(pl: 'Zmień język', en: 'Change language'),
        initialValue: lang,
        onSelected: context.setLanguage,
        itemBuilder: (_) => const [
          PopupMenuItem(value: AppLanguage.pl, child: Text('Polski')),
          PopupMenuItem(value: AppLanguage.en, child: Text('English')),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinTapTarget + 8,
            minHeight: kMinTapTarget,
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, size: 15, color: kArc),
                  const SizedBox(width: 6),
                  Text(
                    lang == AppLanguage.en ? 'EN' : 'PL',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: kArc,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.expand_more, size: 16, color: kArc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── POWITANIE ───────────────────────────────────────────────────────────────
// Dawny baner zajmował ok. 30% ekranu (znaczek „Aktywny", duże liczniki).
// Zostało jedno zdanie i jedna linia liczb.
class _Greeting extends StatelessWidget {
  final String? firstName;
  final int totalProjects;
  final int totalSegments;

  /// Po błędzie odczytu (albo w trakcie) liczba jest NIEZNANA, nie zerowa.
  final bool unknownCounts;

  const _Greeting({
    required this.firstName,
    required this.totalProjects,
    required this.totalSegments,
    required this.unknownCounts,
  });

  @override
  Widget build(BuildContext context) {
    final name = firstName?.trim() ?? '';
    final projects = unknownCounts ? '–' : '$totalProjects';
    final segments = unknownCounts ? '–' : '$totalSegments';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty
                ? context.tr(pl: 'Witaj', en: 'Welcome')
                : context.tr(pl: 'Cześć, $name', en: 'Hi, $name'),
            key: const ValueKey('home-greeting'),
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: kText,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          // Forma „etykieta: N" — polska odmiana po liczbie (1 projekt,
          // 2 projekty, 5 projektów) nie mieści się w jednym szablonie.
          Text(
            context.tr(
              pl: 'Projekty: $projects  ·  Segmenty: $segments',
              en: 'Projects: $projects  ·  Segments: $segments',
            ),
            style: const TextStyle(fontSize: 13, color: kTextSec),
          ),
        ],
      ),
    );
  }
}

// ─── WYSZUKIWARKA ─────────────────────────────────────────────────────────────
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('home-tool-search'),
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: kText, fontSize: 15.5),
      decoration: InputDecoration(
        hintText: context.tr(
          pl: 'Szukaj narzędzia, np. kolano, spadek',
          en: 'Find a tool, e.g. elbow, slope',
        ),
        prefixIcon: const Icon(Icons.search, color: kTextSec),
        suffixIcon: hasText
            ? IconButton(
                icon: const Icon(Icons.close, color: kTextSec),
                tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
                onPressed: onClear,
              )
            : null,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final VoidCallback onHelp;
  const _NoResults({required this.query, required this.onHelp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              pl: 'Brak narzędzia dla „$query".',
              en: 'No tool matches "$query".',
            ),
            style: const TextStyle(
                color: kText, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              pl: 'Spróbuj innego słowa, np. „kolano", „spadek", „DN".',
              en: 'Try another word, e.g. "elbow", "slope", "DN".',
            ),
            style: const TextStyle(color: kTextSec, fontSize: 12.5),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: Text(
                  context.tr(pl: 'Szukaj w pomocy', en: 'Search the help')),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ETYKIETA SEKCJI ─────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return ToolSectionLabel(
      text,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
    );
  }
}

// ─── KAFEL DZIAŁU ─────────────────────────────────────────────────────────────
class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorder),
      ),
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.10),
        highlightColor: accent.withValues(alpha: 0.06),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: accent.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icon, size: 22, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: kText,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: kTextSec, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── PIERWSZY KROK ────────────────────────────────────────────────────────────
class _TryThis extends StatelessWidget {
  final VoidCallback onTap;
  const _TryThis({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kArc.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kArc.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, color: kArc, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(pl: 'SPRÓBUJ TEGO', en: 'TRY THIS'),
                      style: const TextStyle(
                        color: kArc,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                          pl: 'Otwórz listę cięć i dodaj pierwszy segment '
                              'rury. Zajmuje 30 s.',
                          en: 'Open the cut list and add your first pipe '
                              'segment. Takes 30 s.'),
                      style: const TextStyle(
                          color: kText, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: kArc),
            ],
          ),
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
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kFail.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kFail.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_off_outlined, color: kFail, size: 20),
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
                      color: kText, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                      pl: 'Twoje dane są bezpieczne. Kalkulatory działają.',
                      en: 'Your data is safe. The calculators still work.'),
                  style: const TextStyle(
                      color: kTextSec, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(
              context.tr(pl: 'Ponów', en: 'Retry'),
              style: const TextStyle(color: kArc, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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

    final matColor = project.materialGroup == 'SS' ? _kBlue : kArc;
    final matLabel = project.materialGroup;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kCard,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kBorder),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kArc.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_outlined,
                      size: 22, color: kArc),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kText,
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
                        style: const TextStyle(fontSize: 12, color: kTextSec),
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
                    border: Border.all(
                        color: matColor.withValues(alpha: 0.3), width: 1),
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
                const Icon(Icons.chevron_right, size: 18, color: kTextMut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
