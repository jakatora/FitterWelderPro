// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/help_entries.dart';
import '../i18n/app_language.dart';
import '../services/help_search.dart';

// Help v2 — searchable knowledge base for fitters and welders.
// Layout:
//   ┌────────────────────────────────────────────┐
//   │  AppBar: "Pomoc"                            │
//   ├────────────────────────────────────────────┤
//   │  [🔎 Szukaj: WPS, NACE, preheat...        ] │
//   ├────────────────────────────────────────────┤
//   │  [All] [TIG] [Materials] [PWHT] [NDT] ...   │ ← horizontal chips
//   ├────────────────────────────────────────────┤
//   │  Empty search → category cards              │
//   │  Active search → flat result list w/score  │
//   └────────────────────────────────────────────┘

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);
const _kAccent = Color(0xFF2ECC71);

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  String? _categoryFilter;
  final _expandedEntries = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = value;
      });
    });
  }

  void _toggleCategory(String? id) {
    setState(() {
      _categoryFilter = (_categoryFilter == id) ? null : id;
    });
  }

  void _toggleExpanded(String entryId) {
    setState(() {
      if (_expandedEntries.contains(entryId)) {
        _expandedEntries.remove(entryId);
      } else {
        _expandedEntries.add(entryId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    final results = _query.trim().isEmpty
        ? const <HelpSearchResult>[]
        : searchHelp(_query, lang, categoryFilter: _categoryFilter);

    final isSearching = _query.trim().isNotEmpty;
    final visibleCats = _categoryFilter == null
        ? kHelpCategories
        : kHelpCategories.where((c) => c.id == _categoryFilter).toList();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(context.tr(pl: 'Pomoc', en: 'Help')),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: context.tr(pl: 'O bazie wiedzy', en: 'About knowledge base'),
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Search bar ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Color(0xFFE8ECF0)),
              decoration: InputDecoration(
                hintText: context.tr(
                  pl: 'Szukaj: WPS, NACE, preheat, NPSH...',
                  en: 'Search: WPS, NACE, preheat, NPSH...',
                ),
                hintStyle: const TextStyle(color: _kTextMut, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: _kTextSec),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: _kTextSec),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: _kCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kAccent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // ─── Filter chips (horizontal scroll) ───────────────────────────
          SizedBox(
            height: 38,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: context.tr(pl: 'Wszystko', en: 'All'),
                  active: _categoryFilter == null,
                  onTap: () => _toggleCategory(null),
                  count: kHelpCategories.fold<int>(
                      0, (sum, c) => sum + c.entries.length),
                ),
                ...kHelpCategories.map((cat) => _FilterChip(
                      label: cat.title(lang),
                      active: _categoryFilter == cat.id,
                      onTap: () => _toggleCategory(cat.id),
                      count: cat.entries.length,
                      accent: Color(cat.accentArgb),
                    )),
              ],
            ),
          ),

          // ─── Results / category tree ─────────────────────────────────────
          Expanded(
            child: isSearching
                ? _buildSearchResults(results, lang)
                : _buildCategoryTree(visibleCats, lang),
          ),
        ],
      ),
    );
  }

  // ─── Search results view ──────────────────────────────────────────────────
  Widget _buildSearchResults(List<HelpSearchResult> results, AppLanguage lang) {
    if (results.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        title: context.tr(
          pl: 'Brak wyników',
          en: 'No matches',
        ),
        subtitle: context.tr(
          pl: 'Spróbuj innych słów kluczowych (np. "wps", "purge", "torque").',
          en: 'Try different keywords (e.g. "wps", "purge", "torque").',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        final isExpanded = _expandedEntries.contains(r.entry.id);
        return _SearchResultCard(
          result: r,
          lang: lang,
          expanded: isExpanded,
          onTap: () => _toggleExpanded(r.entry.id),
        );
      },
    );
  }

  // ─── Category tree view (empty search) ────────────────────────────────────
  Widget _buildCategoryTree(List<HelpCategory> cats, AppLanguage lang) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final cat = cats[i];
        return _CategoryCard(
          category: cat,
          lang: lang,
          expandedEntries: _expandedEntries,
          onToggleEntry: _toggleExpanded,
        );
      },
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text(
          context.tr(pl: 'O bazie wiedzy', en: 'About knowledge base'),
          style: const TextStyle(color: Color(0xFFE8ECF0)),
        ),
        content: Text(
          context.tr(
            pl: 'Baza zawiera ${kHelpCategories.fold<int>(0, (s, c) => s + c.entries.length)} tematów w ${kHelpCategories.length} kategoriach: '
                'spawanie TIG, materiały, NACE, PWHT, NDT, kody ASME/API, BHP. '
                'Każdy temat dwujęzyczny (PL/EN). '
                'Wyszukiwarka uwzględnia synonimy (purge / back-purge / argon → ten sam wpis).',
            en: 'Knowledge base: ${kHelpCategories.fold<int>(0, (s, c) => s + c.entries.length)} topics in ${kHelpCategories.length} categories: '
                'TIG welding, materials, NACE, PWHT, NDT, ASME/API codes, safety. '
                'Bilingual content (PL/EN). '
                'Search supports synonyms (purge / back-purge / argon → same entry).',
          ),
          style: const TextStyle(color: _kTextSec, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr(pl: 'OK', en: 'OK')),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Filter chip — horizontal scrollable selector for categories.
// ════════════════════════════════════════════════════════════════════════════
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int count;
  final Color? accent;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.count,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? _kAccent;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.18) : _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? color : _kBorder,
              width: active ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? color : _kTextSec,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (active ? color : _kBorder).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: active ? color : _kTextMut,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Category card — used when search is empty. Renders the category header +
