// Słownik spawalniczy PL · EN · DE · NL · NO — offline.
//
// Monter za granicą wpisuje słowo w dowolnym języku (bez polskich, niemieckich
// i norweskich znaków), numer niezgodności ISO 6520-1 („5011”) albo procesu
// ISO 4063 („135”) i od razu widzi polski termin oraz tłumaczenie na swój
// „język docelowy” (DE/NL/NO/EN, zapamiętany). Rozwinięcie pokazuje wszystkie
// pięć języków, definicję i numer normy; każde tłumaczenie można skopiować.
// „Pokaż rozmówcy” daje pełny ekran z ogromnym napisem — telefon podaje się
// Niemcowi czy Norwegowi, a przycisk / dwuklik obraca napis o 180°.
//
// Dane: lib/data/welding_glossary.dart, wyszukiwarka: lib/domain/glossary/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/welding_glossary.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../domain/glossary/glossary.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';

class GlossaryPage extends StatefulWidget {
  const GlossaryPage({super.key});

  /// Wybrany „mój język docelowy” (nazwa [GlossaryLang]).
  static const String targetPrefsKey = 'glossary_target_lang_v1';

  /// Identyfikatory ulubionych terminów.
  static const String favoritesPrefsKey = 'glossary_favorites_v1';

  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage>
    with ToolHandleHost<GlossaryPage> {
  String? _assistantTermId;
  @override
  String get toolId => 'glossary';
  @override
  Set<String> get supportedFields => const {'term_id', 'target'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final rejected = fields.keys.toSet().difference(supportedFields);
    final term =
        kWeldingGlossary.where((t) => t.id == fields['term_id']).firstOrNull;
    final target = GlossaryLang.values
        .where((l) => l.name == fields['target'])
        .firstOrNull;
    if (term == null) rejected.add('term_id');
    if (fields.containsKey('target') &&
        (target == null || !GlossaryLang.targets.contains(target))) {
      rejected.add('target');
    }
    if (rejected.isNotEmpty || !mounted) {
      return rejected.isEmpty ? fields.keys.toSet() : rejected;
    }
    _search.text = term!.pl;
    setState(() {
      _assistantTermId = term.id;
      _category = null;
      _onlyFavorites = false;
      _expanded
        ..clear()
        ..add(term.id);
      if (target != null) _target = target;
    });
    _scrollToTop();
    return {};
  }

  final _search = TextEditingController();
  final _list = ScrollController();
  String _lastQuery = '';

  GlossaryLang _target = GlossaryLang.de;
  GlossaryCategory? _category;
  bool _onlyFavorites = false;
  Set<String> _favorites = <String>{};
  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQuery);
    unawaited(_restore().whenComplete(markReady));
  }

  @override
  void dispose() {
    _search.removeListener(_onQuery);
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  void _onQuery() {
    if (!mounted || _search.text == _lastQuery) return;
    _lastQuery = _search.text;
    _assistantTermId = null;
    _scrollToTop();
    setState(() {});
  }

  /// Nowe zapytanie / filtr — wyniki od góry, nie od starego przewinięcia.
  void _scrollToTop() {
    if (_list.hasClients) _list.jumpTo(0);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final target =
          GlossaryLang.parse(prefs.getString(GlossaryPage.targetPrefsKey));
      final favs =
          prefs.getStringList(GlossaryPage.favoritesPrefsKey) ?? const [];
      if (!mounted) return;
      setState(() {
        if (target != null && GlossaryLang.targets.contains(target)) {
          _target = target;
        }
        _favorites = favs.toSet();
      });
    } catch (e) {
      // Bez zapisu też działa — domyślnie DE, bez ulubionych.
      debugPrint('glossary prefs restore failed: $e');
    }
  }

  Future<void> _setTarget(GlossaryLang lang) async {
    unawaited(Haptic.tap());
    setState(() => _target = lang);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(GlossaryPage.targetPrefsKey, lang.name);
    } catch (e) {
      debugPrint('glossary target save failed: $e');
    }
  }

  Future<void> _toggleFavorite(GlossaryTerm term) async {
    unawaited(Haptic.tap());
    final next = {..._favorites};
    if (!next.remove(term.id)) next.add(term.id);
    setState(() => _favorites = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          GlossaryPage.favoritesPrefsKey, next.toList()..sort());
    } catch (e) {
      debugPrint('glossary favorites save failed: $e');
    }
  }

  void _toggleExpanded(GlossaryTerm term) {
    setState(() {
      if (!_expanded.remove(term.id)) _expanded.add(term.id);
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    unawaited(Haptic.copied());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Skopiowano: $text', en: 'Copied: $text')),
        duration: const Duration(milliseconds: 1200),
      ));
  }

  void _show(GlossaryTerm term) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => GlossaryShowView(term: term, initialLang: _target),
    ));
  }

  /// Język wiersza „źródłowego”: polski, a w angielskim interfejsie
  /// angielski — chyba że angielski jest już językiem docelowym.
  GlossaryLang _source(BuildContext context) =>
      context.language == AppLanguage.en && _target != GlossaryLang.en
          ? GlossaryLang.en
          : GlossaryLang.pl;

  @override
  Widget build(BuildContext context) {
    final results = weldingGlossaryIndex.search(
      _search.text,
      category: _category,
      onlyIds: _assistantTermId != null
          ? {_assistantTermId!}
          : _onlyFavorites
              ? _favorites
              : null,
    );
    final source = _source(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            context.tr(pl: 'Słownik spawalniczy', en: 'Welding dictionary')),
        actions: [
          IconButton(
            key: const ValueKey('glossary-fav-filter'),
            tooltip: _onlyFavorites
                ? context.tr(pl: 'Pokaż wszystko', en: 'Show all')
                : context.tr(pl: 'Tylko ulubione', en: 'Favourites only'),
            isSelected: _onlyFavorites,
            icon: Icon(_onlyFavorites ? Icons.star : Icons.star_border,
                color: _onlyFavorites ? kGold : kTextSec),
            onPressed: () {
              unawaited(Haptic.tap());
              _scrollToTop();
              setState(() {
                _assistantTermId = null;
                _onlyFavorites = !_onlyFavorites;
              });
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              // Na niskim ekranie (poziomo, klawiatura) nagłówek się przewija,
              // zamiast wypychać listę poza ekran.
              constraints:
                  BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
              child: SingleChildScrollView(
                child: _header(context, results.length),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      key: const ValueKey('glossary-list'),
                      controller: _list,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(12, 4, 12,
                          24 + MediaQuery.viewPaddingOf(context).bottom),
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final term = results[i];
                        return _TermCard(
                          key: ValueKey('glossary-term-${term.id}'),
                          term: term,
                          source: source,
                          target: _target,
                          expanded: _expanded.contains(term.id),
                          favorite: _favorites.contains(term.id),
                          onToggle: () => _toggleExpanded(term),
                          onFavorite: () => _toggleFavorite(term),
                          onCopy: _copy,
                          onShow: () => _show(term),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int count) {
    final en = context.language == AppLanguage.en;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('glossary-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: kTextSec),
              hintText: context.tr(
                  pl: 'Szukaj: PL, EN, DE, NL, NO lub nr ISO',
                  en: 'Search: PL, EN, DE, NL, NO or ISO no.'),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('glossary-search-clear'),
                      tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
                      icon: const Icon(Icons.close),
                      onPressed: _search.clear,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Tooltip(
                message: context.tr(
                    pl: 'Mój język docelowy', en: 'My target language'),
                child: const Icon(Icons.translate, size: 22, color: kTextSec),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 0,
                  children: [
                    for (final lang in GlossaryLang.targets)
                      ChoiceChip(
                        key: ValueKey('glossary-target-${lang.name}'),
                        label: Text(lang.code),
                        tooltip: en ? lang.nameEn : lang.namePl,
                        selected: _target == lang,
                        showCheckmark: false,
                        selectedColor: kArc,
                        labelStyle: TextStyle(
                          color: _target == lang ? kOnArc : kText,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) => _setTarget(lang),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            key: const ValueKey('glossary-categories'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip(context, null),
                for (final c in GlossaryCategory.values)
                  _categoryChip(context, c),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              _countLabel(context, count),
              key: const ValueKey('glossary-count'),
              style: const TextStyle(color: kTextMut, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _countLabel(BuildContext context, int count) {
    final base = context.tr(pl: 'Pozycji: $count', en: 'Entries: $count');
    if (!_onlyFavorites) return base;
    return '$base · ${context.tr(pl: 'tylko ulubione', en: 'favourites only')}';
  }

  Widget _categoryChip(BuildContext context, GlossaryCategory? c) {
    final selected = _category == c;
    final label = c == null
        ? context.tr(pl: 'Wszystko', en: 'All')
        : context.tr(pl: c.titlePl, en: c.titleEn);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: ValueKey('glossary-cat-${c?.name ?? 'all'}'),
        avatar: Icon(_categoryIcon(c),
            size: 18, color: selected ? kOnArc : kTextSec),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: kArc,
        labelStyle: TextStyle(
          color: selected ? kOnArc : kText,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        onSelected: (_) {
          unawaited(Haptic.tap());
          _scrollToTop();
          setState(() {
            _assistantTermId = null;
            _category = c;
          });
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final String text;
    if (_onlyFavorites && _favorites.isEmpty) {
      text = context.tr(
          pl: 'Nie masz jeszcze ulubionych. Dotknij gwiazdki przy terminie, '
              'żeby mieć go zawsze pod ręką.',
          en: 'No favourites yet. Tap the star next to a term to keep it '
              'at hand.');
    } else {
      text = context.tr(
          pl: 'Nic nie znaleziono. Wpisz fragment słowa w dowolnym z pięciu '
              'języków albo numer ISO (np. 5011, 135).',
          en: 'Nothing found. Type part of a word in any of the five '
              'languages or an ISO number (e.g. 5011, 135).');
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.search_off, size: 40, color: kTextMut),
        const SizedBox(height: 12),
        Text(
          text,
          key: const ValueKey('glossary-empty'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: kTextSec, fontSize: 14, height: 1.4),
        ),
      ],
    );
  }
}

IconData _categoryIcon(GlossaryCategory? c) => switch (c) {
      null => Icons.apps,
      GlossaryCategory.process => Icons.bolt,
      GlossaryCategory.imperfection => Icons.report_problem_outlined,
      GlossaryCategory.joint => Icons.merge_type,
      GlossaryCategory.position => Icons.open_with,
      GlossaryCategory.material => Icons.inventory_2_outlined,
      GlossaryCategory.piping => Icons.plumbing,
      GlossaryCategory.testing => Icons.fact_check_outlined,
      GlossaryCategory.tools => Icons.handyman_outlined,
      GlossaryCategory.safety => Icons.health_and_safety_outlined,
      GlossaryCategory.phrase => Icons.forum_outlined,
    };

class _TermCard extends StatelessWidget {
  const _TermCard({
    super.key,
    required this.term,
    required this.source,
    required this.target,
    required this.expanded,
    required this.favorite,
    required this.onToggle,
    required this.onFavorite,
    required this.onCopy,
    required this.onShow,
  });

  final GlossaryTerm term;
  final GlossaryLang source;
  final GlossaryLang target;
  final bool expanded;
  final bool favorite;
  final VoidCallback onToggle;
  final VoidCallback onFavorite;
  final void Function(String text) onCopy;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final tag = term.isoLabel ?? term.code;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('glossary-toggle-${term.id}'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            term.text(source),
                            style: const TextStyle(
                              color: kText,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            term.text(target),
                            key: ValueKey('glossary-target-text-${term.id}'),
                            style: const TextStyle(
                              color: kArc,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          if (tag != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              tag,
                              style: const TextStyle(
                                  color: kTextMut, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('glossary-copy-${term.id}-target'),
                      tooltip: en
                          ? 'Copy (${target.code})'
                          : 'Kopiuj (${target.code})',
                      icon: const Icon(Icons.copy_rounded, color: kTextSec),
                      onPressed: () => onCopy(term.text(target)),
                    ),
                    IconButton(
                      key: ValueKey('glossary-fav-${term.id}'),
                      tooltip: favorite
                          ? context.tr(
                              pl: 'Usuń z ulubionych',
                              en: 'Remove from favourites')
                          : context.tr(
                              pl: 'Dodaj do ulubionych',
                              en: 'Add to favourites'),
                      icon: Icon(favorite ? Icons.star : Icons.star_border,
                          color: favorite ? kGold : kTextMut),
                      onPressed: onFavorite,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) _details(context, en),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, bool en) {
    final def = en ? (term.defEn ?? term.defPl) : (term.defPl ?? term.defEn);
    return Padding(
      key: ValueKey('glossary-details-${term.id}'),
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: 4),
          for (final lang in GlossaryLang.values) _langRow(context, lang, en),
          if (def != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                def,
                style:
                    const TextStyle(color: kTextSec, fontSize: 13, height: 1.4),
              ),
            ),
          ],
          if (term.isoLabel != null && term.code != null) ...[
            const SizedBox(height: 6),
            Text(term.code!,
                style: const TextStyle(color: kTextMut, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: ValueKey('glossary-show-${term.id}'),
              onPressed: onShow,
              icon: const Icon(Icons.open_in_full),
              label: Text(context.tr(
                  pl: 'Pokaż rozmówcy', en: 'Show to the other person')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _langRow(BuildContext context, GlossaryLang lang, bool en) {
    final text = term.text(lang);
    final syn = term.synonymsFor(lang);
    final isTarget = lang == target;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            lang.code,
            style: TextStyle(
              color: isTarget ? kArc : kTextMut,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: isTarget ? kArc : kText,
                    fontSize: 15,
                    fontWeight: isTarget ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (syn.isNotEmpty)
                  Text(
                    '${context.tr(pl: 'także', en: 'also')}: ${syn.join(', ')}',
                    style: const TextStyle(color: kTextMut, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          key: ValueKey('glossary-copy-${term.id}-${lang.name}'),
          tooltip: en ? 'Copy (${lang.code})' : 'Kopiuj (${lang.code})',
          icon: const Icon(Icons.copy_rounded, size: 20, color: kTextSec),
          onPressed: () => onCopy(text),
        ),
      ],
    );
  }
}

/// Tryb „pokaż rozmówcy”: pełny ekran z ogromnym napisem w języku
/// docelowym. Przycisk lub dwuklik obraca napis o 180° (rozmówca stoi
/// naprzeciwko), przesunięcie w dół albo „Zamknij” wraca do listy.
class GlossaryShowView extends StatefulWidget {
  const GlossaryShowView({
    super.key,
    required this.term,
    this.initialLang = GlossaryLang.de,
  });

  final GlossaryTerm term;
  final GlossaryLang initialLang;

  @override
  State<GlossaryShowView> createState() => _GlossaryShowViewState();
}

class _GlossaryShowViewState extends State<GlossaryShowView> {
  late GlossaryLang _lang = widget.initialLang;
  bool _rotated = false;

  void _toggleRotation() {
    unawaited(Haptic.tap());
    setState(() => _rotated = !_rotated);
  }

  static double _fontSize(String text) {
    final n = text.length;
    if (n <= 14) return 60;
    if (n <= 28) return 48;
    if (n <= 60) return 38;
    return 30;
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.term.text(_lang);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('glossary-show-close'),
                  tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
                  icon: const Icon(Icons.close, color: kText),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    widget.term.text(GlossaryLang.pl),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kTextSec, fontSize: 14),
                  ),
                ),
                IconButton(
                  key: const ValueKey('glossary-show-rotate'),
                  tooltip: context.tr(pl: 'Obróć o 180°', en: 'Rotate 180°'),
                  icon: const Icon(Icons.screen_rotation, color: kText),
                  onPressed: _toggleRotation,
                ),
              ],
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _toggleRotation,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 600) {
                    Navigator.of(context).maybePop();
                  }
                },
                child: Center(
                  child: RotatedBox(
                    key: const ValueKey('glossary-show-rotation'),
                    quarterTurns: _rotated ? 2 : 0,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Text(
                        text,
                        key: const ValueKey('glossary-show-text'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _fontSize(text),
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final lang in GlossaryLang.targets)
                    ChoiceChip(
                      key: ValueKey('glossary-show-lang-${lang.name}'),
                      label: Text(lang.code),
                      selected: _lang == lang,
                      showCheckmark: false,
                      selectedColor: kArc,
                      labelStyle: TextStyle(
                        color: _lang == lang ? kOnArc : kText,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _lang = lang),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                context.tr(
                    pl: 'Dwuklik lub ⟳ obraca napis dla osoby naprzeciwko. '
                        'Przesuń w dół, aby zamknąć.',
                    en: 'Double-tap or ⟳ flips the text for the person '
                        'opposite. Swipe down to close.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextMut, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