// all its entries as expandable rows.
// ════════════════════════════════════════════════════════════════════════════
class _CategoryCard extends StatelessWidget {
  final HelpCategory category;
  final AppLanguage lang;
  final Set<String> expandedEntries;
  final void Function(String) onToggleEntry;

  const _CategoryCard({
    required this.category,
    required this.lang,
    required this.expandedEntries,
    required this.onToggleEntry,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Color(category.accentArgb);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    category.icon,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.title(lang),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE8ECF0),
                        ),
                      ),
                      Text(
                        category.subtitle(lang),
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kTextMut,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${category.entries.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Entries
          ...category.entries.map((entry) {
            final expanded = expandedEntries.contains(entry.id);
            return _EntryRow(
              entry: entry,
              lang: lang,
              expanded: expanded,
              onTap: () => onToggleEntry(entry.id),
              accent: accent,
            );
          }),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final HelpEntry entry;
  final AppLanguage lang;
  final bool expanded;
  final VoidCallback onTap;
  final Color accent;
  final List<String> matchedTerms;

  const _EntryRow({
    required this.entry,
    required this.lang,
    required this.expanded,
    required this.onTap,
    required this.accent,
    this.matchedTerms = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: _kBorder.withValues(alpha: 0.5)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _HighlightedText(
                      text: entry.question(lang),
                      terms: matchedTerms,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: expanded ? accent : const Color(0xFFE8ECF0),
                      ),
                      highlightColor: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: expanded ? accent : _kTextMut,
                    ),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                _HighlightedText(
                  text: entry.answer(lang),
                  terms: matchedTerms,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kTextSec,
                    height: 1.5,
                  ),
                  highlightColor: accent,
                ),
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.tags
                        .map((tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Search result card — flat list when user types into search. Shows the
// category badge so the user knows where the entry lives in the tree.
// ════════════════════════════════════════════════════════════════════════════
class _SearchResultCard extends StatelessWidget {
  final HelpSearchResult result;
  final AppLanguage lang;
  final bool expanded;
  final VoidCallback onTap;

  const _SearchResultCard({
    required this.result,
    required this.lang,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Color(result.category.accentArgb);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge on top
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        result.category.icon,
                        size: 12,
                        color: accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        result.category.title(lang),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _EntryRow(
            entry: result.entry,
            lang: lang,
            expanded: expanded,
            onTap: onTap,
            accent: accent,
            matchedTerms: result.matchedTerms,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Highlight matched terms in body text. Case-insensitive, accent-folded.
// ════════════════════════════════════════════════════════════════════════════
class _HighlightedText extends StatelessWidget {
  final String text;
  final List<String> terms;
  final TextStyle style;
  final Color highlightColor;

  const _HighlightedText({
    required this.text,
    required this.terms,
    required this.style,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) {
      return Text(text, style: style);
    }
    final normalizedText = normalizeForSearch(text);
    final segments = <_Seg>[];
    var cursor = 0;
    while (cursor < text.length) {
      var bestStart = -1;
      var bestEnd = -1;
      for (final term in terms) {
        final idx = normalizedText.indexOf(term, cursor);
        if (idx >= 0 && (bestStart < 0 || idx < bestStart)) {
          bestStart = idx;
          bestEnd = idx + term.length;
        }
      }
      if (bestStart < 0) {
        segments.add(_Seg(text.substring(cursor), false));
        break;
      }
      if (bestStart > cursor) {
        segments.add(_Seg(text.substring(cursor, bestStart), false));
      }
      segments.add(_Seg(text.substring(bestStart, bestEnd), true));
      cursor = bestEnd;
    }

    return RichText(
      text: TextSpan(
        style: style,
        children: segments
            .map((seg) => TextSpan(
                  text: seg.text,
                  style: seg.highlight
                      ? TextStyle(
                          color: highlightColor,
                          fontWeight: FontWeight.w800,
                          backgroundColor:
                              highlightColor.withValues(alpha: 0.15),
                        )
                      : null,
                ))
            .toList(),
      ),
    );
  }
}

class _Seg {
  final String text;
  final bool highlight;
  const _Seg(this.text, this.highlight);
}

// ════════════════════════════════════════════════════════════════════════════
// Empty state (no search matches).
// ════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _kTextMut),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8ECF0),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: _kTextSec),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
